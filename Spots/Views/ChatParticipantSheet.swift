//
//  ChatParticipantSheet.swift
//  Spots
//
//  Created by Pablo Jimenez on 30/9/25.
//


//
//  ChatParticipantSheet.swift
//  Spots
//

import SwiftUI

struct ChatParticipantSheet: View {
    let chatId: String
    let displayName: String
    let avatarURL: String?

    @EnvironmentObject var userSession: UserSession
    @EnvironmentObject var appConfig: AppConfig
    @Environment(\.dismiss) private var dismiss

    @State private var isReporting = false
    @State private var showReasons = false
    @State private var showToast = false
    @State private var toastMessage = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {

                // Avatar
                Group {
                    if let avatarURL, let url = URL(string: avatarURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ProgressView().frame(width: 96, height: 96)
                            case .success(let image):
                                image.resizable().scaledToFill()
                            case .failure:
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable().scaledToFit()
                            @unknown default:
                                Image(systemName: "person.crop.circle.fill")
                                    .resizable().scaledToFit()
                            }
                        }
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 96, height: 96)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.top, 24)

                // Nombre
                Text(displayName)
                    .font(.title3.bold())
                    .foregroundColor(.black)

                Spacer(minLength: 12)

                // Botón Reportar (solo si enabled y logueado)
                if appConfig.reportsEnabled, userSession.uid != nil {
                    Button {
                        showReasons = true
                    } label: {
                        Label("Reportar usuario", systemImage: "exclamationmark.bubble")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red.opacity(0.12))
                            .foregroundColor(.red)
                            .cornerRadius(10)
                    }
                    .padding(.horizontal, 20)
                }

                Spacer()
            }
            .padding(.bottom, 20)
            .navigationTitle("Perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        // Selección de motivo
        .confirmationDialog("Motivo del reporte", isPresented: $showReasons, titleVisibility: .visible) {
            Button("Spam", role: .destructive) { Task { await report("Spam") } }
            Button("Ofensivo o abuso", role: .destructive) { Task { await report("Ofensivo/abuso") } }
            Button("Contenido inapropiado", role: .destructive) { Task { await report("Contenido inapropiado") } }
            Button("Cancelar", role: .cancel) { }
        }
        // Feedback simple (si usas toast propio, sustitúyelo aquí)
        .alert(toastMessage, isPresented: $showToast) {
            Button("OK", role: .cancel) { }
        }
    }

    private func report(_ reason: String) async {
        guard !isReporting else { return }
        isReporting = true
        defer { isReporting = false }

        await ReportService.reportChat(chatId: chatId, reason: reason)
        await MainActor.run {
            toastMessage = "Reporte enviado. Gracias por avisar."
            showToast = true
        }
    }
}
