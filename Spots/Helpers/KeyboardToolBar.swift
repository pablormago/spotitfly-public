import SwiftUI

// Utilidad para cerrar el teclado (sin colisionar con .keyboard)
enum KeyboardHider {
    static func dismiss() {
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        #endif
    }
}

/// ViewModifier que añade una barra sobre el teclado con un botón para ocultarlo
struct KeyboardDismissToolbar: ViewModifier {
    var title: String = "Ocultar"
    var showTitle: Bool = false   // si prefieres solo el icono, déjalo en false

    func body(content: Content) -> some View {
        content
            // Variante sin el argumento `placement:` en el modificador,
            // especificamos el placement dentro del ToolbarItemGroup.
            .toolbar {
                ToolbarItemGroup(placement: ToolbarItemPlacement.keyboard) {
                    Spacer()
                    Button {
                        KeyboardHider.dismiss()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "keyboard.chevron.compact.down")
                            if showTitle { Text(title) }
                        }
                        .font(.body)
                    }
                    .accessibilityLabel(Text("Ocultar teclado"))
                }
            }
    }
}

extension View {
    /// Añade una barra sobre el teclado con botón para ocultarlo
    func keyboardDismissToolbar(showTitle: Bool = false) -> some View {
        self.modifier(KeyboardDismissToolbar(showTitle: showTitle))
    }
}
