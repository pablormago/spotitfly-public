//
//  LinkPreview.swift
//  Spots
//
//  Created by Pablo Jimenez on 9/10/25.
//


import Foundation
import CryptoKit

// 🔒 Datos completos del preview (amplíalo si usas más campos)
public struct LinkPreview: Codable, Equatable {
    public let url: String
    public let siteName: String?
    public let title: String?
    public let description: String?
    public let thumbnailURL: String?
    public let mediaType: String?      // e.g., "video", "image", "link"
    public let author: String?
    public let duration: Double?       // segundos (YouTube, etc.)
    public let publishedAt: Date?
    public let fetchedAt: Date         // para TTL
}

// 🧠 Caché JSON en disco + memoria, con TTL configurable
final class LinkPreviewCache {
    static let shared = LinkPreviewCache()

    private let memory = NSCache<NSString, Wrapped>()
    private let fm = FileManager.default
    private let ttl: TimeInterval = 7 * 24 * 60 * 60 // 7 días (ajusta si quieres)

    private init() {}

    // MARK: - Public

    func get(for url: String) -> LinkPreview? {
        let key = cacheKey(for: url)

        // 1) Memoria
        if let w = memory.object(forKey: key as NSString) {
            if !isExpired(w.value.fetchedAt) { return w.value }
        }

        // 2) Disco
        let path = pathFor(key: key)
        guard let data = try? Data(contentsOf: path),
              let preview = try? JSONDecoder().decode(LinkPreview.self, from: data) else {
            return nil
        }
        if isExpired(preview.fetchedAt) {
            // expiró: quitar de disco
            try? fm.removeItem(at: path)
            return nil
        }
        memory.setObject(Wrapped(preview), forKey: key as NSString)
        return preview
    }

    func set(_ preview: LinkPreview) {
        let key = cacheKey(for: preview.url)
        memory.setObject(Wrapped(preview), forKey: key as NSString)
        let path = pathFor(key: key)
        do {
            let data = try JSONEncoder().encode(preview)
            try data.write(to: path, options: .atomic)
        } catch {
            #if DEBUG
            print("LinkPreviewCache write error: \(error)")
            #endif
        }
    }

    func remove(for url: String) {
        let key = cacheKey(for: url)
        memory.removeObject(forKey: key as NSString)
        let path = pathFor(key: key)
        try? fm.removeItem(at: path)
    }

    // MARK: - Helpers

    private func cacheKey(for url: String) -> String {
        // normaliza mínimamente (lowercase host, etc.)
        guard var comps = URLComponents(string: url) else { return sha256(url) }
        comps.scheme = comps.scheme?.lowercased()
        comps.host = comps.host?.lowercased()
        // quita anchors típicos de redes que no alteran metadatos
        comps.fragment = nil
        let normalized = comps.string ?? url
        return sha256(normalized)
    }

    private func pathFor(key: String) -> URL {
        let dir = cachesDir().appendingPathComponent("link_previews", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("\(key).json")
    }

    private func cachesDir() -> URL {
        fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
    }

    private func isExpired(_ date: Date) -> Bool {
        Date().timeIntervalSince(date) > ttl
    }

    private func sha256(_ s: String) -> String {
        let data = Data(s.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private final class Wrapped: NSObject {
        let value: LinkPreview
        init(_ v: LinkPreview) { self.value = v }
    }
}
