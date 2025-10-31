import Foundation
import UniformTypeIdentifiers

enum AttachmentKind: String, Codable {
    case image, video, file
}

enum MIME {
    static func from(fileExtension ext: String?) -> String {
        guard let ext, !ext.isEmpty else { return "application/octet-stream" }
        if let type = UTType(filenameExtension: ext), let mime = type.preferredMIMEType {
            return mime
        }
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "pdf": return "application/pdf"
        case "zip": return "application/zip"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }

    static func kind(for mime: String) -> AttachmentKind {
        if mime.hasPrefix("image/") { return .image }
        if mime.hasPrefix("video/") { return .video }
        return .file
    }

    static func bestExtension(for mime: String) -> String {
        if let type = UTType(mimeType: mime), let ext = type.preferredFilenameExtension {
            return ext
        }
        switch mime {
        case "image/jpeg": return "jpg"
        case "image/png": return "png"
        case "video/mp4": return "mp4"
        case "video/quicktime": return "mov"
        case "application/pdf": return "pdf"
        default: return "bin"
        }
    }
}
