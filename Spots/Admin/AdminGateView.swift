//
//  AdminGateView.swift
//  Spots
//

import SwiftUI
import FirebaseAuth

struct AdminGateView: View {
    private let adminEmail = "pablormago@gmail.com"

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isProcessing: Bool = false
    @State private var errorMessage: String? = nil
    @State private var unlocked: Bool = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundColor(.blue)
                    .padding(.bottom, 6)

                Text("Acceso de administrador")
                    .font(.title3.bold())

                Text("Introduce tu email y contraseña para abrir el panel interno.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)
                    .padding(.horizontal)

                VStack(spacing: 12) {
                    TextField("Email", text: $email)
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)

                    SecureField("Contraseña", text: $password)
                        .textContentType(.password)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(10)
                }
                .padding(.top, 4)

                if let msg = errorMessage, !msg.isEmpty {
                    Text(msg)
                        .font(.footnote)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button {
                    Task { await unlock() }
                } label: {
                    HStack {
                        if isProcessing { ProgressView().padding(.trailing, 6) }
                        Text("Entrar")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canSubmit ? Color.blue : Color.gray.opacity(0.4))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(!canSubmit || isProcessing)
                .padding(.top, 4)

                sessionInfoView

                Spacer(minLength: 0)

                NavigationLink(
                    destination: AdminHubView(),
                    isActive: $unlocked
                ) { EmptyView() }
                .hidden()
            }
            .padding()
            .navigationTitle("Admin")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty
    }

    @ViewBuilder
    private var sessionInfoView: some View {
        let currentEmail = Auth.auth().currentUser?.email ?? "sin sesión"
        VStack(spacing: 6) {
            Text("Sesión actual: \(currentEmail)")
                .font(.caption)
                .foregroundColor(.secondary)
            if let current = Auth.auth().currentUser,
               current.email?.lowercased() != adminEmail {
                Text("Nota: para usar el panel, debes iniciar sesión como \(adminEmail).")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
    }

    // MARK: - Core
    private func unlock() async {
        errorMessage = nil
        guard email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == adminEmail else {
            errorMessage = "Este panel solo está disponible para \(adminEmail)."
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        do {
            if let user = Auth.auth().currentUser, user.email?.lowercased() == adminEmail {
                let credential = EmailAuthProvider.credential(withEmail: adminEmail, password: password)
                try await user.reauthenticate(with: credential)
            } else {
                if Auth.auth().currentUser != nil {
                    try? Auth.auth().signOut()
                }
                _ = try await Auth.auth().signIn(withEmail: adminEmail, password: password)
            }

            errorMessage = nil
            unlocked = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            errorMessage = "Error de acceso: \(error.localizedDescription)"
        }
    }
}
