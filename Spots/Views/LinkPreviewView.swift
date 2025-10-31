//
//  LinkPreviewView.swift
//  Spots
//

import SwiftUI
import LinkPresentation
import UIKit

struct LinkPreviewView: View {
    let url: URL

    @State private var metadata: LPLinkMetadata? = nil
    @State private var previewImage: UIImage? = nil
    @State private var aspectRatioHint: CGFloat? = nil   // alto/ancho (h/w) persistido
    @State private var failed = false

    // Ratio típico de OG images: 1200x630 → h/w ≈ 0.525
    private let defaultLinkRatio: CGFloat = 0.525

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Imagen (o placeholder) con altura estable usando ratio persistido
            Group {
                if let img = previewImage {
                    // Usamos el MISMO ratio para que no cambie de altura
                    let ratio = aspectRatioHint ?? max(0.2, min(3.0, img.size.height / max(1, img.size.width)))
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(1.0 / ratio, contentMode: .fit) // width/height = 1/(h/w)
                        .cornerRadius(10)
                } else {
                    // Placeholder estable mientras llega metadata/imagen
                    let ratio = aspectRatioHint ?? defaultLinkRatio
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(.systemGray6))
                            .aspectRatio(1.0 / ratio, contentMode: .fit)
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Cargando vista previa…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                UIApplication.shared.open(url)
            }

            // Título y host
            VStack(alignment: .leading, spacing: 2) {
                if let title = (metadata?.title ?? metadata?.originalURL?.host), !title.isEmpty {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                        .foregroundColor(.primary)
                } else {
                    Text(displayHost(url))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundColor(.primary)
                }
                Text(displayHost(url))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            await loadPreview()
        }
    }

    // MARK: - Carga y caché

    private func loadPreview() async {
        let key = url.absoluteString + "#og"

        // 1) Ratio persistido → altura estable inmediata
        if aspectRatioHint == nil, let r = MediaCache.shared.ratio(forKey: key) {
            aspectRatioHint = r
        }

        // 2) Imagen cacheada (RAM/disco)
        if previewImage == nil, let cached = MediaCache.shared.cachedImage(for: key) {
            await MainActor.run {
                self.previewImage = cached
                // recalcula ratio por si no existía
                let r = max(0.2, min(3.0, cached.size.height / max(1, cached.size.width)))
                self.aspectRatioHint = self.aspectRatioHint ?? r
                MediaCache.shared.setRatio(r, forKey: key)
            }
            // Seguimos para cargar metadata (título/host) si faltara
        }

        // 3) Metadata con LinkPresentation
        if metadata == nil && !failed {
            do {
                let provider = LPMetadataProvider()
                let meta = try await provider.startFetchingMetadata(for: url)
                await MainActor.run { self.metadata = meta }

                // 4) Imagen OG vía NSItemProvider → cache + ratio
                if let img = await loadImage(from: meta) {
                    await MainActor.run {
                        self.previewImage = img
                        let r = max(0.2, min(3.0, img.size.height / max(1, img.size.width)))
                        self.aspectRatioHint = r
                        MediaCache.shared.storeImage(img, forKey: key)
                        MediaCache.shared.setRatio(r, forKey: key)
                    }
                } else if previewImage == nil {
                    // si no hay imagen tras metadata, mantenemos placeholder estable
                    await MainActor.run { self.failed = false } // no lo tratamos como fallo total
                }
            } catch {
                print("⚠️ Sin metadata para \(url): \(error.localizedDescription)")
                await MainActor.run { self.failed = true }
            }
        }
    }

    private func loadImage(from metadata: LPLinkMetadata) async -> UIImage? {
        // Prioridad: imageProvider; fallback: iconProvider
        if let provider = metadata.imageProvider,
           let img = await loadUIImage(from: provider) {
            return img
        }
        if let provider = metadata.iconProvider,
           let img = await loadUIImage(from: provider) {
            return img
        }
        return nil
    }

    private func loadUIImage(from provider: NSItemProvider) async -> UIImage? {
        // Primero intento como UIImage
        if provider.canLoadObject(ofClass: UIImage.self) {
            return await withCheckedContinuation { cont in
                provider.loadObject(ofClass: UIImage.self) { obj, _ in
                    cont.resume(returning: obj as? UIImage)
                }
            }
        }
        // Fallback: archivo (png/jpg)
        let types = ["public.png", "public.jpeg", "public.jpg"]
        for t in types {
            if provider.hasItemConformingToTypeIdentifier(t) {
                return await withCheckedContinuation { cont in
                    provider.loadItem(forTypeIdentifier: t, options: nil) { item, _ in
                        if let url = item as? URL, let data = try? Data(contentsOf: url), let img = UIImage(data: data) {
                            cont.resume(returning: img)
                        } else {
                            cont.resume(returning: nil)
                        }
                    }
                }
            }
        }
        return nil
    }

    private func displayHost(_ url: URL) -> String {
        if let host = url.host {
            return host.replacingOccurrences(of: "www.", with: "")
        }
        return url.absoluteString
    }
}
