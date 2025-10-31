import Foundation
import SwiftUI

extension String {
    /// Convierte HTML en un `AttributedString` con formato y color adaptativo
    var htmlAttributed: AttributedString? {
        guard let data = self.data(using: .utf8) else { return nil }
        do {
            let nsAttr = try NSMutableAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )

            // 🔹 Forzar color dinámico en todo el texto
            nsAttr.addAttribute(
                .foregroundColor,
                value: UIColor.label, // se adapta a Light/Dark
                range: NSRange(location: 0, length: nsAttr.length)
            )

            return AttributedString(nsAttr)
        } catch {
            print("❌ Error al parsear HTML:", error)
            return nil
        }
    }
}
