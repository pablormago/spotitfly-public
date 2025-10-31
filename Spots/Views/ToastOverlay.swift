import SwiftUI

/// Toast discreto inferior. Uso:
/// .toast(isPresented: $showToast, message: "Guardado", systemImage: "checkmark.circle.fill", duration: 3.0)
struct ToastOverlay: View {
    let message: String
    var systemImage: String?
    var body: some View {
        HStack(spacing: 8) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(message)
                .font(.callout).bold()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(radius: 6)
        .padding(.bottom, 24)
    }
}

private struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let systemImage: String?
    let duration: Double

    func body(content: Content) -> some View {
        ZStack {
            content
            if isPresented {
                VStack {
                    Spacer()
                    ToastOverlay(message: message, systemImage: systemImage)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                        withAnimation { isPresented = false }
                    }
                }
            }
        }
    }
}

extension View {
    func toast(isPresented: Binding<Bool>, message: String, systemImage: String? = nil, duration: Double = 1.4) -> some View {
        self.modifier(ToastModifier(isPresented: isPresented, message: message, systemImage: systemImage, duration: duration))
    }
}
