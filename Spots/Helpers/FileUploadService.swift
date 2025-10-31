import Foundation
import FirebaseStorage

struct FileUploadResult {
    let url: URL
    let size: Int64
    let contentType: String
    let fileName: String
}

enum FileUploadError: Error {
    case exceedsMaxSize
    case missingData
}

final class FileUploadService {
    static let shared = FileUploadService()
    private init() {}

    /// Sube `Data` (imágenes, miniaturas, etc.)
    func upload(data: Data,
                contentType: String,
                fileName: String,
                path: String,
                progress: ((Double) -> Void)? = nil) async throws -> FileUploadResult {

        let maxBytes = Int64(FeatureFlags.maxUploadMB * 1024 * 1024)
        if Int64(data.count) > maxBytes {
            throw FileUploadError.exceedsMaxSize
        }

        let ref = Storage.storage().reference(withPath: path).child(fileName)
        let meta = StorageMetadata()
        meta.contentType = contentType

        let task = ref.putData(data, metadata: meta)

        if let progress = progress {
            let obs = task.observe(.progress) { snap in
                let p = Double(snap.progress?.fractionCompleted ?? 0)
                progress(p)
            }
            // Para evitar warning de no uso
            _ = obs
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            task.observe(.success) { _ in cont.resume() }
            task.observe(.failure) { snap in
                cont.resume(throwing: snap.error ?? URLError(.cannotWriteToFile))
            }
        }

        let downloadURL = try await ref.downloadURL()
        let size = Int64(data.count)
        return FileUploadResult(url: downloadURL, size: size, contentType: contentType, fileName: fileName)
    }

    /// Sube archivo desde URL local (vídeos/otros); valida el tamaño antes.
    func uploadFile(at localURL: URL,
                    contentType: String,
                    fileName: String,
                    path: String,
                    progress: ((Double) -> Void)? = nil) async throws -> FileUploadResult {

        let attrs = try FileManager.default.attributesOfItem(atPath: localURL.path)
        let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let maxBytes = Int64(FeatureFlags.maxUploadMB * 1024 * 1024)
        if fileSize > maxBytes {
            throw FileUploadError.exceedsMaxSize
        }

        let ref = Storage.storage().reference(withPath: path).child(fileName)
        let meta = StorageMetadata()
        meta.contentType = contentType

        let task = ref.putFile(from: localURL, metadata: meta)

        if let progress = progress {
            let obs = task.observe(.progress) { snap in
                let p = Double(snap.progress?.fractionCompleted ?? 0)
                progress(p)
            }
            _ = obs
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            task.observe(.success) { _ in cont.resume() }
            task.observe(.failure) { snap in
                cont.resume(throwing: snap.error ?? URLError(.cannotWriteToFile))
            }
        }

        let downloadURL = try await ref.downloadURL()
        return FileUploadResult(url: downloadURL, size: fileSize, contentType: contentType, fileName: fileName)
    }
}
