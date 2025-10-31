//
//  ImageCache.swift
//  Spots
//
//  Created by Pablo Jimenez on 15/9/25.
//

import Foundation
import UIKit

/// Caché de imágenes por URL para toda la sesión.
/// - Incluye coalescing (varias vistas esperan a la misma descarga).
/// - Ahora persiste también en disco (cachesDirectory).
actor ImageCache {
    static let shared = ImageCache()

    private var memory: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 300
        c.totalCostLimit = 64 * 1_024 * 1_024 // ~64MB
        return c
    }()

    private var inflight: [String: Task<UIImage?, Never>] = [:]

    // MARK: - Obtener imagen
    func image(for urlString: String) async -> UIImage? {
        let key = urlString as NSString

        // 1) En memoria
        if let img = memory.object(forKey: key) {
            return img
        }

        // 2) En disco
        if let disk = loadFromDisk(for: urlString) {
            memory.setObject(disk, forKey: key, cost: disk.cost)
            return disk
        }

        // 3) En vuelo
        if let task = inflight[urlString] {
            return await task.value
        }

        // 4) Descargar
        let task = Task<UIImage?, Never> {
            defer { Task { await self.finish(urlString) } }
            guard let url = URL(string: urlString) else { return nil }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard let img = UIImage(data: data) else { return nil }
                memory.setObject(img, forKey: key, cost: data.count)
                saveToDisk(img, for: urlString)   // ✅ guardamos en disco
                return img
            } catch {
                return nil
            }
        }
        inflight[urlString] = task
        return await task.value
    }

    private func finish(_ urlString: String) {
        inflight[urlString] = nil
    }

    // MARK: - Cache helpers
    func remove(for urlString: String) {
        memory.removeObject(forKey: urlString as NSString)
        removeFromDisk(for: urlString)
    }

    func clear() {
        memory.removeAllObjects()
        inflight.removeAll()
        clearDisk()
    }

    /// ✅ Ahora mira primero en memoria, luego en disco de forma síncrona.
    func cachedImage(for urlString: String) -> UIImage? {
        let key = urlString as NSString
        if let img = memory.object(forKey: key) {
            return img
        }
        if let disk = loadFromDisk(for: urlString) {
            memory.setObject(disk, forKey: key, cost: disk.cost)
            return disk
        }
        return nil
    }

    // MARK: - Prefetch (descarga anticipada)
    func prefetch(urlString: String) {
        Task {
            _ = await image(for: urlString)
        }
    }

    // MARK: - Disco
    private static var cacheDir: URL = {
        let urls = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
        let dir = urls[0].appendingPathComponent("ImageCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private func fileURL(for urlString: String) -> URL {
        let name = urlString
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        return Self.cacheDir.appendingPathComponent(name)
    }

    private func saveToDisk(_ image: UIImage, for urlString: String) {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return }
        let url = fileURL(for: urlString)
        try? data.write(to: url, options: .atomic)
    }

    private func loadFromDisk(for urlString: String) -> UIImage? {
        let url = fileURL(for: urlString)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    private func removeFromDisk(for urlString: String) {
        let url = fileURL(for: urlString)
        try? FileManager.default.removeItem(at: url)
    }

    private func clearDisk() {
        try? FileManager.default.removeItem(at: Self.cacheDir)
        try? FileManager.default.createDirectory(at: Self.cacheDir, withIntermediateDirectories: true)
    }
}

// Extensión para estimar coste en memoria
private extension UIImage {
    var cost: Int {
        guard let cgImage = self.cgImage else { return 1 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
