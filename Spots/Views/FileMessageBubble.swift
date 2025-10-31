//
//  FileMessageBubble.swift
//  Spots
//

import SwiftUI
import AVKit
import AVFoundation
import QuickLook
import UIKit

import FirebaseAuth
import FirebaseFirestore
struct FileMessageBubble: View {
    let msg: Message
    let isMine: Bool
    let groupRole: GroupRole
    let isGroup: Bool
    let senderName: String?

    private var timeString: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return f.string(from: msg.createdAt)
    }
    
    

    @Environment(\.colorScheme) private var colorScheme

    @EnvironmentObject var vm: ChatViewModel
    
    // BEGIN INSERT — PALETA TELEGRAM (FIJA)
    private enum TG {
        static let incomingLight = Color.white
        static let incomingDark  = Color(red: 0.17, green: 0.19, blue: 0.21) // ≈ #2B3036
        static let outgoingLight = Color(red: 0.83, green: 0.93, blue: 1.00) // ≈ #D4ECFF
        static let outgoingDark  = Color(red: 0.18, green: 0.46, blue: 0.77) // ≈ #2E76C5
        static let textLight     = Color.black
        static let textDark      = Color.white
        static let timeGrey      = Color(red: 0.56, green: 0.56, blue: 0.60) // #8E8E93
    }

    private var bubbleTextColor: Color {
        colorScheme == .dark ? TG.textDark : TG.textLight
    }
    // END INSERT — PALETA TELEGRAM (FIJA)


    // BEGIN INSERT — palette para color de nombre (igual a MessageBubble)
    private let senderPalette: [Color] = [
        Color(red: 1.00, green: 0.48, blue: 0.00), // naranja fluo
        Color(red: 0.22, green: 1.00, blue: 0.08), // verde fluo
        Color(red: 0.00, green: 0.90, blue: 1.00)  // azul fluo
    ]
    private func nameColorFor(_ uid: String) -> Color {
        var h: UInt64 = 0
        for u in uid.unicodeScalars { h = ((h << 5) &+ h) &+ UInt64(u.value) }
        let idx = Int(h % UInt64(senderPalette.count))
        return senderPalette[idx]
    }
    // END INSERT — palette para color de nombre



    // BEGIN REPLACE — fondo con colores fijos
    private var bubbleBackground: Color {
        if isMine {
            return colorScheme == .dark ? TG.outgoingDark : TG.outgoingLight
        } else {
            return colorScheme == .dark ? TG.incomingDark : TG.incomingLight
        }
    }
    // END REPLACE — fondo con colores fijos


    // QuickLook
    @State private var localFileURL: URL?
    @State private var quickLookTitle: String = "Archivo"
    @State private var quickLookItem: QLItem? = nil
    @State private var showDeleteAlert = false
    @State private var showForwardPicker = false
    
    

    private struct QLItem: Identifiable {
        let id = UUID()
        let url: URL
        let title: String
    }

    // Descarga genérica (archivos no imagen/vídeo)
    @State private var isDownloading = false

    // Miniaturas cacheadas
    @State private var cachedImage: UIImage? = nil
    @State private var aspectRatioHint: CGFloat? = nil // alto/ancho persistido para placeholder estable

    private var bubbleMaxWidth: CGFloat {
        min(UIScreen.main.bounds.width * 0.66, 320)
    }

    var body: some View {
        HStack(alignment: .bottom) {
            if isMine { Spacer(minLength: 0) }

            VStack(alignment: .leading, spacing: 8) {
                
                if let name = senderName, !isMine, isGroup {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(name)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(nameColorFor(msg.senderId))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.bottom, 2)
                }

                filePreviewContent

                // Título / nombre de archivo debajo de la previsualización
                /*if let name = msg.fileName, !name.isEmpty {
                    Text(name)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
                }*/


                // Caption opcional debajo del nombre
                if !msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(msg.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: bubbleMaxWidth, alignment: .leading)
                }

                // Progreso de subida (cuando aún no hay fileUrl)
                if msg.fileUrl == nil, let p = msg.uploadProgress, p < 1.0 {
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: bubbleMaxWidth)
                }

                // Progreso de descarga (para archivos genéricos) — indeterminado
                if isDownloading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(maxWidth: bubbleMaxWidth, alignment: .trailing)
                }
            }
            .padding(.vertical, 4)
            .padding(.bottom, 16) // más hueco para la hora/‘· editado’

            if !isMine { Spacer(minLength: 0) }
        }
        .sheet(item: $quickLookItem) { item in
            QuickLookPreview(url: item.url, title: item.title)
        }
        .contextMenu {
            if isMine && !msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    NotificationCenter.default.post(
                        name: .init("Chat.StartEditMessage"),
                        object: nil,
                        userInfo: ["id": msg.id]
                    )
                } label: {
                    Label("Editar", systemImage: "pencil")
                }
            }
            Button { vm.setReply(to: msg) } label: {
                Label("Responder", systemImage: "arrowshape.turn.up.left")
            }
            Button { showForwardPicker = true } label: {
                Label("Reenviar…", systemImage: "arrowshape.turn.up.right")
            }
            if !msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { UIPasteboard.general.string = msg.text } label: {
                    Label("Copiar", systemImage: "doc.on.doc")
                }
            }
            if isMine {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("Borrar", systemImage: "trash")
                }
            }
        }
        .alert("¿Borrar mensaje?", isPresented: $showDeleteAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Borrar", role: .destructive) {
                Task { await vm.deleteMessage(msg) }
            }
        }
        .sheet(isPresented: $showForwardPicker) {
            ForwardPickerSheet(currentChatId: msg.chatId) { targetId in
                Task { await forward(msg, to: targetId) }
            }
        }
    }

    // MARK: - Contenido de preview por tipo
    @ViewBuilder
    private var filePreviewContent: some View {
        let kind = detectFileKind()

        if kind.isImage {
            // IMAGEN
            ZStack(alignment: .bottomTrailing) {
                if let image = cachedImage {
                    // ratio = h/w, pero .aspectRatio espera w/h → 1/ratio
                    let r = max(0.2, min(3.0, image.size.height / max(1, image.size.width)))
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(1.0 / r, contentMode: .fit)
                        .frame(maxWidth: bubbleMaxWidth)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else if msg.fileUrl == nil {
                    // Subiendo todavía
                    placeholderImage(width: bubbleMaxWidth, ratio: aspectRatioHint ?? defaultImageAspect, mine: isMine) {
                        ProgressView()
                    }
                } else {
                    // Placeholder estable mientras cargamos
                    placeholderImage(width: bubbleMaxWidth, ratio: aspectRatioHint ?? defaultImageAspect, mine: isMine) {
                        ProgressView()
                    }
                    .task {
                        guard let urlStr = msg.fileUrl else { return }
                        // Usa ratio persistido si existe (para placeholder sin "bailes")
                        if aspectRatioHint == nil, let r = MediaCache.shared.ratio(forKey: urlStr) {
                            aspectRatioHint = r
                        }
                        if let img = MediaCache.shared.cachedImage(for: urlStr) {
                            cachedImage = img
                            applyRatio(from: img, key: urlStr)
                        } else if let img = await MediaCache.shared.image(for: urlStr) {
                            await MainActor.run {
                                cachedImage = img
                                applyRatio(from: img, key: urlStr)
                            }
                        }
                    }
                }

                // Lupa para abrir (si hay algo para mostrar)
                if msg.fileUrl != nil || localFileURL != nil || cachedImage != nil {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(8)
                        .background(.black.opacity(0.35))
                        .clipShape(Circle())
                        .padding(6)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { openQuickLook() }

        } else if kind.isVideo {
            // VÍDEO (mostramos thumb si la tenemos o placeholder con botón play)
            ZStack(alignment: .center) {
                if let thumb = cachedImage {
                    let r = aspectRatioHint ?? defaultVideoAspect
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(1.0 / r, contentMode: .fit) // w/h
                        .frame(maxWidth: bubbleMaxWidth)
                        .clipped()
                        .cornerRadius(12)
                } else {
                    // Placeholder estable mientras se genera/descarga thumb
                    placeholderVideo(width: bubbleMaxWidth, ratio: aspectRatioHint ?? defaultVideoAspect, mine: isMine) {
                        ProgressView()
                    }
                    .task {
                        // Primero ratio persistido si existe
                        let thumbKey = (msg.thumbnailUrl ?? msg.fileUrl ?? "") + "_thumb"
                        if let r = MediaCache.shared.ratio(forKey: thumbKey) {
                            aspectRatioHint = r
                        }

                        if let thumbUrl = msg.thumbnailUrl {
                            if let img = MediaCache.shared.cachedImage(for: thumbUrl) {
                                cachedImage = img
                                applyRatio(from: img, key: thumbUrl)
                            } else if let img = await MediaCache.shared.image(for: thumbUrl) {
                                await MainActor.run {
                                    cachedImage = img
                                    applyRatio(from: img, key: thumbUrl)
                                }
                            }
                        } else if let urlStr = msg.fileUrl, let url = URL(string: urlStr) {
                            // genera thumb local y cachea
                            if let img = MediaCache.shared.cachedImage(for: thumbKey) {
                                cachedImage = img
                                applyRatio(from: img, key: thumbKey)
                            } else if let img = await generateVideoThumbnail(url: url) {
                                await MainActor.run {
                                    cachedImage = img
                                    applyRatio(from: img, key: thumbKey)
                                }
                                MediaCache.shared.storeImage(img, forKey: thumbKey)
                            }
                        }
                    }
                }

                // Botón de “play” superpuesto (siempre visible en vídeos)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
                    .shadow(radius: 2)
            }
            .contentShape(Rectangle())
            .onTapGesture { openQuickLook() }

        } else {
            // ARCHIVO genérico (PDF, ZIP, etc.)
            placeholderGeneric(width: bubbleMaxWidth, mine: isMine)
                .overlay(alignment: .bottomTrailing) {
                    if isDownloading {
                        ProgressView() // indeterminado
                            .tint(.white)
                            .padding(8)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { openQuickLook() }
        }
    }

    // MARK: - Helpers de UI (placeholders con altura estable)

    private var defaultImageAspect: CGFloat { 0.75 }     // 3:4  (h/w)
    private var defaultVideoAspect: CGFloat { 9.0 / 16 } // 9:16 (h/w)

    @ViewBuilder
    private func placeholderImage(width: CGFloat, ratio: CGFloat, mine: Bool, @ViewBuilder overlay: () -> some View) -> some View {
        ZStack {
            Rectangle()
                .fill(mine ? Color.blue.opacity(0.08) : Color.gray.opacity(0.08))
                .frame(width: width, height: width * ratio) // h = w * (h/w)
                .cornerRadius(12)
            overlay()
        }
    }

    @ViewBuilder
    private func placeholderVideo(width: CGFloat, ratio: CGFloat, mine: Bool, @ViewBuilder overlay: () -> some View) -> some View {
        ZStack {
            Rectangle()
                .fill(mine ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                .frame(width: width, height: width * ratio)
                .cornerRadius(12)
            overlay()
        }
    }

    @ViewBuilder
    private func placeholderGeneric(width: CGFloat, mine: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.fill")
                .font(.title2)
            Text(msg.fileName ?? "Archivo")
                .font(.subheadline.bold())
                .lineLimit(1)
        }
        .foregroundColor(bubbleTextColor)
        .padding(12)
        .frame(maxWidth: width, alignment: .leading)
        // BEGIN REPLACE — fondo + radios + overlay dentro (archivos)
        .background(bubbleBackground)
        .clipShape(GroupedBubbleShape(isMine: isMine, role: groupRole, radius: 20))
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 6) {
                Text(timeString)
                if msg.editedAt != nil { Text("· editado") }
            }
            .font(.caption2)
            .foregroundColor(
                (colorScheme == .dark && isMine)
                ? Color.white.opacity(0.9)   // igual que MessageBubble saliente en dark
                : TG.timeGrey                // igual que MessageBubble en resto
            )
            .padding(.trailing, isMine ? 8 : 12)
            .padding(.bottom, 12)
        }
        // END REPLACE — fondo + radios + overlay dentro (archivos)

    }

    // Persistimos el aspect ratio cuando tenemos la imagen real
    private func applyRatio(from image: UIImage, key: String) {
        let r = max(0.2, min(3.0, image.size.height / max(1, image.size.width))) // h/w
        aspectRatioHint = r
        MediaCache.shared.setRatio(r, forKey: key)
    }

    // MARK: - Detección robusta de tipo (image / video / otro)
    private func detectFileKind() -> (isImage: Bool, isVideo: Bool) {
        let type = (msg.fileType ?? "").lowercased()
        let name = (msg.fileName ?? "").lowercased()
        let urlStr = (msg.fileUrl ?? "").lowercased()
        let urlExt = URL(string: urlStr)?.pathExtension.lowercased() ?? ""

        let isImageMIME = type.hasPrefix("image/")
        let isVideoMIME = type.hasPrefix("video/")

        let isImageExt = [name, urlExt].contains { $0.hasSuffix(".jpg") || $0.hasSuffix(".jpeg") || $0.hasSuffix(".png") || $0.hasSuffix(".gif") || $0.hasSuffix(".heic") }
        let isVideoExt = [name, urlExt].contains { $0.hasSuffix(".mp4") || $0.hasSuffix(".mov") || $0.hasSuffix(".m4v") || $0.hasSuffix(".avi") || $0.hasSuffix(".mkv") }

        return (isImageMIME || isImageExt, isVideoMIME || isVideoExt)
    }

    // MARK: - QuickLook / descarga con nombre y extensión correctos
    private func openQuickLook() {
        // 1) Si ya hay un archivo local válido, abrir
        if let local = localFileURL {
            let title = msg.fileName ?? local.lastPathComponent
            quickLookItem = QLItem(url: local, title: title)
            return
        }

        // 2) Si es imagen y tenemos cachedImage, volcar a un JPG temp y abrir
        if detectFileKind().isImage, let img = cachedImage {
            let fileName = (msg.fileName?.isEmpty == false ? msg.fileName! : "image") + ".jpg"
            let url = uniqueTempURL(fileName: sanitizeFileName(fileName))
            if let data = img.jpegData(compressionQuality: 0.9) {
                try? data.write(to: url, options: .atomic)
                localFileURL = url
                quickLookItem = QLItem(url: url, title: msg.fileName ?? "Imagen")
                return
            }
        }

        // 3) Descargar remoto, mover con extensión correcta y abrir
        guard let urlStr = msg.fileUrl, let remoteURL = URL(string: urlStr) else { return }

        Task {
            await MainActor.run { isDownloading = true }

            do {
                let (tmpURL, _) = try await URLSession.shared.download(from: remoteURL)

                // Nombre/extension final
                let baseName = (msg.fileName?.isEmpty == false ? msg.fileName! : remoteURL.lastPathComponent)
                let extFromName = (baseName as NSString).pathExtension
                let extFromURL = remoteURL.pathExtension
                let extFromMime = fileExtension(forMime: msg.fileType ?? "")
                let ext = [extFromName, extFromURL, extFromMime].first(where: { !$0.isEmpty }) ?? "bin"

                let cleanBase = ((baseName as NSString).deletingPathExtension.isEmpty ? "archivo" : (baseName as NSString).deletingPathExtension)
                let finalName = sanitizeFileName("\(cleanBase).\(ext)")
                let destURL = uniqueTempURL(fileName: finalName)

                // Mover al destino con nombre final
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.moveItem(at: tmpURL, to: destURL)

                await MainActor.run {
                    self.localFileURL = destURL
                    self.isDownloading = false
                    self.quickLookItem = QLItem(url: destURL, title: msg.fileName ?? finalName)
                }
            } catch {
                await MainActor.run { self.isDownloading = false }
                print("❌ Error descargando archivo:", error.localizedDescription)
            }
        }
    }

    // MARK: - Helpers de archivo
    private func uniqueTempURL(fileName: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
        var url = dir.appendingPathComponent(fileName)
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var i = 1
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base)-\(i).\(ext)")
            i += 1
        }
        return url
    }

    private func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.isEmpty ? "archivo.bin" : cleaned
    }

    private func fileExtension(forMime mime: String) -> String {
        let m = mime.lowercased()
        if m.hasPrefix("image/jpeg") { return "jpg" }
        if m.hasPrefix("image/png")  { return "png" }
        if m.hasPrefix("image/heic") { return "heic" }
        if m.hasPrefix("image/gif")  { return "gif" }
        if m.hasPrefix("video/mp4")  { return "mp4" }
        if m.hasPrefix("video/quicktime") { return "mov" }
        if m.hasPrefix("audio/mpeg") { return "mp3" }
        if m.hasPrefix("audio/mp4")  { return "m4a" }
        if m.hasPrefix("application/pdf") { return "pdf" }
        if m.hasPrefix("application/zip") { return "zip" }
        if m.hasPrefix("text/plain") { return "txt" }
        return ""
    }

    private func generateVideoThumbnail(url: URL) async -> UIImage? {
        // Carga asíncrona robusta del asset (remoto/local) y generación del frame
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])

        // Espera a que el asset tenga datos suficientes
        _ = try? await asset.load(.duration)
        _ = try? await asset.load(.tracks)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero

        // Reintentos por si el primer frame es negro
        let candidates: [CMTime] = [
            CMTime(seconds: 0.1, preferredTimescale: 600),
            CMTime(seconds: 1.0, preferredTimescale: 600),
            CMTime(seconds: 2.0, preferredTimescale: 600)
        ]

        for t in candidates {
            if let cg = try? generator.copyCGImage(at: t, actualTime: nil) {
                return UIImage(cgImage: cg)
            }
        }
        return nil
    }


    private func forward(_ message: Message, to targetChatId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        let msgRef = db.collection("chats").document(targetChatId).collection("messages").document()
        let now = Date()

        var data: [String: Any] = [
            "id": msgRef.documentID,
            "senderId": uid,
            "createdAtClient": Timestamp(date: now),
            "createdAt": FieldValue.serverTimestamp()
        ]

        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { data["text"] = trimmed }

        if let fileUrl = message.fileUrl {
            data["fileUrl"] = fileUrl
            if let fileName = message.fileName { data["fileName"] = fileName }
            if let fileSize = message.fileSize { data["fileSize"] = fileSize }
            if let fileType = message.fileType { data["fileType"] = fileType }
            if let thumb = message.thumbnailUrl { data["thumbnailUrl"] = thumb }
        }

        do { try await msgRef.setData(data) }
        catch { print("❌ Reenviar falló:", error.localizedDescription) }
    }

}

// MARK: - QuickLook wrapper con título + botón compartir
private struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL
    let title: String

    func makeUIViewController(context: Context) -> UINavigationController {
        let ql = QLPreviewController()
        ql.dataSource = context.coordinator
        ql.navigationItem.title = title

        // Botón de compartir/guardar
        let share = UIBarButtonItem(barButtonSystemItem: .action,
                                    target: context.coordinator,
                                    action: #selector(Coordinator.shareTapped))
        ql.navigationItem.rightBarButtonItem = share

        let nav = UINavigationController(rootViewController: ql)
        context.coordinator.presenter = nav
        context.coordinator.shareButton = share
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url, title: title) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        let title: String
        weak var presenter: UIViewController?
        weak var shareButton: UIBarButtonItem?

        init(url: URL, title: String) {
            self.url = url
            self.title = title
        }

        // QLPreviewControllerDataSource
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }

        // Acción del botón compartir
        @objc func shareTapped() {
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let pop = activity.popoverPresentationController, let bar = shareButton {
                pop.barButtonItem = bar
            }
            presenter?.present(activity, animated: true)
        }
    }
}
