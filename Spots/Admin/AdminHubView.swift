//
//  AdminHubView.swift
//  Spots
//
//  Created by Pablo Jimenez on 1/10/25.
//

import SwiftUI
import FirebaseAuth

struct AdminHubView: View {
    @State private var showSignOutAlert = false

    var body: some View {
        List {
            Section {
                NavigationLink("Bandeja de soporte") {
                    SupportInboxView()
                }
                NavigationLink("Moderación · Spots") {
                    AdminModerationView(mode: .spots)
                }
                NavigationLink("Moderación · Comentarios") {
                    AdminModerationView(mode: .comments)
                }
            }

            Section("Sesión") {
                HStack {
                    Text("Email actual")
                    Spacer()
                    Text(Auth.auth().currentUser?.email ?? "—")
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Button(role: .destructive) {
                    showSignOutAlert = true
                } label: {
                    Label("Cerrar sesión admin", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Admin")
        .alert("¿Cerrar sesión de administrador?", isPresented: $showSignOutAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Cerrar sesión", role: .destructive) {
                try? Auth.auth().signOut()
            }
        } message: {
            Text("Se cerrará la sesión actual.")
        }
    }
}
