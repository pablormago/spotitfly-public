//
//  MemberRow.swift
//  Spots
//
//  Created by Pablo Jimenez on 24/10/25.
//

import SwiftUI
import FirebaseFirestore
import PhotosUI
import FirebaseStorage
import UIKit

struct MemberRow: Identifiable, Hashable {
    let id: String
    let displayName: String
    let photoURL: String?
    let role: String // "owner" | "admin" | "member" (solo UX por ahora)
}

struct GroupMembersSheet: View {
    let chatId: String
    let currentUserId: String
    @State var members: [MemberRow]
    
    // Picker interno (presentado por este sheet)
    @State private var showAddPicker = false
    // 🔁 Listener Firestore de participantes
    @State private var participantsListener: ListenerRegistration? = nil
    
    @State private var showOwnerLeaveAlert = false
    
    // Gestión de nombre y foto del grupo (solo Owner/Admin)
    @State private var groupName: String = ""
    @State private var showRenameSheet = false
    @State private var newName: String = ""
    @State private var isRenaming = false
    
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var isUploadingPhoto = false
    
    // Foto del grupo (URL remota; se cachea con clave estable "chat:<chatId>")
    @State private var groupPhotoURL: String? = nil
    
    // Invitaciones + límite
    @State private var maxMembers: Int = 64
    @State private var inviteURL: String? = nil
    @State private var isCreatingInvite = false
    @State private var isRevokingInvite = false
    @State private var showRevokeConfirm = false
    
    // Toast (copiado)
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastIcon: String? = nil
    
    // Acciones (inyectables desde fuera)
    let onAdd: () -> Void
    let onRemove: (String) -> Void
    let onPromote: (String) -> Void
    let onDemote: (String) -> Void      // 🆕 quitar admin
    let onLeave: () -> Void
    let onToggleMute: (_ mute: Bool) -> Void
    let initialMute: Bool
    
    @Environment(\.dismiss) private var dismiss
    @State private var isMuted: Bool
    
    init(chatId: String,
         currentUserId: String,
         members: [MemberRow],
         initialMute: Bool,
         onAdd: @escaping () -> Void,
         onRemove: @escaping (String) -> Void,
         onPromote: @escaping (String) -> Void,
         onDemote: @escaping (String) -> Void,   // 🆕
         onLeave: @escaping () -> Void,
         onToggleMute: @escaping (_ mute: Bool) -> Void) {
        self.chatId = chatId
        self.currentUserId = currentUserId
        self._members = State(initialValue: members)
        self.initialMute = initialMute
        self.onAdd = onAdd
        self.onRemove = onRemove
        self.onDemote = onDemote                 // 🆕 asegura inicialización
        self.onPromote = onPromote
        self.onLeave = onLeave
        self.onToggleMute = onToggleMute
        _isMuted = State(initialValue: initialMute)
    }
    
    var body: some View {
        NavigationStack {
            List {
                // Avatar del grupo (header)
                Section {
                    HStack {
                        Spacer()
                        CachedAvatarImageView(
                            urlString: groupPhotoURL,
                            initials: groupName.isEmpty ? "GR" : groupName,
                            size: 72,
                            stableKey: "chat:\(chatId)"
                        )
                        .onAppear {
                            if let u = groupPhotoURL {
                                MediaCache.shared.prefetch(urlString: u)
                            }
                        }
                        Spacer()
                    }
                }
                Section {
                    Toggle("Silenciar este grupo", isOn: $isMuted)
                        .onChange(of: isMuted) { _, v in onToggleMute(v) }
                }
                
                // Solo owner o admin pueden ver y usar estas secciones
                if canManageGroup {
                    Section("Configuración del grupo") {
                        Button {
                            newName = groupName
                            showRenameSheet = true
                        } label: {
                            Label("Renombrar grupo", systemImage: "pencil")
                        }
                        
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            HStack {
                                Label("Cambiar foto", systemImage: "camera")
                                if isUploadingPhoto {
                                    Spacer()
                                    ProgressView().controlSize(.small)
                                }
                            }
                        }
                        .disabled(isUploadingPhoto)
                    }
                    
                    // Invitaciones + Límite
                    Section("Invitaciones") {
                        HStack {
                            Label("Miembros", systemImage: "person.3.fill")
                            Spacer()
                            Text("\(members.count) / \(maxMembers)")
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                        
                        if let url = inviteURL {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Enlace activo")
                                    .font(.subheadline.weight(.semibold))
                                
                                Text(url)
                                    .font(.footnote)
                                    .foregroundColor(.blue)
                                    .textSelection(.enabled)
                                
                                HStack(spacing: 12) {
                                    Button {
                                        UIPasteboard.general.string = url
                                        // 👇 Toast 3s
                                        toastMessage = "Enlace de invitación copiado al portapapeles"
                                        toastIcon = "doc.on.doc.fill"
                                        showToast = true
                                    } label: {
                                        Label("Copiar enlace", systemImage: "doc.on.doc")
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Spacer(minLength: 12)
                                    
                                    Button(role: .destructive) {
                                        showRevokeConfirm = true
                                    } label: {
                                        Label("Revocar", systemImage: "xmark.seal.fill")
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(isRevokingInvite)
                                }
                            }
                            .contentShape(Rectangle())
                            .alert("¿Revocar el enlace de invitación?", isPresented: $showRevokeConfirm) {
                                Button("Cancelar", role: .cancel) {}
                                Button("Revocar", role: .destructive) {
                                    Task {
                                        isRevokingInvite = true
                                        defer { isRevokingInvite = false }
                                        try? await GroupAPI.shared.revokeInviteLink(chatId: chatId)
                                        await MainActor.run { inviteURL = nil }
                                    }
                                }
                            } message: {
                                Text("Nadie podrá usar el enlace actual para unirse.")
                            }
                        } else {
                            Button {
                                Task {
                                    isCreatingInvite = true
                                    defer { isCreatingInvite = false }
                                    if let url = try? await GroupAPI.shared.createInviteLink(chatId: chatId) {
                                        await MainActor.run { inviteURL = url }
                                    }
                                }
                            } label: {
                                Label("Crear enlace de invitación", systemImage: "link.badge.plus")
                            }
                            .disabled(isCreatingInvite)
                        }
                        
                        
                        if members.count >= maxMembers {
                            Text("Este grupo ha alcanzado el límite de miembros.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("Miembros") {
                    ForEach(members) { m in
                        HStack {
                            AvatarStub(url: m.photoURL)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(m.displayName)
                                Text(m.role).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if m.id != currentUserId {
                                Menu {
                                    Button("Quitar", role: .destructive) { onRemove(m.id) }
                                    // Solo el owner puede cambiar roles
                                    if (members.first { $0.id == currentUserId }?.role) == "owner" {
                                        if m.role == "admin" {
                                            Button("Quitar admin") { onDemote(m.id) }
                                        } else if m.role == "member" {
                                            Button("Promover a admin") { onPromote(m.id) }
                                        }
                                    }
                                } label: { Image(systemName: "ellipsis.circle") }
                            } else {
                                Text("Tú").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
            }
            .navigationTitle(groupName.isEmpty ? "Miembros" : groupName)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddPicker = true
                    } label: {
                        Label("Añadir", systemImage: "person.badge.plus")
                    }
                    .disabled(!canManageGroup || members.count >= maxMembers)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button(role: .destructive) {
                        if (members.first { $0.id == currentUserId }?.role) == "owner" {
                            showOwnerLeaveAlert = true
                        } else {
                            onLeave()
                        }
                    } label: {
                        Label("Salir del grupo", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .sheet(isPresented: $showAddPicker) {
                // Excluir miembros ya existentes
                let existing = Set(members.map { $0.id })
                AddMembersPicker(exclude: existing) { picked in
                    Task {
                        do {
                            // Recorte defensivo por límite local (el servidor valida de todas formas)
                            let allowed = max(0, maxMembers - members.count)
                            let toSend = Array(picked.prefix(allowed))
                            guard !toSend.isEmpty else { return }
                            
                            // 1) Alta en backend
                            try await GroupAPI.shared.addMembers(chatId: chatId, memberIds: toSend)
                            
                            // 2) Refrescar UI local: obtener nombres/fotos de los nuevos y añadir a 'members'
                            let col = Firestore.firestore().collection("users")
                            var appended: [MemberRow] = []
                            for uid in toSend {
                                do {
                                    let snap = try await col.document(uid).getDocument()
                                    let data = snap.data() ?? [:]
                                    let name =
                                    (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                                    ?? (data["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                                    ?? (data["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                                    ?? (data["fullName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                                    ?? "Usuario"
                                    let photo =
                                    (data["profileImageUrl"] as? String)
                                    ?? (data["photoURL"] as? String)
                                    ?? (data["avatarURL"] as? String)
                                    ?? (data["profilePhotoURL"] as? String)
                                    
                                    appended.append(MemberRow(id: uid, displayName: name, photoURL: photo, role: "member"))
                                } catch {
                                    appended.append(MemberRow(id: uid, displayName: "Usuario", photoURL: nil, role: "member"))
                                }
                            }
                            let before = Set(members.map { $0.id })
                            let newOnes = appended.filter { !before.contains($0.id) }
                            await MainActor.run { members.append(contentsOf: newOnes) }
                            
                            // 3) Avisar al padre (por si necesita refrescar fuera)
                            onAdd()
                        } catch {
                            print("❌ addMembers:", error.localizedDescription)
                        }
                    }
                }
            }
            .sheet(isPresented: $showRenameSheet) {
                NavigationStack {
                    Form {
                        Section("Nombre del grupo") {
                            TextField("Nombre", text: $newName)
                                .textInputAutocapitalization(.words)
                                .disableAutocorrection(true)
                        }
                    }
                    .navigationTitle("Renombrar")
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancelar") { showRenameSheet = false }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                Task {
                                    guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                                    isRenaming = true
                                    do {
                                        try await GroupAPI.shared.renameGroup(
                                            chatId: chatId,
                                            name: newName.trimmingCharacters(in: .whitespacesAndNewlines)
                                        )
                                        groupName = newName
                                        showRenameSheet = false
                                    } catch {
                                        print("❌ renameGroup:", error.localizedDescription)
                                    }
                                    isRenaming = false
                                }
                            } label: {
                                if isRenaming { ProgressView() } else { Text("Guardar") }
                            }
                            .disabled(isRenaming || newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await uploadNewGroupPhoto(from: item) }
            }
            
        }
        .toast(isPresented: $showToast, message: toastMessage, systemImage: toastIcon, duration: 3.0)
        
        .alert("¿Salir del grupo?", isPresented: $showOwnerLeaveAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Salir", role: .destructive) { onLeave() }
        } message: {
            Text("Eres el propietario. Al salir, la propiedad se transferirá automáticamente a un admin (si queda) o al miembro más antiguo.")
        }
        .onAppear {
            startParticipantsListener()
        }
        .onDisappear {
            participantsListener?.remove()
            participantsListener = nil
        }
        
    }
    // MARK: - Live updates de participantes (dentro del struct)
    
    private func startParticipantsListener() {
        let db = Firestore.firestore()
        participantsListener?.remove()
        participantsListener = db.collection("chats").document(chatId)
            .addSnapshotListener { snap, _ in
                guard let data = snap?.data() else { return }
                
                // Roles reales desde el chat
                let ownerId = (data["ownerId"] as? String) ?? (data["createdBy"] as? String) ?? ""
                let adminList = (data["admins"] as? [String]) ?? []
                let admins = Set(adminList)
                let participants = (data["participants"] as? [String]) ?? []
                let name = (data["name"] as? String) ?? "Grupo"
                let limit = (data["maxMembers"] as? Int) ?? 64
                // Foto del grupo: admite varios nombres de campo por compatibilidad
                let photoURL =
                (data["photoURL"] as? String)
                ?? (data["groupPhotoURL"] as? String)
                ?? (data["avatarURL"] as? String)
                
                // Mantener nombres/fotos ya pasados al sheet; rellenar huecos si faltan
                let byId = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
                
                var newMembers: [MemberRow] = []
                newMembers.reserveCapacity(participants.count)
                
                for uid in participants {
                    let base = byId[uid]
                    let role: String = {
                        if uid == ownerId { return "owner" }
                        if admins.contains(uid) { return "admin" }
                        return "member"
                    }()
                    
                    newMembers.append(MemberRow(
                        id: uid,
                        displayName: base?.displayName ?? uid,
                        photoURL: base?.photoURL,
                        role: role
                    ))
                }
                
                // Orden: owner → admins → resto (opc.)
                newMembers.sort { a, b in
                    let rank: (String) -> Int = { r in
                        switch r { case "owner": return 0; case "admin": return 1; default: return 2 }
                    }
                    if rank(a.role) != rank(b.role) { return rank(a.role) < rank(b.role) }
                    return a.displayName.localizedCaseInsensitiveCompare(b.displayName) == .orderedAscending
                }
                
                DispatchQueue.main.async {
                    self.members = newMembers
                    self.groupName = name
                    self.maxMembers = limit
                    self.groupPhotoURL = photoURL
                }
                
            }
    }
    
    // Sincroniza la lista local 'members' con el array 'participants'
    @MainActor
    private func syncMembers(with participants: [String]) async {
        let currentIds = Set(members.map { $0.id })
        let incoming = Set(participants)
        
        // Remociones
        let removed = currentIds.subtracting(incoming)
        if !removed.isEmpty {
            members.removeAll { removed.contains($0.id) }
        }
        
        // Altas: para los que no estuvieran, traemos nombre/foto
        let toAdd = incoming.subtracting(currentIds)
        guard !toAdd.isEmpty else { return }
        
        let col = Firestore.firestore().collection("users")
        var appended: [MemberRow] = []
        for uid in toAdd {
            do {
                let snap = try await col.document(uid).getDocument()
                let d = snap.data() ?? [:]
                let name =
                (d["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (d["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (d["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (d["fullName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Usuario"
                let photo =
                (d["profileImageUrl"] as? String)
                ?? (d["photoURL"] as? String)
                ?? (d["avatarURL"] as? String)
                ?? (d["profilePhotoURL"] as? String)
                appended.append(MemberRow(id: uid, displayName: name, photoURL: photo, role: "member"))
            } catch {
                appended.append(MemberRow(id: uid, displayName: "Usuario", photoURL: nil, role: "member"))
            }
        }
        
        // Evita duplicados y añade
        let before = Set(members.map { $0.id })
        let newOnes = appended.filter { !before.contains($0.id) }
        members.append(contentsOf: newOnes)
    }
    
    private var canManageGroup: Bool {
        if let role = members.first(where: { $0.id == currentUserId })?.role {
            return role == "owner" || role == "admin"
        }
        return false
    }
    
    private func uploadNewGroupPhoto(from item: PhotosPickerItem) async {
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        do {
            // 1) Leer datos de la imagen del picker
            guard let data = try await item.loadTransferable(type: Data.self), !data.isEmpty else {
                print("⚠️ No se pudo leer imagen del picker")
                return
            }
            
            // 2) Subir a Storage
            let ts = Int(Date().timeIntervalSince1970 * 1000)
            let path = "chats/\(chatId)/\(currentUserId)/avatar_v\(ts).jpg"
            let ref = Storage.storage().reference(withPath: path)
            
            let meta = StorageMetadata()
            meta.contentType = "image/jpeg"
            
            _ = try await ref.putDataAsync(data, metadata: meta)
            let url = try await ref.downloadURL()
            
            // 3) Evitar cache con 'bust=' si alt=media
            var urlStr = url.absoluteString
            if urlStr.contains("alt=media") {
                urlStr += (urlStr.contains("?") ? "&" : "?") + "bust=\(ts)"
            }
            
            // 4) Guardar en el doc (tu GroupAPI ya hace setData con photoURL)
            try await GroupAPI.shared.setGroupPhoto(chatId: chatId, photoURL: urlStr)
            // Refresca el header inmediatamente (el listener también lo hará)
            await MainActor.run {
                self.groupPhotoURL = urlStr
            }
            // Sobrescribe el caché local con la imagen recién elegida (sin esperar a red)
            if let img = UIImage(data: data) {
                MediaCache.shared.storeImage(img, forKey: "chat:\(chatId)")
                MediaCache.shared.storeImage(img, forKey: urlStr)
            }

        } catch {
            print("❌ uploadNewGroupPhoto:", error.localizedDescription)
        }
    }
    
}

private struct AvatarStub: View {
    let url: String?
    var body: some View {
        ZStack {
            Circle().fill(Color.secondary.opacity(0.12))
            Image(systemName: "person.fill").font(.system(size: 14)).opacity(0.6)
        }
        .frame(width: 36, height: 36)
        .overlay(Circle().stroke(Color.black.opacity(0.06)))
        // Sustituye por tu loader de imágenes si lo tienes
    }
}

// MARK: - AddMembersPicker (búsqueda + multi-selección)
private struct AddMembersPicker: View {
    let exclude: Set<String>
    let onPicked: (_ userIds: [String]) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var results: [UserItem] = []
    @State private var selected = Set<String>()
    @State private var isSearching = false
    @State private var isSubmitting = false
    
    private struct UserItem: Identifiable, Hashable {
        let id: String
        let name: String
        let photo: String?
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Buscar por nombre o usuario…", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .submitLabel(.search)
                        .onSubmit { Task { await runSearch() } }
                }
                Section {
                    if isSearching {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Buscando…").foregroundStyle(.secondary)
                        }
                    } else if results.isEmpty && !query.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("Sin resultados").foregroundStyle(.secondary)
                    } else {
                        ForEach(results) { u in
                            Button {
                                if selected.contains(u.id) { selected.remove(u.id) } else { selected.insert(u.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    if let url = u.photo {
                                        CachedAvatarImageView(urlString: url, initials: u.name, size: 36)
                                    } else {
                                        ZStack {
                                            Circle().fill(Color.blue.opacity(0.2)).frame(width: 36, height: 36)
                                            Text(String(u.name.prefix(2)).uppercased())
                                                .font(.caption.bold()).foregroundColor(.blue)
                                        }
                                    }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(u.name).foregroundStyle(.primary)
                                        //Text(u.id).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selected.contains(u.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                            }
                            .disabled(isSubmitting)
                        }
                    }
                } header: { Text("Resultados") }
            }
            .navigationTitle("Añadir miembros")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") { dismiss() }.disabled(isSubmitting)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isSubmitting = true
                        onPicked(Array(selected))
                        dismiss()
                    } label: {
                        if isSubmitting { ProgressView() }
                        else { Text(selected.isEmpty ? "Añadir" : "Añadir (\(selected.count))") }
                    }
                    .disabled(selected.isEmpty || isSubmitting)
                }
            }
            .onChange(of: query) { _ in
                let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
                if q.count >= 2 {
                    Task { await runSearch() }
                } else {
                    results = []
                }
            }
        }
    }
    
    // Búsqueda en Firestore por usernameLower / displayNameLower
    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 2 else { await MainActor.run { results = [] }; return }
        await MainActor.run { isSearching = true }
        
        let db = Firestore.firestore()
        var found: [UserItem] = []
        
        // 1) usernameLower
        do {
            let upper = q + "\u{f8ff}"
            let snap = try await db.collection("users")
                .whereField("usernameLower", isGreaterThanOrEqualTo: q)
                .whereField("usernameLower", isLessThan: upper)
                .limit(to: 25)
                .getDocuments()
            for d in snap.documents {
                let uid = d.documentID
                if exclude.contains(uid) { continue }
                let data = d.data()
                let name =
                (data["displayName"] as? String)
                ?? (data["username"] as? String)
                ?? (data["name"] as? String)
                ?? (data["fullName"] as? String)
                ?? "Usuario"
                let photo =
                (data["profileImageUrl"] as? String)
                ?? (data["photoURL"] as? String)
                ?? (data["avatarURL"] as? String)
                ?? (data["profilePhotoURL"] as? String)
                found.append(UserItem(id: uid, name: name, photo: photo))
            }
        } catch {
            print("⚠️ búsqueda usernameLower:", error.localizedDescription)
        }
        
        // 2) displayNameLower (complemento)
        do {
            let upper = q + "\u{f8ff}"
            let snap = try await db.collection("users")
                .whereField("displayNameLower", isGreaterThanOrEqualTo: q)
                .whereField("displayNameLower", isLessThan: upper)
                .limit(to: 25)
                .getDocuments()
            for d in snap.documents {
                let uid = d.documentID
                if exclude.contains(uid) { continue }
                let data = d.data()
                let name =
                (data["displayName"] as? String)
                ?? (data["username"] as? String)
                ?? (data["name"] as? String)
                ?? (data["fullName"] as? String)
                ?? "Usuario"
                let photo =
                (data["profileImageUrl"] as? String)
                ?? (data["photoURL"] as? String)
                ?? (data["avatarURL"] as? String)
                ?? (data["profilePhotoURL"] as? String)
                let item = UserItem(id: uid, name: name, photo: photo)
                if !found.contains(item) { found.append(item) }
            }
        } catch {
            // ignora si no existe el índice
        }
        
        await MainActor.run {
            results = found
            isSearching = false
        }
    }
}
