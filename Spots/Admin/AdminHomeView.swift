//
//  AdminHomeView.swift
//  Spots
//

import SwiftUI
import FirebaseAuth

struct AdminHomeView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case support, spots, comments, users, blocks
        var id: String { rawValue }

        var title: String {
            switch self {
            case .support:  return "Soporte"
            case .spots:    return "Spots"
            case .comments: return "Comentarios"
            case .users:    return "Usuarios"
            case .blocks:   return "Bloqueos"
            }
        }
        var shortTitle: String {
            switch self {
            case .support:  return "Soporte"
            case .spots:    return "Spots"
            case .comments: return "Coment..."
            case .users:    return "Usuarios"
            case .blocks:   return "Bloqueos"
            }
        }
    }

    @State private var tab: Tab = .support
    @State private var showSignOutAlert = false

    var body: some View {
        // contenido central según la pestaña
        Group {
            switch tab {
            case .support:
                SupportInboxView()
                    .navigationBarTitle(Text("Soporte"), displayMode: .inline)

            case .spots:
                AdminModerationView(mode: .spots)
                    .navigationBarTitle(Text("Spots"), displayMode: .inline)

            case .comments:
                AdminModerationView(mode: .comments)
                    .navigationBarTitle(Text("Comentarios"), displayMode: .inline)

            case .users:
                AdminReportedUsersView()
                    .navigationBarTitle(Text("Usuarios"), displayMode: .inline)

            case .blocks:
                AdminBlocksView()
                    .navigationBarTitle(Text("Bloqueos"), displayMode: .inline)
            }
        }
        // Header de pestañas pegado justo bajo el título
        .safeAreaInset(edge: .top, spacing: 6) {
            AdminTabsHeader(tab: $tab)
                .padding(.horizontal, 12)
                .padding(.bottom, 2)
                .background(.ultraThinMaterial) // se integra con la barra
        }
        .toolbar {
            /*ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showSignOutAlert = true
                    } label: {
                        Label("Cerrar sesión admin", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
            }*/
        }
        .alert("¿Cerrar sesión de administrador?", isPresented: $showSignOutAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Cerrar sesión", role: .destructive) {
                try? Auth.auth().signOut()
            }
        } message: { Text("Se cerrará la sesión actual.") }
    }
}

// MARK: - Header con las pestañas (Segmented)
private struct AdminTabsHeader: View {
    @Binding var tab: AdminHomeView.Tab

    var body: some View {
        Picker("", selection: $tab) {
            Text(AdminHomeView.Tab.support.shortTitle).tag(AdminHomeView.Tab.support)
            Text(AdminHomeView.Tab.spots.shortTitle).tag(AdminHomeView.Tab.spots)
            Text(AdminHomeView.Tab.comments.shortTitle).tag(AdminHomeView.Tab.comments)
            Text(AdminHomeView.Tab.users.shortTitle).tag(AdminHomeView.Tab.users)
            Text(AdminHomeView.Tab.blocks.shortTitle).tag(AdminHomeView.Tab.blocks)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize(horizontal: false, vertical: true)
    }
}
