//
//  NewChatView.swift
//  Spots
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct NewChatView: View {
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchText = ""
    @State private var results: [(uid: String, username: String, avatarUrl: String?)] = []
    // Lista completa cargada (se filtra en memoria)
    @State private var allUsers: [(uid: String, username: String, avatarUrl: String?)] = []
    @State private var loading = false
    @State private var lastDocument: DocumentSnapshot? = nil
    @State private var hasMoreResults = false
    
    @FocusState private var searchFocused: Bool   // 🔹 Control del foco
    
    // 🔹 Devolvemos el Chat resuelto al padre (sin navegar aquí)
    var onChatResolved: ((Chat) -> Void)?
    
    var body: some View {
        VStack(spacing: 0) {
            // 🔎 Campo de búsqueda con foco inicial
            HStack {
                TextField("Buscar usuario…", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.done)           // muestra el botón "Cerrar/OK" en el teclado
                        .onSubmit {
                            searchFocused = false     // cierra el teclado al pulsar "Done"
                        }
                    .padding(12)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)
                    .focused($searchFocused) // 👈 vinculado al foco
            }
            .padding()
            
            // 📋 Resultados debajo
            if loading {
                ProgressView("Buscando…")
                    .frame(maxHeight: .infinity, alignment: .center)
            } else if !searchText.isEmpty && results.isEmpty {
                Text("No se encontraron usuarios")
                    .foregroundColor(.secondary)
                    .frame(maxHeight: .infinity, alignment: .center)
            } else {
                List {
                    ForEach(results, id: \.uid) { user in
                        Button {
                            Task { await createOrOpenChat(with: user.uid, username: user.username) }
                        } label: {
                            HStack(spacing: 12) {
                                avatarView(for: user)
                                Text(user.username)
                                    .foregroundColor(.primary)
                            }
                            .padding(.vertical, 6)
                        }
                    }
                    
                    if hasMoreResults {
                        Button {
                            Task { await searchUsers(reset: false) }
                        } label: {
                            HStack {
                                Spacer()
                                Text("Cargar más…")
                                    .foregroundColor(.blue)
                                    .padding(.vertical, 8)
                                Spacer()
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .onChange(of: searchText) { _ in
            applyFilter()
        }
        .navigationTitle("Nuevo chat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Foco + primera carga
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                searchFocused = true
            }
            Task { await searchUsers(reset: true) }
        }
    }
    
    // MARK: - Firestore: paginar SIEMPRE y filtrar en memoria
    private func searchUsers(reset: Bool) async {
        if reset {
            await MainActor.run {
                allUsers = []
                results = []
                lastDocument = nil
                hasMoreResults = false
            }
        }

        loading = true
        defer { loading = false }

        let db = Firestore.firestore()
        do {
            var baseQuery: Query = db.collection("users")
                .order(by: "usernameLower")
                .limit(to: 50) // un poco más grande para que el filtro “contiene” sea útil

            if let lastDoc = lastDocument {
                baseQuery = baseQuery.start(afterDocument: lastDoc)
            }

            let snap = try await baseQuery.getDocuments()

            var batch: [(String, String, String?)] = []
            for doc in snap.documents {
                let data = doc.data()
                let uid = doc.documentID
                guard uid != Auth.auth().currentUser?.uid else { continue }
                let username = (data["username"] as? String) ?? ""
                // Admite varios nombres de campo para el avatar
                let avatarUrl =
                    (data["profileImageUrl"] as? String)
                    ?? (data["photoURL"] as? String)
                    ?? (data["avatarURL"] as? String)

                batch.append((uid, username, avatarUrl))
            }

            await MainActor.run {
                if reset {
                    allUsers = batch
                } else {
                    allUsers.append(contentsOf: batch)
                }
                lastDocument = snap.documents.last
                hasMoreResults = snap.documents.count == 50
                applyFilter()
            }
        } catch {
            print("❌ Error buscando usuarios:", error.localizedDescription)
        }
    }
    
    // Normaliza: minúsculas, sin tildes, sin emojis/símbolos → solo alfanumérico
    private func norm(_ s: String) -> String {
        let lowered = s.lowercased()
        let folded = lowered.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                                     locale: .current)
        let compat = (folded as NSString).precomposedStringWithCompatibilityMapping
        let scalars = compat.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }

    private func applyFilter() {
        let q = norm(searchText)
        if q.isEmpty {
            results = allUsers
        } else {
            results = allUsers.filter { norm($0.username).contains(q) }
        }
    }


    
    // MARK: - Lógica de chat
    private func createOrOpenChat(with otherId: String, username: String) async {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        
        let participants = [myUid, otherId].sorted()
        let chatId = participants.joined(separator: "_")
        let ref = db.collection("chats").document(chatId)
        
        do {
            let snap = try await ref.getDocument()
            if snap.exists {
                let data = snap.data() ?? [:]
                let lastMessage = data["lastMessage"] as? String
                let ts = data["updatedAt"] as? Timestamp
                let updatedAt = ts?.dateValue()
                let lastSenderId = data["lastSenderId"] as? String
                
                var lastReadDates: [String: Date] = [:]
                if let lastReadMap = data["lastRead"] as? [String: Any] {
                    for (k, v) in lastReadMap {
                        if let t = v as? Timestamp { lastReadDates[k] = t.dateValue() }
                    }
                }
                
                let chat = Chat(
                    id: chatId,
                    participants: participants,
                    lastMessage: lastMessage,
                    updatedAt: updatedAt,
                    displayName: username,
                    lastRead: lastReadDates,
                    lastSenderId: lastSenderId
                )
                await MainActor.run { self.onChatResolved?(chat) }
            } else {
                try await ref.setData([
                    "participants": participants,
                    "lastMessage": "",
                    "updatedAt": FieldValue.serverTimestamp(),
                    "lastSenderId": NSNull(),
                    "lastRead": [
                        myUid: FieldValue.serverTimestamp(),
                        otherId: FieldValue.serverTimestamp()
                    ]
                ], merge: false)
                
                let chat = Chat(
                    id: chatId,
                    participants: participants,
                    lastMessage: nil,
                    updatedAt: Date(),
                    displayName: username,
                    lastRead: [:],
                    lastSenderId: nil
                )
                await MainActor.run { self.onChatResolved?(chat) }
            }
        } catch {
            print("❌ Error creando/abriendo chat:", error.localizedDescription)
        }
    }
    
    // MARK: - Avatar (cache estable para cero parpadeo)
    private func avatarView(for user: (uid: String, username: String, avatarUrl: String?)) -> some View {
        if let urlStr = user.avatarUrl {
            return AnyView(
                CachedAvatarImageView(
                    urlString: urlStr,
                    initials: user.username,
                    size: 44,
                    stableKey: "user:\(user.uid)"
                )
                .overlay(avatarBorder)
            )
        } else {
            return AnyView(
                placeholderAvatar(initials: user.username)
                    .overlay(avatarBorder)
            )
        }
    }

    
    private func placeholderAvatar(initials: String?) -> some View {
        let letters = String((initials ?? "U").prefix(2)).uppercased()
        return ZStack {
            Circle().fill(Color.blue.opacity(0.2))
            Text(letters)
                .font(.headline.bold())
                .foregroundColor(.blue)
        }
        .frame(width: 44, height: 44)
    }
    
    private var avatarBorder: some View {
        ZStack {
            Circle().stroke(Color.white, lineWidth: 3)
            Circle().stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.0, green: 0.85, blue: 0.9),
                        Color(red: 0.2, green: 0.5, blue: 1.0)
                    ]),
                    center: .center
                ),
                lineWidth: 2
            )
            .padding(-1)
        }
    }
}
