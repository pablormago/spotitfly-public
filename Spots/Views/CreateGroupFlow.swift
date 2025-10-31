import SwiftUI
import FirebaseAuth
import Combine

struct SelectableUser: Identifiable, Hashable {
    let id: String           // uid
    let displayName: String  // nunca mostramos uid, solo nombre
    let photoURL: String?    // para CachedAvatarImageView
}

struct CreateGroupFlow: View {
    let allUsers: [SelectableUser]
    let onCreated: (String) -> Void  // chatId
    @Environment(\.dismiss) private var dismiss

    @State private var groupName: String = ""
    @State private var avatar: UIImage?
    @State private var selected: Set<String> = []
    @State private var searchText: String = ""
    @State private var isCreating = false
    @State private var errorText: String?

    // Empuje inferior cuando hay teclado (sube toda la vista)
    @State private var keyboardInset: CGFloat = 0

    // Foco para poder mostrar/ocultar teclado desde la toolbar del teclado
    @FocusState private var isInputFocused: Bool

    // Visibilidad “teclado abierto”
    private var isKeyboardVisible: Bool { keyboardInset > 0 }

    var body: some View {
        NavigationStack {
            VStack {
                // Paso 1: nombre + avatar
                VStack(spacing: 16) {
                    GroupAvatarPicker(uiImage: $avatar)
                    TextField("Nombre del grupo", text: $groupName)
                        .textFieldStyle(.roundedBorder)
                        .padding(.horizontal)
                        .focused($isInputFocused)
                }
                .padding(.top, 20)

                // Header inline cuando hay teclado (sustituye a la nav bar)
                if isKeyboardVisible {
                    HStack {
                        Button("Cancelar") { dismiss() }
                        Spacer()
                        Text("Nuevo grupo").font(.headline)
                        Spacer()
                        Color.clear.frame(width: 1, height: 1).opacity(0)
                    }
                    .padding(.horizontal)
                    .padding(.top, 4)
                }

                // Barra de búsqueda (inline, encima de la lista)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                    TextField("Buscar usuarios", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .submitLabel(.search)
                        .focused($isInputFocused)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Borrar búsqueda")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                        .padding(.horizontal)
                )

                // Paso 2: selección múltiple
                List {
                    Section("Miembros") {
                        ForEach(filteredUsers) { u in
                            MultipleSelectionRow(
                                title: u.displayName,
                                isSelected: selected.contains(u.id),
                                photoURL: u.photoURL
                            ) {
                                if selected.contains(u.id) { selected.remove(u.id) }
                                else { selected.insert(u.id) }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.interactively)

                if let e = errorText {
                    Text(e).foregroundColor(.red).padding(.top, 4)
                }

                Button {
                    Task { await createGroup() }
                } label: {
                    if isCreating { ProgressView() }
                    else { Text("Crear grupo") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreating || groupName.trimmed().isEmpty || selected.isEmpty)
                .padding()
            }
            .navigationTitle("Nuevo grupo")
            // Oculta nav bar cuando hay teclado (mostramos el header inline arriba)
            .toolbar(isKeyboardVisible ? .hidden : .visible, for: .navigationBar)
            // Empuja TODA la vista al aparecer el teclado
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: keyboardInset)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                // Botón nativo en la barra del teclado para ocultarlo
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button {
                        isInputFocused = false
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                    }
                    .accessibilityLabel("Ocultar teclado")
                }
            }
        }
        // Escucha el teclado y ajusta el inset inferior (sube/baja toda la vista)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            guard
                let userInfo = note.userInfo,
                let frame = (userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue
            else { return }

            // Altura efectiva del teclado respecto a pantalla
            let screenHeight = UIScreen.main.bounds.height
            let overlap = max(0, screenHeight - frame.origin.y)

            // Descuenta safe-area inferior de la ventana activa
            let window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
            let safeBottom = window?.safeAreaInsets.bottom ?? 0

            withAnimation(.easeOut(duration: 0.20)) {
                keyboardInset = max(0, overlap - safeBottom)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.20)) {
                keyboardInset = 0
            }
        }
    }

    // MARK: - Filtrado en vivo
    private var filteredUsers: [SelectableUser] {
        let q = searchText.normalizedForSearch()
        guard !q.isEmpty else { return allUsers } // vacío → lista completa
        return allUsers.filter { user in
            user.displayName.normalizedForSearch().contains(q)
        }
    }

    private func createGroup() async {
        guard !isCreating else { return }
        isCreating = true; defer { isCreating = false }
        errorText = nil
        guard Auth.auth().currentUser?.uid != nil else {
            errorText = "Sesión inválida"; return
        }
        let members = Array(selected)

        do {
            // 1) Crear chat (sin foto)
            let chatId = try await GroupAPI.shared.createGroup(name: groupName, memberIds: members)
            // 2) Subir avatar (opcional) y setear photoURL con bust
            if let img = avatar {
                let url = try await GroupAvatarUploader.upload(chatId: chatId, image: img)
                try await GroupAPI.shared.setGroupPhoto(chatId: chatId, photoURL: url)
            }
            onCreated(chatId)
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Row selección múltiple
private struct MultipleSelectionRow: View {
    let title: String
    let isSelected: Bool
    let photoURL: String?
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack {
                avatarView  // foto o iniciales
                Text(title)
                Spacer()
                if isSelected { Image(systemName: "checkmark.circle.fill") }
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let url = photoURL {
            CachedAvatarImageView(urlString: url, initials: title, size: 36)
        } else {
            let letters = String(title.prefix(2)).uppercased()
            ZStack {
                Circle().fill(Color.blue.opacity(0.2)).frame(width: 36, height: 36)
                Text(letters).font(.subheadline.bold()).foregroundColor(.blue)
            }
        }
    }
}

// MARK: - Utils
private extension String {
    func trimmed() -> String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

private extension String {
    /// Normaliza para búsqueda: minúsculas, sin acentos y sin emojis
    func normalizedForSearch() -> String {
        // 1) Minusculas + sin diacríticos (á→a, ñ→n, ü→u)
        var s = self.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        // 2) Elimina emojis (y símbolos de presentación de emoji)
        s.removeAll { ch in
            ch.unicodeScalars.contains { $0.properties.isEmoji || $0.properties.isEmojiPresentation }
        }
        // 3) Trim + a minúsculas
        s = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return s
    }
}
