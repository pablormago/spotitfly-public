import SwiftUI

struct AuthView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var userSession: UserSession

    @State private var selectedTab: AuthTab = .login

    var body: some View {
        NavigationView {
            Group {
                switch selectedTab {
                case .login:
                    LoginView(onSwitch: { selectedTab = .register })
                        .environmentObject(auth)
                        .environmentObject(userSession)
                case .register:
                    RegisterView(onSwitch: { selectedTab = .login })
                }
            }
            .navigationTitle(selectedTab == .login ? "Entrar" : "Crear cuenta")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    enum AuthTab: Hashable {
        case login
        case register
    }
}
