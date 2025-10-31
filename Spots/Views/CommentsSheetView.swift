import SwiftUI

struct CommentsSheetView: View {
    let spotId: String
    let spotDescription: String
    let creatorName: String

    @StateObject private var vm: CommentsViewModel
    @EnvironmentObject private var userSession: UserSession

    @State private var input: String = ""
    @FocusState private var inputFocused: Bool

    // Toasts existentes
    @State private var showEditedToast = false
    @State private var showDeletedToast = false

    // 🆕 Toast de moderación
    @State private var showModerationToast = false
    @State private var toastMessage: String = ""
    @State private var toastIcon: String? = nil

    // Confirmación borrar
    @State private var commentToDelete: SpotComment? = nil
    @State private var showDeleteConfirm = false

    // Scroll control
    @State private var scrollProxy: ScrollViewProxy?

    init(spotId: String, spotDescription: String, creatorName: String) {
        self.spotId = spotId
        self.spotDescription = spotDescription
        self.creatorName = creatorName
        _vm = StateObject(wrappedValue: CommentsViewModel(spotId: spotId))
    }

    var body: some View {
        VStack(spacing: 12) {
            // Usuario + descripción arriba del sheet
            VStack(alignment: .leading, spacing: 6) {
                Text(creatorName.isEmpty ? "Usuario" : creatorName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.blue)

                Text(spotDescription.isEmpty ? "Añade una descripción" : spotDescription)
                    .font(.body)
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)

            Divider()

            // Lista de comentarios con scroll automático
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(sortedComments) { c in
                            CommentRow(
                                spotId: spotId,
                                comment: c,
                                canEdit: c.authorId == userSession.uid,
                                onEdit: { newText in
                                    Task {
                                        do {
                                            try await vm.edit(commentId: c.id, newText: newText)
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
                            .id(c.id) // necesario para scrollTo
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onAppear {
                    scrollProxy = proxy
                    scrollToLast(proxy: proxy)
                }
                .onChange(of: vm.comments.count) { _ in
                    scrollToLast(proxy: proxy)
                }
            }

            // Composer
            HStack(spacing: 10) {
                TextField("Escribe un comentario…", text: $input, axis: .vertical)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled(false)
                    .lineLimit(1...4)
                    .padding(10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(10)
                    .focused($inputFocused)

                Button {
                    Task { await send() }
                } label: {
                    if vm.isSending {
                        ProgressView()
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 18, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                .foregroundColor(inputTrimmed.isEmpty || vm.isSending ? .gray : .accentColor)
                .disabled(inputTrimmed.isEmpty || vm.isSending)
            }
            .padding(.vertical, 6)

            // 🆕 Bloque de Community Guidelines (pegado abajo del contenido)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.circle")
                    .foregroundColor(.orange)
                Text("Recuerda seguir las normas de la comunidad: nada de spam, lenguaje ofensivo ni contenido inapropiado. Puedes reportar comentarios desde el menú contextual.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .padding()
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
        // 🆕 Toast moderación
        .toast(isPresented: $showModerationToast,
               message: toastMessage,
               systemImage: toastIcon,
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
            Button("Cancelar", role: .cancel) {}
        } message: { _ in
            Text("¿Seguro que quieres eliminar este comentario?")
        }
    }

    // MARK: - Helpers

    private var sortedComments: [SpotComment] {
        vm.comments.sorted { $0.createdAt < $1.createdAt }
    }

    private var inputTrimmed: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send() async {
        let text = inputTrimmed
        guard !text.isEmpty else { return }
        let uid = userSession.uid ?? ""
        let name = userSession.username

        // 🧹 Moderación
        switch ModerationService.evaluate(text) {
            case .allow:
                break
            case .warn(let reason):
                await MainActor.run {
                    toastMessage = "⚠️ Mensaje dudoso: \(reason)"
                    toastIcon = "exclamationmark.circle.fill"
                    showModerationToast = true
                }
                // seguimos enviando
            case .block(let reason):
                await MainActor.run {
                    toastMessage = "⛔️ Bloqueado: \(reason)"
                    toastIcon = "nosign"
                    showModerationToast = true
                }
                return
        }

        do {
            try await vm.send(text: text, authorId: uid, authorName: name)
            await MainActor.run {
                input = ""
                inputFocused = false
                if let last = sortedComments.last {
                    scrollProxy?.scrollTo(last.id, anchor: .bottom)
                }
            }
        } catch {
            print("❌ Error enviando comentario: \(error.localizedDescription)")
        }
    }

    private func scrollToLast(proxy: ScrollViewProxy) {
        if let last = sortedComments.last {
            withAnimation {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
