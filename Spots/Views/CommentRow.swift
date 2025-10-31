//
//  CommentRow.swift
//  Spots
//
//  Created by Pablo Jimenez on 18/9/25.
//

import SwiftUI
import FirebaseAuth

struct CommentRow: View {
    let spotId: String                 // 🆕 necesario para reportar
    let comment: SpotComment
    let canEdit: Bool
    let onEdit: (String) -> Void
    let onAskDelete: (SpotComment) -> Void

    @EnvironmentObject var userSession: UserSession
    @EnvironmentObject var appConfig: AppConfig

    @State private var isEditing = false
    @State private var draft = ""

    @State private var isReporting = false
    @State private var showToast = false
    @State private var toastMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Cabecera: autor + fecha + acciones
            HStack {
                Text(author)
                    .font(.subheadline).bold()
                Spacer()
                Text(timeString)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if canEdit {
                    HStack(spacing: 12) {
                        Button {
                            draft = comment.text
                            isEditing = true
                        } label: {
                            Image(systemName: "pencil")
                        }
                        .buttonStyle(.plain)

                        Button {
                            onAskDelete(comment)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .foregroundColor(.secondary)
                }
            }

            // Cuerpo: edición o lectura
            if isEditing {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Editar comentario", text: $draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Cancelar") { isEditing = false }
                        Spacer()
                        Button("Guardar") {
                            let newText = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !newText.isEmpty else { return }
                            onEdit(newText)
                            isEditing = false
                        }
                    }
                    .font(.caption)
                }
            } else {
                // Enlaces clicables
                LinkTextView(text: comment.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
        // 👇 Long tap → menú contextual con varios motivos
        .contextMenu {
            if appConfig.reportsEnabled,
               let uid = userSession.uid,
               uid != comment.authorId {
                Button(role: .destructive) {
                    Task { await report("Spam") }
                } label: {
                    Label("Reportar: Spam", systemImage: "exclamationmark.triangle")
                }
                Button(role: .destructive) {
                    Task { await report("Ofensivo o abuso") }
                } label: {
                    Label("Reportar: Ofensivo", systemImage: "hand.raised")
                }
                Button(role: .destructive) {
                    Task { await report("Contenido inapropiado") }
                } label: {
                    Label("Reportar: Inapropiado", systemImage: "exclamationmark.bubble")
                }
            }
        }
        .alert(toastMessage, isPresented: $showToast) {
            Button("OK", role: .cancel) { }
        }
    }

    private var author: String {
        if let n = comment.authorName, !n.isEmpty { return n }
        return comment.authorId
    }

    private var timeString: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: comment.createdAt, relativeTo: Date())
    }

    // MARK: - Reporte comentario (cierra menú, háptica y toast)
    private func report(_ reason: String) async {
        guard !isReporting else { return }
        isReporting = true
        defer { isReporting = false }

        // háptica ligera
        let h = UINotificationFeedbackGenerator()
        h.notificationOccurred(.success)

        await ReportService.reportComment(
            commentId: comment.id,
            spotId: spotId,
            reason: reason
        )

        await MainActor.run {
            toastMessage = "Reporte enviado. Gracias por avisar."
            showToast = true
        }
    }

}
