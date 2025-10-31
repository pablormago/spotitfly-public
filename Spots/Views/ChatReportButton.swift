//
//  ChatReportButton.swift
//  Spots
//
//  Created by Pablo Jimenez on 30/9/25.
//


//
//  ChatReportButton.swift
//  Spots
//

import SwiftUI

struct ChatReportButton: View {
    let chatId: String

    @EnvironmentObject var userSession: UserSession
    @EnvironmentObject var appConfig: AppConfig

    @State private var isReporting = false
    @State private var showToast = false
    @State private var toastMessage = ""

    var body: some View {
        Menu {
            if appConfig.reportsEnabled,
               userSession.uid != nil {
                Button(role: .destructive) {
                    Task { await report("Spam") }
                } label: {
                    Label("Reportar chat: Spam", systemImage: "exclamationmark.triangle")
                }
                Button(role: .destructive) {
                    Task { await report("Ofensivo o abuso") }
                } label: {
                    Label("Reportar chat: Ofensivo", systemImage: "hand.raised")
                }
                Button(role: .destructive) {
                    Task { await report("Contenido inapropiado") }
                } label: {
                    Label("Reportar chat: Inapropiado", systemImage: "exclamationmark.bubble")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
        }
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
