import Foundation
import UIKit

final class MediaCache {
    static let shared = MediaCache()

    private let memory = NSCache<NSString, NSData>()
    private let fm = FileManager.default
    private let dir: URL
    private let ratiosKey = "MediaCache.ratios.v1" // [String: Double]

    private init() {
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
        dir = base.appendingPathComponent("MediaCache.v1", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        memory.countLimit = 400
        memory.totalCostLimit = 120 * 1024 * 1024
    }

    // MARK: - Disk paths
    private func key(_ k: String) -> String { k }
    private func path(for key: String) -> URL {
        let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? UUID().uuidString
        return dir.appendingPathComponent(safe)
    }

    // MARK: - Data
    func data(forKey key: String) -> Data? {
        let k = key as NSString
        if let d = memory.object(forKey: k) { return d as Data }
        let p = path(for: key)
        if let d = try? Data(contentsOf: p) {
            memory.setObject(d as NSData, forKey: k, cost: d.count)
            return d
        }
        return nil
    }

    func store(_ data: Data, forKey key: String) {
        let k = key as NSString
        memory.setObject(data as NSData, forKey: k, cost: data.count)
        try? data.write(to: path(for: key), options: .atomic)
    }

    // MARK: - Images
    func cachedImage(for key: String) -> UIImage? {
        if let d = data(forKey: key) { return UIImage(data: d) }
        return nil
    }

    func image(for urlString: String) async -> UIImage? {
        if let img = cachedImage(for: urlString) { return img }
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            store(data, forKey: urlString)
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    func storeImage(_ image: UIImage, forKey key: String, jpegQuality: CGFloat = 0.82) {
        if let d = image.jpegData(compressionQuality: jpegQuality) {
            store(d, forKey: key)
        } else if let d = image.pngData() {
            store(d, forKey: key)
        }
    }

    func prefetch(urlString: String) {
        Task.detached { [weak self] in
            guard let self else { return }
            _ = await self.image(for: urlString)
        }
    }

    // MARK: - Aspect ratio (height/width)
    func ratio(forKey key: String) -> CGFloat? {
        guard let dict = UserDefaults.standard.dictionary(forKey: ratiosKey) as? [String: Double],
              let val = dict[key] else { return nil }
        return CGFloat(val)
    }

    func setRatio(_ ratio: CGFloat, forKey key: String) {
        var dict = (UserDefaults.standard.dictionary(forKey: ratiosKey) as? [String: Double]) ?? [:]
        dict[key] = Double(ratio)
        UserDefaults.standard.set(dict, forKey: ratiosKey)
    }
}
