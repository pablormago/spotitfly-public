//
//  ChatsHomeView.swift
//  Spots
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import UIKit

struct ChatsHomeView: View {
    @StateObject private var vm = ChatsViewModel.shared
    @State private var statuses: [String: String] = [:]               // uid -> estado
    @State private var statusListeners: [String: ListenerRegistration] = [:]
    @State private var chatPhotoListeners: [String: ListenerRegistration] = [:]
    
    
    // Navegación
    @State private var showingNewChat = false
    @State private var pendingChat: Chat? = nil
    @State private var chatToOpen: Chat? = nil
    @State private var navigateToChat = false
    
    // Handoff para abrir por id cuando aún no está cargado
    @State private var pendingOpenChatId: String? = nil
    
    // Unirse por invitación (⬅️ mover aquí)
    @State private var showingJoinByCode = false
    @State private var joinCode: String = ""
    
    // Anti-parpadeo (solo al volver de grupos)
    @State private var suppressUnreadChatId: String? = nil
    @State private var suppressUnreadUntil: Date? = nil
    
    // Grupos
    @State private var showingNewGroup = false
    
    @State private var showDeleteGroupAlert = false
    @State private var pendingDeletionChatId: String? = nil
    @State private var pendingDeletionChatName: String? = nil
    
    @State private var groupUsers: [SelectableUser] = []
    @State private var lastCreatedGroupId: String? = nil
    @State private var lastUsersDoc: DocumentSnapshot? = nil
    
    // Ocultos
    @State private var showHidden = false
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Constantes
    private let SUPPORT_BOT_ID = "26CSxWS7R7eZlrvXUV1qJFyL7Oc2"
    private let db = Firestore.firestore()
    
    // MARK: - Helpers
    private var currentUid: String? { Auth.auth().currentUser?.uid }
    
    private func lastPreviewText(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? text
    }
    
    private func otherId(for chat: Chat) -> String? {
        let uid = currentUid
        let isSupportChat = chat.participants.contains(SUPPORT_BOT_ID)
        
        if isSupportChat {
            // En la app del USUARIO siempre queremos ver al BOT como “otro”
            // (aunque el admin esté incluido como 3er participante)
            return SUPPORT_BOT_ID
        } else {
            // Chats normales 1:1
            return chat.participants.first { $0 != uid }
        }
    }
    
    // Calculados para que el compilador respire
    private var hiddenChats: [Chat] {
        let uid = currentUid
        return vm.chats.filter { $0.hidden(for: uid) }
    }
    
    private var visibleChats: [Chat] {
        let uid = currentUid
        return vm.chats.filter { !$0.hidden(for: uid) }
    }
    
    // MARK: - Firestore: ocultar/mostrar chat
    // BEGIN INSERT: helper optimista para publicar cambios en vm.chats
    // BEGIN PATCH: helper optimista sin auto-expansión
    @MainActor private func applyLocalHidden(chatId: String, hide: Bool, uid: String) {
        guard let i = vm.chats.firstIndex(where: { $0.id == chatId }) else { return }
        var copy = vm.chats
        var chat = copy[i]
        var map = chat.isHidden ?? [:]
        if hide { map[uid] = true } else { map.removeValue(forKey: uid) }
        chat.isHidden = map
        copy[i] = chat
        vm.chats = copy  // reasignamos el array para forzar publicación
    }
    // END PATCH
    
    // END INSERT
    
    // BEGIN PATCH: setHidden optimista + revert si falla
    private func setHidden(chatId: String, hide: Bool) async {
        guard let uid = currentUid else { return }
        let field = "isHidden.\(uid)"
        
        // 1) Optimista en UI
        await MainActor.run { applyLocalHidden(chatId: chatId, hide: hide, uid: uid) }
        
        // 2) Persistencia en Firestore
        do {
            if hide {
                try await db.collection("chats").document(chatId)
                    .setData([
                        field: true,
                        // ✅ fallback legacy para cargas iniciales
                        "hiddenFor": FieldValue.arrayUnion([uid])
                    ], merge: true)
            } else {
                try await db.collection("chats").document(chatId)
                    .setData([
                        field: FieldValue.delete(),
                        // ✅ quita del legacy también
                        "hiddenFor": FieldValue.arrayRemove([uid])
                    ], merge: true)
            }
            
        } catch {
            print("❌ setHidden error:", error.localizedDescription)
            // 3) Revertir optimismo si falla
            await MainActor.run { applyLocalHidden(chatId: chatId, hide: !hide, uid: uid) }
        }
    }
    // END PATCH
    // Marca un hilo como leído (anti-flicker local + persistencia)
    private func markAsRead(_ chat: Chat) async {
        guard let uid = currentUid else { return }
        
        // 1) Actualiza inmediatamente la UI (y badges) usando el VM compartido
        vm.applyLocalRead(chatId: chat.id, uid: uid)
        
        // 2) Persiste en Firestore (usa el método ya existente de ChatViewModel)
        let detailVM = ChatViewModel(chatId: chat.id)
        await detailVM.markAsRead(for: uid)
    }
    
    // Borrar grupo (solo Owner). Elimina el doc del chat.
    // Nota: desde cliente no borra subcolecciones; si quieres limpieza total, hacemos Function.
    private func deleteGroup(chatId: String) async {
        do {
            try await Firestore.firestore().collection("chats").document(chatId).delete()
            print("🗑️ Grupo borrado:", chatId)
        } catch {
            print("❌ Error al borrar grupo:", error.localizedDescription)
        }
    }
    
    
    var body: some View {
        VStack {
            if vm.chats.isEmpty {
                EmptyStateView()
                communityGuidelinesFooter
                    .padding(.horizontal)
            } else {
                mainListView()
            }
        }
        .navigationTitle("Chats")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true) // usamos solo el botón manual en castellano
        .alert("¿Borrar grupo “\(pendingDeletionChatName ?? "grupo")”?", isPresented: $showDeleteGroupAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Borrar", role: .destructive) {
                if let id = pendingDeletionChatId {
                    Task { await deleteGroup(chatId: id) }
                }
                pendingDeletionChatId = nil
                pendingDeletionChatName = nil
            }
        }
        .toolbar {
            // Botón manual “Atrás”
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    print("↩️ ChatsHomeView.dismiss() -> volver al mapa")
                    
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "chevron.backward")
                        Text("Atrás")
                    }
                }
            }
            
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    // Nuevo chat 1:1
                    Button {
                        showingNewChat = true
                    } label: {
                        Label("Nuevo chat", systemImage: "person.crop.circle.badge.plus")
                    }
                    
                    // Nuevo grupo
                    Button {
                        Task {
                            await loadUsersForGroup(reset: true)
                            showingNewGroup = true
                        }
                    } label: {
                        Label("Nuevo grupo", systemImage: "person.3.fill")
                    }
                    
                    // (Opcional) Unirse por código
                    // Button {
                    //     showingJoinByCode = true
                    // } label: {
                    //     Label("Unirse por código", systemImage: "link.badge.plus")
                    // }
                } label: {
                    Image(systemName: "square.and.pencil").font(.title2)
                }
            }
            
            
            
            
        }
        
        
        // Unirse por invitación
        .sheet(isPresented: $showingJoinByCode) {
            NavigationStack {
                Form {
                    Section {
                        TextField("Código (8 caracteres)", text: $joinCode)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .monospaced()
                    }
                    Section {
                        Button {
                            Task {
                                let code = joinCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                                guard !code.isEmpty else { return }
                                do {
                                    let chatId = try await GroupAPI.shared.joinByInvite(code: code)
                                    if let c = vm.chats.first(where: { $0.id == chatId }) {
                                        chatToOpen = c
                                        navigateToChat = true
                                    } else {
                                        // si aún no está en la lista, recarga y navegar cuando aparezca
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            if let c = vm.chats.first(where: { $0.id == chatId }) {
                                                chatToOpen = c
                                                navigateToChat = true
                                            }
                                        }
                                    }
                                    showingJoinByCode = false
                                    joinCode = ""
                                } catch {
                                    // TODO: mostrar alerta si quieres
                                    print("joinByInvite error:", error.localizedDescription)
                                }
                            }
                        } label: {
                            Label("Unirme", systemImage: "arrow.right.circle.fill")
                        }
                        .disabled(joinCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .navigationTitle("Unirse por invitación")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancelar") { showingJoinByCode = false }
                    }
                }
            }
        }
        // Nuevo chat
        .sheet(isPresented: $showingNewChat) {
            NavigationStack {
                NewChatView { resolvedChat in
                    pendingChat = resolvedChat
                    showingNewChat = false
                }
            }
        }
        
        // Nuevo grupo
        .sheet(isPresented: $showingNewGroup) {
            NavigationStack {
                CreateGroupFlow(allUsers: groupUsers) { newChatId in
                    lastCreatedGroupId = newChatId
                    showingNewGroup = false
                }
            }
        }
        
        
        // Empujar detalle al cerrar sheet
        .onChange(of: showingNewChat) { presented in
            if !presented, let c = pendingChat {
                chatToOpen = c
                pendingChat = nil
                navigateToChat = true
            }
        }
        
        // Cargar usuarios cuando abrimos el creador de grupos
        .onChange(of: showingNewGroup) { presented in
            if presented {
                Task { await loadUsersForGroup() }
            }
        }
        
        
        // Navegación programática
        .background(
            NavigationLink(
                destination: destinationChatDetail(),
                isActive: Binding(
                    get: { navigateToChat },
                    set: { active in
                        if !active {
                            navigateToChat = false
                            chatToOpen = nil
                        }
                    }
                )
            ) { EmptyView() }
                .hidden()
        )
        .onAppear {
            print("💬 ChatsHomeView.onAppear")
            ensureImageCacheDirExists()   // ✅ evita el error IIOImageSource
            
            // ⬇️ NEW: consumir handoff ANTES del primer render
            if
                let info = UserDefaults.standard.dictionary(forKey: "Chats.justReadOverride.v1") as? [String: Any],
                let chatId = info["chatId"] as? String,
                let ts = info["overrideAt"] as? Double,
                let uid = Auth.auth().currentUser?.uid
            {
                let at = Date(timeIntervalSince1970: ts)
                vm.applyLocalRead(chatId: chatId, uid: uid, at: at)
                UserDefaults.standard.removeObject(forKey: "Chats.justReadOverride.v1")
                // 👇 EXTRA: suprime el “unread” solo en UI durante ~0.8s para ese chat
                suppressUnreadChatId = chatId
                suppressUnreadUntil = Date().addingTimeInterval(0.8)
            }
            
            vm.start()
            subscribeToStatuses()
        }
        
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenChatById"))) { note in
            if let id = note.object as? String, !id.isEmpty {
                openChat(withId: id)
            } else if let id = note.userInfo?["chatId"] as? String, !id.isEmpty {
                openChat(withId: id)
            }
        }
        
        .onChange(of: vm.chats.map { $0.id }) { _ in
            subscribeToStatuses()
            if let target = lastCreatedGroupId,
               let c = vm.chats.first(where: { $0.id == target }) {
                chatToOpen = c
                navigateToChat = true
                lastCreatedGroupId = nil
            }
        }
        
        .onChange(of: vm.chats.map(\.id)) { _ in
            if let id = pendingOpenChatId,
               let c = vm.chats.first(where: { $0.id == id }) {
                chatToOpen = c
                navigateToChat = true
                pendingOpenChatId = nil
            }
        }
        
        
        .onDisappear {
            print("🚪 ChatsHomeView.onDisappear")
            
            removeListeners()
        }
    }
    

    
    
    
    // Verifica ownership en servidor y si procede muestra la alerta de borrado
    // Verifica ownership en servidor y si procede muestra la alerta de borrado
    private func confirmDeleteGroup(_ chat: Chat) {
        guard chat.participants.count > 2 else { return }
        guard let uid = currentUid else { return }
        let ref = Firestore.firestore().collection("chats").document(chat.id)
        ref.getDocument { snap, _ in
            guard let data = snap?.data() else { return }
            let owner = (data["ownerId"] as? String) ?? (data["createdBy"] as? String) ?? ""
            if owner == uid {
                // Resolvemos nombre priorizando Firestore: name -> displayName -> chat.displayName -> "grupo"
                let resolvedName =
                    (data["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    ?? chat.displayName
                    ?? "grupo"

                pendingDeletionChatId = chat.id
                pendingDeletionChatName = resolvedName
                showDeleteGroupAlert = true
            } else {
                print("ℹ️ No eres owner; no se muestra borrado para:", chat.id)
            }
        }
    }

    @ViewBuilder
    private func chatRowView(_ chat: Chat, inHiddenSection: Bool) -> some View {
        ChatRow(
            chat: chat,
            statusText: statusFor(chat: chat),
            isOnline: isOnline(chat: chat),
            isUnread: isUnreadEffective(chat),
            lastPreview: chat.previewLabel,
            avatarURL: avatarURL(for: chat),
            destination: ChatDetailView(chat: chat),
            
            onMarkRead: { Task { await markAsRead(chat) } },
            
            actionLabel: inHiddenSection ? "Mostrar" : "Ocultar",
            actionSystemImage: inHiddenSection ? "eye" : "eye.slash",
            actionRoleDestructive: !inHiddenSection,
            onAction: { Task { await setHidden(chatId: chat.id, hide: !inHiddenSection) } }
        )
        .contextMenu {
            if chat.participants.count > 2 {
                Button(role: .destructive) {
                    confirmDeleteGroup(chat)
                } label: {
                    Label("Borrar grupo", systemImage: "trash")
                }
            }
        }
    }
    
    func mainListView() -> some View {
        List {
            // 1) Chats visibles
            Section {
                ForEach(visibleChats, id: \.id) { chat in
                    chatRowView(chat, inHiddenSection: false)
                }
            } header: {
                Text("Chats")
            }
            
            // 2) Chats ocultos (debajo)
            if !hiddenChats.isEmpty {
                Section {
                    if showHidden {
                        ForEach(hiddenChats, id: \.id) { chat in
                            chatRowView(chat, inHiddenSection: true)
                        }
                    }
                } header: {
                    HiddenHeader(showHidden: $showHidden)
                }
            }
            
            // 3) Footer
            Section { EmptyView() } footer: {
                communityGuidelinesFooter
            }
        }
    }
    // END PATCH
    
    // END PATCH
    
    
    // MARK: - Datos para la fila
    private func statusFor(chat: Chat) -> String {
        if chat.participants.count > 2 {
            return "\(chat.participants.count) miembros"
        }
        if let other = otherId(for: chat) { return statuses[other] ?? "conectando…" }
        return "desconocido"
    }
    
    
    private func isOnline(chat: Chat) -> Bool {
        if chat.participants.count > 2 { return false }
        if let other = otherId(for: chat) { return statuses[other] == "en línea" }
        return false
    }
    
    
    private func avatarURL(for chat: Chat) -> String? {
        if chat.participants.count > 2 {
            return vm.groupPhotos[chat.id]
        }
        if let other = otherId(for: chat) { return vm.profileImages[other] }
        return nil
    }
    
    // isUnread efectivo con supresión temporal solo para el chat recién leído (grupos)
    private func isUnreadEffective(_ chat: Chat) -> Bool {
        if let sid = suppressUnreadChatId,
           let until = suppressUnreadUntil,
           sid == chat.id,
           Date() < until {
            // Durante esta pequeña ventana, fuerzo leído para evitar blink
            return false
        }
        return chat.isUnread(for: currentUid)
    }
    
    
    // MARK: - Destino
    @ViewBuilder
    private func destinationChatDetail() -> some View {
        if let chat = chatToOpen {
            ChatDetailView(chat: chat)
        } else {
            EmptyView()
        }
    }
    
    // MARK: - Estados en tiempo real
    private func subscribeToStatuses() {
        removeListeners()
        for chat in vm.chats {
            // 1:1 → escucha user doc (estado + avatar)
            if let other = otherId(for: chat) {
                let l1 = Firestore.firestore().collection("users").document(other)
                    .addSnapshotListener { snap, _ in
                        guard let data = snap?.data() else { return }
                        let status = UserStatusFormatter.format(from: data)
                        // Avatar del usuario (varios nombres por compatibilidad)
                        let avatar =
                        (data["profileImageUrl"] as? String)
                        ?? (data["photoURL"] as? String)
                        ?? (data["avatarURL"] as? String)
                        ?? (data["profilePhotoURL"] as? String)
                        
                        DispatchQueue.main.async {
                            statuses[other] = status
                            if let avatar {
                                vm.profileImages[other] = avatar
                                MediaCache.shared.prefetch(urlString: avatar)
                            }
                        }
                    }
                statusListeners[other] = l1
            }
            
            // Grupos → escucha chat doc para foto de grupo
            if chat.participants.count > 2 {
                let l2 = Firestore.firestore().collection("chats").document(chat.id)
                    .addSnapshotListener { snap, _ in
                        guard let d = snap?.data() else { return }
                        let gPhoto =
                        (d["photoURL"] as? String)
                        ?? (d["groupPhotoURL"] as? String)
                        ?? (d["avatarURL"] as? String)
                        DispatchQueue.main.async {
                            if let gPhoto {
                                vm.groupPhotos[chat.id] = gPhoto
                                MediaCache.shared.prefetch(urlString: gPhoto)
                            }
                        }
                    }
                chatPhotoListeners[chat.id] = l2
            }
        }
    }
    
    
    private func removeListeners() {
        for (_, l) in statusListeners { l.remove() }
        statusListeners.removeAll()
        for (_, l) in chatPhotoListeners { l.remove() }
        chatPhotoListeners.removeAll()
    }
    
    
    private func ensureImageCacheDirExists() {
        let fm = FileManager.default
        if let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let legacy = base.appendingPathComponent("ImageCache", isDirectory: true)
            if !fm.fileExists(atPath: legacy.path) {
                try? fm.createDirectory(at: legacy, withIntermediateDirectories: true)
            }
            let media = base.appendingPathComponent("MediaCache.v1", isDirectory: true)
            if !fm.fileExists(atPath: media.path) {
                try? fm.createDirectory(at: media, withIntermediateDirectories: true)
            }
        }
    }
    
    
    // MARK: - Carga de usuarios para grupos (mismo datasource que NewChatView)
    //@State private var lastUsersDoc: DocumentSnapshot? = nil
    
    
    private func loadUsersForGroup(reset: Bool = false) async {
        guard let me = currentUid else { return }
        let db = Firestore.firestore()
        do {
            if reset {
                await MainActor.run {
                    self.groupUsers = []
                }
                lastUsersDoc = nil
            }
            
            var q: Query = db.collection("users")
                .order(by: "usernameLower")
                .limit(to: 20)
            
            if let last = lastUsersDoc {
                q = q.start(afterDocument: last)
            }
            
            let snap = try await q.getDocuments()
            var batch: [SelectableUser] = []
            
            for doc in snap.documents {
                let uid = doc.documentID
                guard uid != me else { continue }
                let data = doc.data()
                
                // ✅ Nunca mostrar UID: usamos username del mismo campo que NewChatView
                let username = (data["username"] as? String) ?? "Usuario"
                
                // ✅ Avatar idéntico a 1-a-1
                let avatar = data["profileImageUrl"] as? String
                
                batch.append(SelectableUser(id: uid, displayName: username, photoURL: avatar))
            }
            
            await MainActor.run {
                if reset { self.groupUsers = batch } else { self.groupUsers += batch }
            }
            lastUsersDoc = snap.documents.last
        } catch {
            print("⚠️ loadUsersForGroup error:", error.localizedDescription)
            await MainActor.run { self.groupUsers = [] }
        }
    }
    
    private func openChat(withId id: String) {
        // Si ya está en memoria, navega ya
        if let c = vm.chats.first(where: { $0.id == id }) {
            chatToOpen = c
            navigateToChat = true
            pendingOpenChatId = nil
            return
        }
        // Si no, guarda el id y reintenta en breve
        pendingOpenChatId = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if let c = vm.chats.first(where: { $0.id == id }) {
                chatToOpen = c
                navigateToChat = true
                pendingOpenChatId = nil
            }
        }
    }
    
    
    
    // MARK: - Footer normas
    private var communityGuidelinesFooter: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundColor(.orange)
            Text("Recuerda seguir las normas de la comunidad: nada de spam, lenguaje ofensivo ni contenido inapropiado. Puedes reportar mensajes y usuarios desde su perfil.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("communityGuidelinesFooter")
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Fila de chat
private struct ChatRow<Destination: View>: View {
    let chat: Chat
    let statusText: String
    let isOnline: Bool
    let isUnread: Bool
    let lastPreview: String?
    let avatarURL: String?
    let destination: Destination
    // 👇 NUEVO:
    let onMarkRead: () -> Void
    
    // Acción (hide/unhide)
    let actionLabel: String
    let actionSystemImage: String
    let actionRoleDestructive: Bool
    let onAction: () -> Void
    
    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 4) {
                    header
                    statusLine
                    previewLine
                }
            }
            .padding(.vertical, 6)
        }
        .onAppear {
            if let url = avatarURL {
                MediaCache.shared.prefetch(urlString: url)
            }
        }
        
        .swipeActions {
            if actionRoleDestructive {
                Button(role: .destructive) { onAction() } label: {
                    Label(actionLabel, systemImage: actionSystemImage)
                }
            } else {
                Button { onAction() } label: {
                    Label(actionLabel, systemImage: actionSystemImage)
                }.tint(.blue)
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                onMarkRead()
            } label: {
                Label("Marcar Leído", systemImage: "checkmark.circle")
            }
            .tint(.green)
        }
        .animation(nil, value: isUnread)
        
    }
    
    private var avatar: some View {
        Group {
            if let url = avatarURL {
                // Clave de caché ESTABLE:
                // - Grupos → "chat:<chatId>"
                // - 1:1    → "user:<otherUid>"
                let key: String? = {
                    if chat.participants.count > 2 {
                        return "chat:\(chat.id)"
                    } else if let me = Auth.auth().currentUser?.uid,
                              let other = chat.participants.first(where: { $0 != me }) {
                        return "user:\(other)"
                    } else {
                        return nil
                    }
                }()
                
                CachedAvatarImageView(
                    urlString: url,
                    initials: chat.displayName,
                    size: 52,
                    stableKey: key
                )
            } else {
                let letters = String((chat.displayName ?? "U").prefix(2)).uppercased()
                ZStack {
                    Circle().fill(Color.blue.opacity(0.2)).frame(width: 52, height: 52)
                    Text(letters).font(.headline.bold()).foregroundColor(.blue)
                }
            }
        }
        .overlay(
            ZStack {
                Circle().stroke(Color.white, lineWidth: 6)
                Circle().stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.0, green: 0.85, blue: 0.9),
                            Color(red: 0.2, green: 0.5, blue: 1.0)
                        ]),
                        center: .center
                    ),
                    lineWidth: 3
                )
                .padding(-2)
            }
        )
    }
    
    
    private var header: some View {
        HStack {
            Text(chat.displayName ?? "Chat")
                .font(.headline.weight(isUnread ? .bold : .regular))
            Spacer()
            if let updatedAt = chat.updatedAt {
                Text(updatedAt, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle().fill(isOnline ? Color.green : Color.gray)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var previewLine: some View {
        HStack {
            if let last = lastPreview, !last.isEmpty {
                Text(last)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            if isUnread {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
            }
        }
    }
    
}

// MARK: - Secciones auxiliares
private struct HiddenHeader: View {
    @Binding var showHidden: Bool
    // BEGIN PATCH: HiddenHeader tap en toda la fila
    var body: some View {
        HStack {
            Text("Chats ocultos")
            Spacer()
            Image(systemName: showHidden ? "chevron.down" : "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle()) // toda la fila es clicable
        .onTapGesture {
            withAnimation(.easeInOut) { showHidden.toggle() }
        }
    }
    // END PATCH
}

private struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 42))
                .foregroundColor(.blue)
            Text("Sin chats todavía")
                .font(.title3).bold()
            Text("Cuando envíes un mensaje a otro usuario, aparecerá aquí.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)
        }
        .padding()
    }
}
