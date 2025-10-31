//
//  DebugMenuView.swift
//  Spots (solo en Debug)
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

#if DEBUG
struct DebugMenuView: View {
    @State private var logs: [String] = []

    // Contexto auto-detectado
    @State private var uid: String = ""
    @State private var sampleSpotId: String? = nil
    @State private var sampleSpotOwner: String? = nil
    @State private var foreignSpotId: String? = nil   // si encuentra uno que no sea tuyo
    @State private var realChatId: String? = nil

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("UID: \(uid.isEmpty ? "—" : uid)")
                            Text("Spot (para comentar): \(sampleSpotId ?? "—")")
                            Text("Spot ajeno (si hay): \(foreignSpotId ?? "—")")
                            Text("Chat real: \(realChatId ?? "—")")
                        }.font(.caption)
                        Spacer()
                        Button("Recargar IDs") { Task { await loadContext() } }
                            .buttonStyle(.borderedProminent)
                    }
                }

                Section("Firestore") {
                    Button("Spots – Crear spot") { Task { await testCreateSpot() } }

                    Button("Spots – Editar spot AJENO") {
                        Task { await testEditForeignSpot() }
                    }
                    .disabled(foreignSpotId == nil)

                    Button("Comments – Crear comentario (en sampleSpot)") {
                        Task { await testCreateComment() }
                    }
                    .disabled(sampleSpotId == nil)

                    Button("Comments – Borrar comentario AJENO (dummy id)") {
                        Task { await testDeleteForeignComment() }
                    }
                    .disabled(sampleSpotId == nil)

                    Button("Chats – Leer chat AJENO (id inventado)") {
                        Task { await testReadForeignChat() }
                    }

                    Button("Messages – Enviar en chat AJENO (id inventado)") {
                        Task { await testSendMessageForeign() }
                    }

                    Button("Reports – Leer reporte (debe fallar)") {
                        Task { await testReadReport() }
                    }
                }

                Section("Storage") {
                    Button("Perfil propio OK") { Task { await testUploadProfileImage(own: true) } }
                    Button("Perfil ajeno 🚫") { Task { await testUploadProfileImage(own: false) } }

                    Button("Chat propio OK (usa realChatId)") {
                        Task { await testUploadChatFile(allowed: true) }
                    }
                    .disabled(realChatId == nil)

                    Button("Chat ajeno 🚫 (id inventado)") {
                        Task { await testUploadChatFile(allowed: false) }
                    }
                    // En DebugMenuView, añade un botón temporal
                    Button("Test get chat directo") {
                        Task {
                            do {
                                let doc = try await Firestore.firestore()
                                    .collection("chats")
                                    .document(realChatId ?? "NO_CHAT")
                                    .getDocument()
                                log("✅ Firestore get chat OK: \(doc.exists)")
                            } catch {
                                log("❌ Firestore get chat DENEGADO: \(error.localizedDescription)")
                            }
                        }
                    }

                }

                Section("Logs") {
                    ForEach(logs.reversed(), id: \.self) { log in
                        Text(log).font(.caption2).textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Debug Rules")
            .task { await loadContext() }
        }
    }

    // MARK: - Context loader
    private func loadContext() async {
        logs.removeAll()
        let db = Firestore.firestore()
        uid = Auth.auth().currentUser?.uid ?? ""

        // 1) Coger un spot cualquiera (para comentar) y, si es posible, también uno AJENO
        do {
            let snap = try await db.collection("spots").limit(to: 15).getDocuments()
            var anySpot: (id: String, owner: String)? = nil
            var foreign: String? = nil
            for d in snap.documents {
                let data = d.data()
                let owner = (data["createdBy"] as? String) ?? ""
                if anySpot == nil {
                    anySpot = (d.documentID, owner)
                }
                if owner != uid, foreign == nil {
                    foreign = d.documentID
                }
            }
            sampleSpotId = anySpot?.id
            sampleSpotOwner = anySpot?.owner
            foreignSpotId = foreign
            log("ℹ️ sampleSpotId=\(sampleSpotId ?? "nil") owner=\(sampleSpotOwner ?? "nil"), foreignSpotId=\(foreignSpotId ?? "nil")")
        } catch {
            log("⚠️ No pude listar spots: \(error.localizedDescription)")
        }

        // 2) Coger un chat real en el que participas
        if !uid.isEmpty {
            do {
                let snap = try await db.collection("chats")
                    .whereField("participants", arrayContains: uid)
                    .order(by: "updatedAt", descending: true)
                    .limit(to: 1)
                    .getDocuments()
                realChatId = snap.documents.first?.documentID
                log("ℹ️ realChatId=\(realChatId ?? "nil")")
            } catch {
                log("⚠️ No pude listar tus chats: \(error.localizedDescription)")
            }
        }
        if sampleSpotId == nil {
            log("👉 Abre/crea un Spot y vuelve a pulsar “Recargar IDs”.")
        }
        if realChatId == nil {
            log("👉 Abre un chat cualquiera y vuelve a pulsar “Recargar IDs”.")
        }
    }

    // MARK: - Helpers
    private func log(_ msg: String) {
        Task { @MainActor in
            logs.append(msg)
            print(msg)
        }
    }

    // MARK: - Firestore Tests
    private func testCreateSpot() async {
        do {
            guard !uid.isEmpty else { log("⚠️ No hay usuario logado"); return }
            let id = UUID().uuidString
            try await Firestore.firestore().collection("spots").document(id).setData([
                "id": id,
                "name": "Test Spot",
                "description": "Spot de prueba",
                "latitude": 0.0,
                "longitude": 0.0,
                "createdBy": uid,
                "createdAt": Timestamp(date: Date())
            ])
            log("✅ Crear spot permitido")
        } catch {
            log("❌ Crear spot denegado: \(error.localizedDescription)")
        }
    }

    private func testEditForeignSpot() async {
        guard let foreignId = foreignSpotId else {
            log("ℹ️ No hay spot ajeno detectado para probar"); return
        }
        do {
            try await Firestore.firestore().collection("spots").document(foreignId).updateData(["name": "Hack"])
            log("❌ Editar spot AJENO PERMITIDO (error)")
        } catch {
            log("✅ Editar spot ajeno bloqueado")
        }
    }

    private func testCreateComment() async {
        guard let spotId = sampleSpotId else { log("ℹ️ Sin sampleSpotId"); return }
        do {
            let id = UUID().uuidString
            try await Firestore.firestore().collection("spots").document(spotId).collection("comments").document(id).setData([
                "id": id,
                "text": "Comentario prueba",
                "authorId": uid,
                "authorName": "Tester",
                "createdAt": FieldValue.serverTimestamp()
            ])
            log("✅ Crear comentario permitido")
        } catch {
            log("❌ Crear comentario denegado: \(error.localizedDescription)")
        }
    }

    private func testDeleteForeignComment() async {
        guard let spotId = sampleSpotId else { log("ℹ️ Sin sampleSpotId"); return }
        // Intentamos borrar un id inventado: en reglas, si no eres autor, debe denegar.
        do {
            try await Firestore.firestore().collection("spots").document(spotId)
                .collection("comments").document("FOREIGN_COMMENT_ID_XYZ").delete()
            log("❌ Borrar comentario AJENO PERMITIDO (error)")
        } catch {
            log("✅ Borrar comentario ajeno bloqueado")
        }
    }

    private func testReadForeignChat() async {
        do {
            _ = try await Firestore.firestore().collection("chats").document("FOREIGN_CHAT_ID_XYZ").getDocument()
            log("❌ Leer chat ajeno PERMITIDO (error)")
        } catch {
            log("✅ Leer chat ajeno bloqueado")
        }
    }

    private func testSendMessageForeign() async {
        do {
            let msgId = UUID().uuidString
            try await Firestore.firestore().collection("chats").document("FOREIGN_CHAT_ID_XYZ")
                .collection("messages").document(msgId).setData([
                    "id": msgId,
                    "senderId": uid,
                    "text": "Hack",
                    "createdAt": FieldValue.serverTimestamp()
                ])
            log("❌ Enviar mensaje en chat ajeno PERMITIDO (error)")
        } catch {
            log("✅ Enviar mensaje en chat ajeno bloqueado")
        }
    }

    private func testReadReport() async {
        do {
            _ = try await Firestore.firestore().collection("reports").document("ANY_REPORT").getDocument()
            log("❌ Leer reporte PERMITIDO (error)")
        } catch {
            log("✅ Leer reporte bloqueado")
        }
    }

    // MARK: - Storage Tests
    private func testUploadProfileImage(own: Bool) async {
        do {
            let targetUid = own ? uid : "OTHER_UID_123"
            let data = "Hello".data(using: .utf8)!
            try await Storage.storage().reference()
                .child("profileImages/\(targetUid)/test.txt")
                .putDataAsync(data)
            if own { log("✅ Subir perfil propio permitido") }
            else   { log("❌ Subir perfil AJENO PERMITIDO (error)") }
        } catch {
            if own { log("❌ Subir perfil propio bloqueado: \(error.localizedDescription)") }
            else   { log("✅ Subir perfil ajeno bloqueado") }
        }
    }

    private func testUploadChatFile(allowed: Bool) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            log("⚠️ No hay usuario logado"); return
        }
        let chatId = allowed ? (realChatId ?? "NO_CHAT") : "FOREIGN_CHAT_ID_XYZ"
        let path = "chats/\(chatId)/\(uid)/test.txt"
        let ref = Storage.storage().reference().child(path)
        let data = "Hola desde DebugView".data(using: .utf8)!

        log("📂 Intentando subir a: \(path)")

        do {
            _ = try await ref.putDataAsync(data)
            if allowed { log("✅ Subir a chat propio permitido") }
            else       { log("❌ Subir a chat ajeno PERMITIDO (error)") }
        } catch {
            if allowed { log("❌ Subir a chat propio bloqueado: \(error.localizedDescription)") }
            else       { log("✅ Subir a chat ajeno bloqueado") }
        }
    }

}
#endif
