import Foundation

extension Chat {
    var previewLabel: String {
        let s = (lastMessage ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "📎 Archivo" }

        let lower = s.lowercased()

        // Heurística por extensión (cuando lastMessage = fileName)
        if lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") || lower.hasSuffix(".png") || lower.hasSuffix(".gif") || lower.hasSuffix(".heic") {
            return "📷 Foto"
        }
        if lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.hasSuffix(".avi") || lower.hasSuffix(".mkv") {
            return "🎬 Vídeo"
        }
        if lower.hasSuffix(".mp3") || lower.hasSuffix(".m4a") || lower.hasSuffix(".wav") {
            return "🎵 Audio"
        }
        if lower.hasSuffix(".pdf") || lower.hasSuffix(".doc") || lower.hasSuffix(".docx") || lower.hasSuffix(".xls") || lower.hasSuffix(".xlsx") || lower.hasSuffix(".zip") || lower.hasSuffix(".rar") {
            return "📎 \(s)"
        }

        // Enlaces
        if s.contains("http://") || s.contains("https://") {
            if let comp = URLComponents(string: s), let host = comp.host {
                return "🔗 \(host)"
            }
            return "🔗 Enlace"
        }

        // Texto normal
        return s
    }
}
