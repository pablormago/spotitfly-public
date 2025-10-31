// Reemplaza la definición completa de CachedAvatarImageView por esta

import SwiftUI
import UIKit

struct CachedAvatarImageView: View {
    let urlString: String?
    let initials: String?
    var size: CGFloat = 52
    // ✅ NUEVO: clave estable (p.ej. "user:<uid>" o "chat:<chatId>")
    var stableKey: String? = nil
    
    @State private var uiImage: UIImage? = nil
    
    var body: some View {
        ZStack {
            if let img = uiImage {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                // Placeholder con iniciales
                let letters = String((initials ?? "U").prefix(2)).uppercased()
                ZStack {
                    Circle().fill(Color.blue.opacity(0.2))
                    Text(letters).font(.headline.bold()).foregroundColor(.blue)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .task(id: urlString ?? stableKey) {
            await load()
        }
        .onAppear {
            // Carga SINCRONA desde caché/memoria/disco para evitar blink
            if uiImage == nil {
                if let k = stableKey, let img = MediaCache.shared.cachedImage(for: k) {
                    uiImage = img
                    return
                }
                if let u = urlString, let img = MediaCache.shared.cachedImage(for: u) {
                    uiImage = img
                    return
                }
            }
        }
    }
    
    // MARK: - Bust helpers (persistimos el último visto por clave estable)
    private func extractBust(from url: String) -> String? {
        guard let comps = URLComponents(string: url),
              let q = comps.queryItems else { return nil }
        return q.first { $0.name.lowercased() == "bust" }?.value
    }
    private func readBust(for key: String) -> String? {
        UserDefaults.standard.string(forKey: "avatar.bust.\(key)")
    }
    private func writeBust(_ bust: String?, for key: String) {
        let k = "avatar.bust.\(key)"
        if let b = bust, !b.isEmpty { UserDefaults.standard.set(b, forKey: k) }
        else { UserDefaults.standard.removeObject(forKey: k) }
    }

    
    // MARK: - Carga y almacenamiento doble (URL -> clave estable)
    private func load() async {
        // 1) Si hay URL, priorizamos URL (evita mostrar una imagen vieja si cambió el bust)
        if let u = urlString {
            let currentBust = extractBust(from: u)
            if let img = MediaCache.shared.cachedImage(for: u) {
                await MainActor.run { self.uiImage = img }
                if let k = stableKey {
                    MediaCache.shared.storeImage(img, forKey: k)   // refresca copia estable
                    writeBust(currentBust, for: k)                 // guarda bust visto
                }
                return
            }
            if let img = await MediaCache.shared.image(for: u) {
                await MainActor.run { self.uiImage = img }
                // Guarda en ambas claves y registra bust
                MediaCache.shared.storeImage(img, forKey: u)
                if let k = stableKey {
                    MediaCache.shared.storeImage(img, forKey: k)
                    writeBust(currentBust, for: k)
                }
                return
            }
        }
        // 2) Fallback: clave estable (arranque en frío sin URL resuelta)
        if let k = stableKey, let img = MediaCache.shared.cachedImage(for: k) {
            await MainActor.run { self.uiImage = img }
            return
        }
    }

    
}

// Si mantienes esta utilidad, déjala tal cual:
private func ensureImageCacheDirExists() {
    let fm = FileManager.default
    if let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
        let legacy = base.appendingPathComponent("ImageCache", isDirectory: true)
        if !fm.fileExists(atPath: legacy.path) {
            try? fm.createDirectory(at: legacy, withIntermediateDirectories: true)
        }
        let media = base.appendingPathComponent("MediaCache.v1", isDirectory: true)
        if !fm.fileExists(atPath: media.path) {
            try? fm.createDirectory(at: media, withIntermediateDirectories: true)
        }
    }
}
