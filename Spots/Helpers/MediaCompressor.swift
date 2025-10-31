import Foundation
import UIKit

#if canImport(AVFoundation)
import AVFoundation
#endif

enum MediaCompressorError: Error {
    case imageEncodingFailed
    case videoExportFailed
    case videoTrackNotFound
    case fileTooLargeAfterCompression
}

enum MediaCompressor {
    /// Comprime/redimensiona una imagen a JPEG <= ~FeatureFlags.imageMaxLongSide px
    static func compressImage(_ image: UIImage,
                              maxLongSide: Int = FeatureFlags.imageMaxLongSide,
                              quality: CGFloat = 0.8) async throws -> Data {
        let size = image.size
        let maxSide = max(size.width, size.height)
        let scale: CGFloat = max(1, maxSide / CGFloat(maxLongSide))
        let target = CGSize(width: size.width / scale, height: size.height / scale)

        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        guard let data = resized.jpegData(compressionQuality: quality) else {
            throw MediaCompressorError.imageEncodingFailed
        }
        return data
    }

    #if canImport(AVFoundation)
    /// Exporta vídeo con preset dado; devuelve URL temporal del vídeo comprimido.
    static func compressVideo(at inputURL: URL,
                              presetName: String = FeatureFlags.videoExportPreset) async throws -> URL {
        let asset = AVAsset(url: inputURL)
        guard let track = asset.tracks(withMediaType: .video).first else {
            throw MediaCompressorError.videoTrackNotFound
        }
        let naturalSize = track.naturalSize.applying(track.preferredTransform)
        _ = abs(naturalSize.width) + abs(naturalSize.height) // (por si se quiere usar para decidir preset)

        guard let export = AVAssetExportSession(asset: asset, presetName: presetName) else {
            throw MediaCompressorError.videoExportFailed
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vid-\(UUID().uuidString).mp4")

        export.outputFileType = .mp4
        export.outputURL = outputURL
        export.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously {
                cont.resume()
            }
        }
        guard export.status == .completed, FileManager.default.fileExists(atPath: outputURL.path) else {
            throw MediaCompressorError.videoExportFailed
        }
        return outputURL
    }
    #endif
}
