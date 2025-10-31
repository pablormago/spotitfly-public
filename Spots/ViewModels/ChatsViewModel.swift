//
//  ChatsViewModel.swift
//  Spots
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class ChatsViewModel: ObservableObject {
    static let shared = ChatsViewModel()

    // MARK: - Constantes internas
    private let SUPPORT_BOT_ID = "26CSxWS7R7eZlrvXUV1qJFyL7Oc2"
    private let ADMIN_EMAIL = "pablormago@gmail.com"

    // 🔒 Claves de caché local (UserDefaults)
    private let NAMES_CACHE_KEY   = "ChatsVM.usernames.v1"
    private let AVATARS_CACHE_KEY = "ChatsVM.profileImages.v1"
    private let GROUP_PHOTOS_CACHE_KEY = "ChatsVM.groupPhotos.v1"


    // MARK: - Estado público
    @Published var chats: [Chat] = []
    @Published var unreadCount: Int = 0
    @Published var usernames: [String: String] = [:]
    @Published var profileImages: [String: String] = [:]
    @Published var blockedUsers: Set<String> = []
    @Published var groupPhotos: [String: String] = [:]   // idChat -> photoURL (solo grupos)


    // MARK: - Internos
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var userListener: ListenerRegistration?
    private var userDocListeners: [String: ListenerRegistration] = [:] // uid -> listener

    /// Overrides locales de lectura (anti-parpadeo hasta que llegue Firestore)
    /// Mapa: chatId -> (uid -> lastReadDate)
    private var localOverrides: [String: [String: Date]] = [:]

    /// Overrides locales de ocultación (anti-parpadeo al alternar oculto/visible)
    /// Mapa: chatId -> hidden(bool) SOLO para el uid actual
    private var localHiddenOverrides: [String: Bool] = [:]

    /// Flag cacheado: ¿soy admin?
    private var isAdmin: Bool = false

    // MARK: - Init → precarga desde disco
    private init() {
        if let rawNames = UserDefaults.standard.dictionary(forKey: NAMES_CACHE_KEY) as? [String: String] {
            self.usernames = rawNames
        }
        if let rawAvatars = UserDefaults.standard.dictionary(forKey: AVATARS_CACHE_KEY) as? [String: String] {
            self.profileImages = rawAvatars
        }
        if let rawGroups = UserDefaults.standard.dictionary(forKey: GROUP_PHOTOS_CACHE_KEY) as? [String: String] {
            self.groupPhotos = rawGroups
        }
    }

    // MARK: - Arranque
    func start() {
        guard let user = Auth.auth().currentUser else { return }
        let uid = user.uid

        // Resolver flag admin por email
        let email = user.email?.lowercased() ?? ""
        self.isAdmin = (email == ADMIN_EMAIL.lowercased())

        // Limpia listeners previos
        stop()

        // Escucha usuario para bloqueados
        userListener = db.collection("users").document(uid)
            .addSnapshotListener { [weak self] snap, error in
                guard let self else { return }
                if let error {
                    print("❌ Error en userListener:", error.localizedDescription)
                    return
                }
                let data = snap?.data() ?? [:]
                let arr = data["blockedUsers"] as? [String] ?? []
                self.blockedUsers = Set(arr)

                // ✅ NO filtrar ocultos aquí (solo bloqueados)
                self.chats = self.chats.filter { chat in
                    let other = chat.participants.first(where: { $0 != uid }) ?? ""
                    return !self.blockedUsers.contains(other)
                }
                self.updateUnreadCount(for: uid)
            }

        // Listener de chats donde participo
        listener = db.collection("chats")
            .whereField("participants", arrayContains: uid)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, err in
                guard let self else { return }
                if let err {
                    print("❌ Chats listener error:", err.localizedDescription)
                    return
                }
                guard let docs = snap?.documents else {
                    self.chats = []
                    self.unreadCount = 0
                    // limpia listeners de perfiles si no hay chats
                    self.subscribeUserDocs(for: [])
                    return
                }
                Task { await self.processDocuments(docs, uid: uid) }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
        userListener?.remove()
        userListener = nil
        for (_, l) in userDocListeners { l.remove() }
        userDocListeners.removeAll()
    }

    // MARK: - Unread
    private func updateUnreadCount(for uid: String) {
        unreadCount = chats.reduce(0) { acc, chat in
            acc + (chat.isUnread(for: uid) ? 1 : 0)
        }
    }

    // MARK: - Procesado de snapshots (rápido + resolución diferida en lote)
    private func processDocuments(_ docs: [QueryDocumentSnapshot], uid: String) async {
        var result: [Chat] = []
        var toFetchUserDocs = Set<String>() // uids que faltan (username o avatar)

        for doc in docs {
            let data = doc.data()

            // Flags
            let isSupport = data["isSupport"] as? Bool ?? false
            let hiddenFor = data["hiddenFor"] as? [String] ?? []   // legacy

            // Campos base
            let id = doc.documentID
            let participants = data["participants"] as? [String] ?? []
            let lastMessage = data["lastMessage"] as? String
            let ts = data["updatedAt"] as? Timestamp
            let updatedAt = ts?.dateValue()
            let lastSenderId = data["lastSenderId"] as? String

            // Filtros cliente
            // ❌ Ya NO descartamos por hiddenFor: deben aparecer en “Chats ocultos”
            if let other = participants.first(where: { $0 != uid }),
               !isSupport,
               blockedUsers.contains(other) {
                continue
            }
            // En bandeja normal del admin, no queremos triadas {admin, soporte, otro}
            if isAdmin && isSupport {
                let humans = participants.filter { $0 != SUPPORT_BOT_ID }
                if !(humans.count == 1 && humans.first == uid) {
                    continue
                }
            }

            // lastRead desde servidor
            var lastReadDates: [String: Date] = [:]
            if let lastReadMap = data["lastRead"] as? [String: Any] {
                for (k, v) in lastReadMap {
                    if let t = v as? Timestamp { lastReadDates[k] = t.dateValue() }
                    else if let d = v as? Date { lastReadDates[k] = d }
                }
            }

            // 🔧 Purga temprana de overrides locales si el server ya va por delante
            if var map = self.localOverrides[id],
               let _ = map[uid] {
                let serverLR = lastReadDates[uid] ?? .distantPast
                let serverUpdated = updatedAt ?? .distantPast
                if serverLR >= serverUpdated {
                    map.removeValue(forKey: uid)
                    if map.isEmpty { self.localOverrides.removeValue(forKey: id) }
                    else { self.localOverrides[id] = map }
                }
            }

            // ✅ Mezcla override local (anti-parpadeo)
            if let ovr = self.localOverrides[id], let ovrDate = ovr[uid] {
                let current = lastReadDates[uid] ?? .distantPast
                if ovrDate > current {
                    lastReadDates[uid] = ovrDate
                }
            }

            // Resolución displayName (rápida, usando caché local cargada en init)
            // 👥 Grupos vs 1:1 (robusto, sin falsos positivos)
            let membersCount =
                (data["membersCount"] as? Int) ??
                (data["memberCount"] as? Int) ??
                ((data["members"] as? [String: Any])?.count) ??
                participants.count

            let isGroup = ((data["type"] as? String) == "group") || (membersCount >= 3)

            var displayName: String?
            if isGroup {
                // Nombre y foto del propio chat
                displayName = (data["name"] as? String) ?? "Grupo"
                if let p = data["photoURL"] as? String, !p.isEmpty {
                    DispatchQueue.main.async {
                        self.groupPhotos[id] = p
                        self.persistCachesToDisk()
                    }
                    // precalienta en segundo plano
                    // precalienta en segundo plano
                    Task.detached {
                        await MediaCache.shared.prefetch(urlString: p)
                    }
                } else {
                    DispatchQueue.main.async {
                        self.groupPhotos.removeValue(forKey: id)
                        self.persistCachesToDisk()
                    }
                }

            } else {
                // 1:1 como siempre
                let other = participants.first(where: { $0 != uid }) ?? uid
                displayName = usernames[other] ?? (isSupport ? "Soporte" : nil)

                if usernames[other] == nil || profileImages[other] == nil {
                    toFetchUserDocs.insert(other)
                }
            }



            // --- isHidden robusto + anti-flicker ---
            // 1) Parse robusto de isHidden: tolera [String: Any] -> [String: Bool]
            let serverIsHidden: [String: Bool]? = {
                if let m = data["isHidden"] as? [String: Bool] { return m }
                if let any = data["isHidden"] as? [String: Any] {
                    var out: [String: Bool] = [:]
                    for (k, v) in any { if let b = v as? Bool { out[k] = b } }
                    return out.isEmpty ? nil : out
                }
                return nil
            }()

            // 2) Merge prioritario: servidor > lo que ya había en memoria > legacy hiddenFor
            let mergedIsHidden: [String: Bool]? = {
                if let map = serverIsHidden { return map }
                if let existing = self.chats.first(where: { $0.id == id }), let map = existing.isHidden {
                    return map
                }
                if hiddenFor.contains(uid) { return [uid: true] }
                return nil
            }()

            // 2.5) Antiflicker: aplica override local hasta que el server coincida
            var finalIsHidden: [String: Bool] = mergedIsHidden ?? [:]
            if let local = self.localHiddenOverrides[id] {
                finalIsHidden[uid] = local
                if let srv = serverIsHidden?[uid], srv == local {
                    // el server ya coincide -> elimina override
                    self.localHiddenOverrides.removeValue(forKey: id)
                }
            }

            // 3) DEBUG (temporal): imprime cómo llega y qué se decide
            print("🧭 ChatsVM.process id=\(id) uid=\(uid) raw isHidden=\(String(describing: data["isHidden"])) parsed=\(String(describing: serverIsHidden)) hiddenFor=\(hiddenFor) ⇒ hidden=\(finalIsHidden[uid] ?? false)")

            // Construcción del Chat
            let chat = Chat(
                id: id,
                participants: participants,
                lastMessage: lastMessage,
                updatedAt: updatedAt,
                displayName: displayName,
                lastRead: lastReadDates,
                lastSenderId: lastSenderId,
                isHidden: finalIsHidden.isEmpty ? nil : finalIsHidden,
                hiddenFor: hiddenFor // legacy, por compat
            )

            result.append(chat)
        }

        // Publica la lista YA (render instantáneo)
        self.chats = result
        self.updateUnreadCount(for: uid)

        // Suscríbete a perfiles de los "otros" usuarios visibles (refresco en vivo + persistencia)
        let others = Set(result.compactMap { chat in
            chat.participants.first(where: { $0 != uid })
        })
        self.subscribeUserDocs(for: others)

        // Precalienta caché de imágenes para todos los chats visibles (1:1 + grupos)
        Task.detached { [weak self] in
            guard let self else { return }
            var urls = Set<String>()
            for c in result {
                if c.participants.count > 2 {
                    if let u = await self.groupPhotos[c.id], !u.isEmpty {
                        urls.insert(u)
                    }
                } else if let other = c.participants.first(where: { $0 != uid }),
                          let u = await self.profileImages[other], !u.isEmpty {
                    urls.insert(u)
                }
            }
            await withTaskGroup(of: Void.self) { group in
                for u in urls {
                    group.addTask { await MediaCache.shared.prefetch(urlString: u) }
                }
                await group.waitForAll()
            }
        }



        // Resolución diferida en lote (no bloquea la UI)
        guard !toFetchUserDocs.isEmpty else { return }
        Task.detached { [weak self] in
            guard let self else { return }
            await self.fetchMissingUserFields(for: Array(toFetchUserDocs))
        }
    }

    // MARK: - Suscripción a docs de usuario (refresco en vivo + persistencia)
    private func subscribeUserDocs(for uids: Set<String>) {
        // Limpia los que ya no están
        for (uid, l) in userDocListeners {
            if !uids.contains(uid) {
                l.remove()
                userDocListeners.removeValue(forKey: uid)
            }
        }
        // Añade los que faltan
        for uid in uids where userDocListeners[uid] == nil {
            let l = db.collection("users").document(uid)
                .addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, _ in
                    guard let self, let data = snap?.data() else { return }

                    var changed = false
                    if let name = data["username"] as? String, !name.isEmpty, self.usernames[uid] != name {
                        self.usernames[uid] = name
                        changed = true
                    }
                    if let url = data["profileImageUrl"] as? String, !url.isEmpty, self.profileImages[uid] != url {
                        self.profileImages[uid] = url
                        changed = true
                        // precalienta en segundo plano
                        Task.detached {
                            await MediaCache.shared.prefetch(urlString: url)
                        }
                    }


                    if changed {
                        // Refresca displayName en la lista
                        if let myUid = Auth.auth().currentUser?.uid {
                            for i in 0..<self.chats.count {
                                var c = self.chats[i]
                                if let other = c.participants.first(where: { $0 != myUid }), other == uid {
                                    c.displayName = self.usernames[uid] ?? c.displayName
                                    self.chats[i] = c
                                }
                            }
                        }
                        // Persiste para arranque instantáneo
                        self.persistCachesToDisk()
                    }
                }
            userDocListeners[uid] = l
        }
    }

    // MARK: - Resolución en lote de usernames + avatars
    private func fetchMissingUserFields(for uids: [String]) async {
        let needing = uids.filter { self.usernames[$0] == nil || self.profileImages[$0] == nil }
        guard !needing.isEmpty else { return }

        // Firestore 'in' query admite hasta 10 ids por tanda
        let chunks = stride(from: 0, to: needing.count, by: 10).map {
            Array(needing[$0..<min($0+10, needing.count)])
        }

        var newUsernames: [String: String] = [:]
        var newAvatars: [String: String] = [:]

        for batch in chunks {
            do {
                let snap = try await db.collection("users")
                    .whereField(FieldPath.documentID(), in: batch)
                    .getDocuments()

                for doc in snap.documents {
                    let uid = doc.documentID
                    if self.usernames[uid] == nil, let uname = doc.get("username") as? String {
                        newUsernames[uid] = uname
                    }
                    if self.profileImages[uid] == nil, let url = doc.get("profileImageUrl") as? String, !url.isEmpty {
                        newAvatars[uid] = url
                    }
                }
            } catch {
                print("⚠️ fetchMissingUserFields batch error:", error.localizedDescription)
            }
        }

        if !newUsernames.isEmpty || !newAvatars.isEmpty {
            await MainActor.run {
                for (k, v) in newUsernames { self.usernames[k] = v }
                for (k, v) in newAvatars  { self.profileImages[k] = v }
                self.persistCachesToDisk()

                if let myUid = Auth.auth().currentUser?.uid {
                    for i in 0..<self.chats.count {
                        var c = self.chats[i]
                        if let other = c.participants.first(where: { $0 != myUid }) {
                            if (c.displayName == nil || c.displayName?.isEmpty == true),
                               let resolved = self.usernames[other] {
                                c.displayName = resolved
                                self.chats[i] = c
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Persistencia local (UserDefaults)
    private func persistCachesToDisk() {
        UserDefaults.standard.set(self.usernames,     forKey: NAMES_CACHE_KEY)
        UserDefaults.standard.set(self.profileImages, forKey: AVATARS_CACHE_KEY)
        UserDefaults.standard.set(self.groupPhotos,   forKey: GROUP_PHOTOS_CACHE_KEY)
    }


    // MARK: - Overrides locales (anti-parpadeo lastRead)
    func applyLocalRead(chatId: String, uid: String, at date: Date = Date()) {
        var map = localOverrides[chatId] ?? [:]
        if let prev = map[uid], prev >= date { return }
        map[uid] = date
        localOverrides[chatId] = map

        if let idx = chats.firstIndex(where: { $0.id == chatId }) {
            var chat = chats[idx]
            var lr = chat.lastRead ?? [:]
            let newDate = max(lr[uid] ?? .distantPast, date)
            lr[uid] = newDate
            chat.lastRead = lr
            chats[idx] = chat
            updateUnreadCount(for: uid)
        }
    }

    /// Alias que ya usa `ChatDetailView` al cerrar (compat).
    func forceUpdate(chatId: String, uid: String) {
        applyLocalRead(chatId: chatId, uid: uid, at: Date())
    }

    // MARK: - Override local (anti-parpadeo ocultos)
    func applyLocalHidden(chatId: String, uid: String, hidden: Bool) {
        // Guarda override
        localHiddenOverrides[chatId] = hidden

        // Refleja INSTANTÁNEAMENTE en el array publicado
        if let idx = chats.firstIndex(where: { $0.id == chatId }) {
            var c = chats[idx]
            var map = c.isHidden ?? [:]
            map[uid] = hidden
            c.isHidden = map.isEmpty ? nil : map
            chats[idx] = c
        }
    }
}
