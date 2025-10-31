import Foundation

extension String {
    /// Versión simple: quita etiquetas y resuelve entidades básicas
    var sinEtiquetasHTML: String {
        // quitar etiquetas
        let sinTags = self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        // entidades mínimas
        return sinTags
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            // acentos más comunes
            .replacingOccurrences(of: "&aacute;", with: "á")
            .replacingOccurrences(of: "&eacute;", with: "é")
            .replacingOccurrences(of: "&iacute;", with: "í")
            .replacingOccurrences(of: "&oacute;", with: "ó")
            .replacingOccurrences(of: "&uacute;", with: "ú")
    }
}
