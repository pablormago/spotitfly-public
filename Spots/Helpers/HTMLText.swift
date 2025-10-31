import SwiftUI

struct HTMLText: View {
    let html: String

    var body: some View {
        if let attributed = html.toAttributedString() {
            Text(attributed)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(html.sinEtiquetasHTML)
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

extension String {
    func toAttributedString() -> AttributedString? {
        guard let data = self.data(using: .utf8) else { return nil }
        do {
            let mut = try NSMutableAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue
                ],
                documentAttributes: nil
            )

            let fullRange = NSRange(location: 0, length: mut.length)

            // 🔹 Forzar fuente global
            mut.addAttribute(
                .font,
                value: UIFont.systemFont(ofSize: 14, weight: .regular).withDesign(.rounded)!,
                range: fullRange
            )

            // 🔹 Quitar colores que vengan del HTML (ej. negro fijo)
            mut.enumerateAttribute(.foregroundColor, in: fullRange) { value, range, _ in
                if value != nil {
                    mut.removeAttribute(.foregroundColor, range: range)
                }
            }

            // 🔹 Aplicar color adaptativo gris claro
            mut.addAttribute(.foregroundColor, value: UIColor.secondaryLabel, range: fullRange)

            // 🔹 Links en azul sin subrayado
            mut.enumerateAttribute(.link, in: fullRange) { value, range, _ in
                if value != nil {
                    mut.addAttribute(.foregroundColor, value: UIColor.systemBlue, range: range)
                    mut.removeAttribute(.underlineStyle, range: range)
                }
            }

            return try AttributedString(mut, including: \.uiKit)
        } catch {
            print("⚠️ Error parseando HTML en AttributedString: \(error)")
            return nil
        }
    }
}

private extension UIFont {
    func withDesign(_ design: UIFontDescriptor.SystemDesign) -> UIFont? {
        let descriptor = self.fontDescriptor.withDesign(design)
        return descriptor.map { UIFont(descriptor: $0, size: pointSize) }
    }
}
