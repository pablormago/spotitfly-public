import SwiftUI

struct CommentsBlock: View {
    let spotId: String
    let spotDescription: String?
    let creatorName: String?

    @StateObject private var vm: CommentsViewModel
    @EnvironmentObject private var userSession: UserSession

    // Toasts
    @State private var showEditedToast = false
    @State private var showDeletedToast = false

    // Confirmación borrar
    @State private var commentToDelete: SpotComment? = nil
    @State private var showDeleteConfirm = false

    // Sheet con todos los comentarios
    @State private var showAllComments = false

    init(
        spotId: String,
        spotDescription: String? = nil,
        creatorName: String? = nil
    ) {
        self.spotId = spotId
        self.spotDescription = spotDescription
        self.creatorName = creatorName
        _vm = StateObject(wrappedValue: CommentsViewModel(spotId: spotId))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            commentsPreview
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }

        // Toasts
        .toast(isPresented: $showEditedToast,
               message: "Comentario editado",
               systemImage: "pencil.circle.fill",
               duration: 3)
        .toast(isPresented: $showDeletedToast,
               message: "Comentario eliminado",
               systemImage: "trash.fill",
               duration: 3)

        // Confirmación borrar
        .confirmationDialog("¿Eliminar comentario?",
                            isPresented: $showDeleteConfirm,
                            presenting: commentToDelete) { comment in
            Button("Eliminar", role: .destructive) {
                Task {
                    do {
                        try await vm.delete(commentId: comment.id)
                        showDeletedToast = true
                    } catch {
                        print("❌ Error eliminando comentario:", error.localizedDescription)
                    }
                }
            }
            Button("Cancelar", role: .cancel) { }
        } message: { _ in
            Text("¿Seguro que quieres eliminar este comentario?")
        }

        // Sheet con todos los comentarios + composer
        .sheet(isPresented: $showAllComments) {
            CommentsSheetView(
                spotId: spotId,
                spotDescription: spotDescription ?? "",
                creatorName: creatorName ?? ""
            )
            .environmentObject(userSession)
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Header (bocadillo abre sheet) + contador
    private var header: some View {
        HStack(spacing: 8) {
            Button { showAllComments = true } label: {
                Image(systemName: "text.bubble")
                    .font(.headline)
            }
            .accessibilityLabel("Abrir todos los comentarios")

            Text(" \(vm.comments.count)")
                .font(.headline)
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    // MARK: - Vista previa (solo el más antiguo)
    @ViewBuilder
    private var commentsPreview: some View {
        if vm.comments.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundColor(.secondary)
                Text("Sé el primero en comentar…")
                    .foregroundColor(.secondary)
            }
            .font(.subheadline)
            .padding(.vertical, 8)
        } else {
            if let first = vm.comments.sorted(by: { $0.createdAt < $1.createdAt }).first {
                CommentPreviewRow(
                    comment: first,
                    canEdit: first.authorId == userSession.uid,
                    onEdit: { newText in
                        Task {
                            do {
                                try await vm.edit(commentId: first.id, newText: newText)
                                showEditedToast = true
                            } catch {
                                print("❌ Error editando comentario:", error.localizedDescription)
                            }
                        }
                    },
                    onAskDelete: { comment in
                        commentToDelete = comment
                        showDeleteConfirm = true
                    }
                )
            }
        }
    }
}

// MARK: - Fila de comentario para la PREVIEW
private struct CommentPreviewRow: View {
    let comment: SpotComment
    let canEdit: Bool
    let onEdit: (String) -> Void
    let onAskDelete: (SpotComment) -> Void

    @State private var isEditing = false
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
}
