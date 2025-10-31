//
//  ChatViewModel.swift
//  Spots
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage   // 👈 Necesario para subir archivos
import UIKit

@MainActor
final class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var isSending = false
    @Published var replyTarget: Message? = nil
    @Published var editTarget: Message? = nil
    
    let chatId: String
    private let db = Firestore.firestore()
    private let SUPPORT_BOT_ID = "26CSxWS7R7eZlrvXUV1qJFyL7Oc2"
    private let storage = Storage.storage()
    private var listener: ListenerRegistration?
    
    init(chatId: String) {
        self.chatId = chatId
    }
    
    func start() {
        guard listener == nil else { return }
        
        listener = db.collection("chats").document(chatId)
            .collection("messages")
            .order(by: "createdAt", descending: false)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self, let snap else { return }
                
                snap.documentChanges.forEach { change in
                    if let msg = Message(
                        id: change.document.documentID,
                        chatId: self.chatId,
                        data: change.document.data()
                    ) {
                        switch change.type {
                        case .added:
                            if !self.messages.contains(where: { $0.id == msg.id }) {
                                self.messages.append(msg)
                                self.messages.sort { $0.createdAt < $1.createdAt }
                            }
                        case .modified:
                            if let idx = self.messages.firstIndex(where: { $0.id == msg.id }) {
                                // Sustituimos sin reordenar para evitar saltos
                                self.messages[idx] = msg
                            }
                        case .removed:
                            self.messages.removeAll { $0.id == msg.id }
                        }
                    }
                }
            }
    }
    
    func stop() {
        listener?.remove()
        listener = nil
    }
    
    // 🧩 Quote helpers
    func setReply(to message: Message) { self.replyTarget = message }
    func clearReply() { self.replyTarget = nil }
    // ✏️ Edit helpers
    func startEdit(_ message: Message) {
        guard let uid = Auth.auth().currentUser?.uid, message.senderId == uid else { return }
        self.editTarget = message
        self.replyTarget = nil // no se puede responder mientras editas
    }
    func cancelEdit() { self.editTarget = nil }
    
    // ✏️ Actualiza el texto de un mensaje propio y marca editedAt
    func updateMessage(text newText: String, mentions: [String] = []) async {

        guard let target = self.editTarget,
              let uid = Auth.auth().currentUser?.uid,
              target.senderId == uid else { return }
        
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let ref = db.collection("chats").document(chatId)
            .collection("messages").document(target.id)
        
        do {
            var update: [String: Any] = [
                "text": trimmed,
                "editedAt": FieldValue.serverTimestamp()
            ]
            if !mentions.isEmpty {
                update["mentions"] = mentions
            }
            try await ref.updateData(update)

            await MainActor.run { self.editTarget = nil }
            // Asegura consistencia del agregado (por si el edit afecta al último mensaje)
            await rebuildChatLastMessage()
        } catch {
            print("❌ Error editando mensaje:", error.localizedDescription)
        }
    }

    
    func send(text: String, mentions: [String] = []) async {

        guard let uid = Auth.auth().currentUser?.uid else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        isSending = true
        defer { isSending = false }
        
        let msgRef = db.collection("chats").document(chatId).collection("messages").document()
        let now = Date()
        
        var data: [String: Any] = [
            "id": msgRef.documentID,
            "senderId": uid,
            "text": trimmed,
            "createdAtClient": Timestamp(date: now),   // fecha estable en cliente
            "createdAt": FieldValue.serverTimestamp()  // fecha oficial servidor
        ]
        
        // Solo si hay menciones
        if !mentions.isEmpty {
            data["mentions"] = mentions
        }

        
        if let rid = self.replyTarget?.id {
            data["replyToMessageId"] = rid
        }
        
        do {
            try await msgRef.setData(data)
            await MainActor.run { self.replyTarget = nil } // limpia el quote tras enviar
            
            try await db.collection("chats").document(chatId).setData([
                "lastMessage": trimmed,
                "updatedAt": FieldValue.serverTimestamp(),
                "lastSenderId": uid
            ], merge: true)
        } catch {
            print("❌ Error enviando mensaje:", error.localizedDescription)
        }
    }
    
    func markAsRead(for uid: String) async {
        guard !uid.isEmpty else { return }
        do {
            // 1) Marca en el documento del chat
            try await db.collection("chats").document(chatId).setData([
                "lastRead": [uid: FieldValue.serverTimestamp()]
            ], merge: true)
            
            // 2) Dispara el trigger del servidor -> badge silencioso
            try await db.collection("users").document(uid)
                .collection("chatsReads").document(chatId)
                .setData(["lastReadAt": FieldValue.serverTimestamp()], merge: true)
        } catch {
            print("❌ Error marcando como leído:", error.localizedDescription)
        }
    }
    
    
    
    func markMessagesAsReadLocally(for uid: String) async {
        guard !uid.isEmpty else { return }
        for i in 0..<messages.count {
            if !messages[i].readBy.contains(uid) {
                messages[i].readBy.append(uid)
            }
        }
    }
    
    // 🆕 Borrar mensaje
    func deleteMessage(_ message: Message) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        guard message.senderId == uid else {
            print("❌ No puedes borrar mensajes de otro usuario")
            return
        }
        
        do {
            try await db.collection("chats")
                .document(chatId)
                .collection("messages")
                .document(message.id)
                .delete()
            print("🗑️ Mensaje borrado: \(message.id)")
            // Recalcular el agregado del chat
            await rebuildChatLastMessage()
        } catch {
            print("❌ Error borrando mensaje:", error.localizedDescription)
        }
    }
    
    // Etiqueta amigable para archivos en lastMessage (para la Home)
    private func labelForPickedFile(_ picked: PickedFile) -> String {
        let name = picked.fileName.lowercased()
        let mt = (picked.mimeType ?? "").lowercased()
        
        let isImage = mt.hasPrefix("image/") || name.hasSuffix(".jpg") || name.hasSuffix(".jpeg") || name.hasSuffix(".png") || name.hasSuffix(".gif") || name.hasSuffix(".heic")
        if isImage { return "📷 Foto" }
        
        let isVideo = mt.hasPrefix("video/") || name.hasSuffix(".mp4") || name.hasSuffix(".mov") || name.hasSuffix(".avi") || name.hasSuffix(".mkv")
        if isVideo { return "🎬 Vídeo" }
        
        let isAudio = mt.hasPrefix("audio/") || name.hasSuffix(".mp3") || name.hasSuffix(".m4a") || name.hasSuffix(".wav")
        if isAudio { return "🎵 Audio" }
        
        // Documentos u otros
        return "📎 \(picked.fileName)"
    }
    
    // 🆕 Enviar archivo
    func sendFile(picked: PickedFile) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let msgRef = db.collection("chats").document(chatId).collection("messages").document()
        let now = Date()
        
        // 🧩 Capturamos el reply actual (por si el usuario lo cierra durante el upload)
        let replyId = self.replyTarget?.id
        
        // Mensaje local con progreso 0
        let placeholder = Message(
            id: msgRef.documentID,
            chatId: chatId,
            senderId: uid,
            text: "",
            createdAt: now,
            readBy: [],
            replyToMessageId: replyId,
            fileUrl: nil,
            fileName: picked.fileName,
            fileSize: picked.fileSize,
            fileType: picked.mimeType,
            uploadProgress: 0.0
        )
        await MainActor.run {
            self.messages.append(placeholder)
        }
        
        // Subida a Firebase con progreso
        let storageRef = storage.reference()
            .child("chats/\(chatId)/\(uid)/\(picked.fileName)")
        
        let uploadTask = storageRef.putData(picked.data ?? Data(), metadata: nil)
        
        uploadTask.observe(.progress) { snap in
            let pct = Double(snap.progress?.fractionCompleted ?? 0)
            Task { @MainActor in
                if let idx = self.messages.firstIndex(where: { $0.id == placeholder.id }) {
                    self.messages[idx].uploadProgress = pct
                }
            }
        }
        
        uploadTask.observe(.success) { _ in
            // ✅ Pide el URL de descarga al terminar la subida
            storageRef.downloadURL { url, _ in
                guard let url else { return }
                
                var data: [String: Any] = [
                    "id": msgRef.documentID,
                    "senderId": uid,
                    "text": "",
                    "fileUrl": url.absoluteString,
                    "fileName": picked.fileName,
                    "fileSize": picked.fileSize,
                    "fileType": picked.mimeType ?? "application/octet-stream",
                    "createdAtClient": Timestamp(date: now),
                    "createdAt": FieldValue.serverTimestamp()
                ]
                
                // Si tienes reply/quote activo, añádelo aquí (ignora si no usas reply)
                if let rid = self.replyTarget?.id {
                    data["replyToMessageId"] = rid
                }
                
                Task {
                    try? await msgRef.setData(data)
                    
                    // Limpia el estado de reply si procede
                    await MainActor.run { self.replyTarget = nil }
                    
                    // Guardamos label amigable en el agregado del chat (para Home)
                    let label = self.labelForPickedFile(picked)
                    try? await self.db.collection("chats").document(self.chatId).setData([
                        "lastMessage": label,
                        "updatedAt": FieldValue.serverTimestamp(),
                        "lastSenderId": uid
                    ], merge: true)
                }
            }
        }
        
        uploadTask.observe(.failure) { snap in
            print("❌ Error subiendo archivo:", snap.error?.localizedDescription ?? "")
        }
    }
    
    // 🟦 Enviar como soporte (bot) con UI optimista
    func sendSupport(text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        isSending = true
        let tempId = "pending-\(UUID().uuidString)"
        let placeholder = Message(
            id: tempId,
            chatId: self.chatId,
            senderId: SUPPORT_BOT_ID,
            text: trimmed,
            createdAt: Date(),
            readBy: [],
            fileUrl: nil,
            fileName: nil,
            fileSize: nil,
            fileType: nil,
            uploadProgress: nil
        )
        await MainActor.run {
            self.messages.append(placeholder)
            self.messages.sort { $0.createdAt < $1.createdAt }
        }
        
        do {
            try await AdminAPI.sendSupportAsBot(chatId: self.chatId, text: trimmed)
            await MainActor.run {
                if let idx = self.messages.firstIndex(where: { $0.id == tempId }) {
                    self.messages.remove(at: idx)
                }
            }
        } catch {
            await MainActor.run {
                if let idx = self.messages.firstIndex(where: { $0.id == tempId }) {
                    self.messages.remove(at: idx)
                }
            }
            print("❌ Error sendSupport:", error.localizedDescription)
        }
        
        isSending = false
    }
    
    // MARK: - Reconstrucción del agregado del chat (último mensaje) tras borrados / cambios
    
    private func labelForMessageData(_ data: [String: Any]) -> String {
        // Si es archivo, prioriza el tipo
        if let ft = (data["fileType"] as? String)?.lowercased(),
           (data["fileUrl"] as? String) != nil || (data["fileName"] as? String) != nil {
            if ft.hasPrefix("image/") { return "📷 Foto" }
            if ft.hasPrefix("video/") { return "🎬 Vídeo" }
            if ft.hasPrefix("audio/") { return "🎵 Audio" }
            let name = (data["fileName"] as? String) ?? "Archivo"
            return "📎 \(name)"
        }
        // Texto normal (si es link, la Home lo formatea con 🔗 host)
        let t = (data["text"] as? String) ?? ""
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func rebuildChatLastMessage() async {
        do {
            let snap = try await db.collection("chats").document(chatId)
                .collection("messages")
                .order(by: "createdAt", descending: true)
                .limit(to: 1)
                .getDocuments()
            
            if let doc = snap.documents.first {
                let data = doc.data()
                let label = labelForMessageData(data)
                let sender = (data["senderId"] as? String) ?? ""
                let createdAtTs = (data["createdAt"] as? Timestamp)
                
                var update: [String: Any] = [
                    "lastMessage": label,
                    "lastSenderId": sender
                ]
                if let createdAtTs { update["updatedAt"] = createdAtTs }  // ordena por fecha del último vivo
                else { update["updatedAt"] = FieldValue.serverTimestamp() }
                
                try await db.collection("chats").document(chatId).setData(update, merge: true)
            } else {
                // No quedan mensajes → limpia agregados básicos
                try await db.collection("chats").document(chatId).setData([
                    "lastMessage": FieldValue.delete(),
                    "lastSenderId": FieldValue.delete(),
                    "updatedAt": FieldValue.serverTimestamp()
                ], merge: true)
            }
        } catch {
            print("⚠️ rebuildChatLastMessage error:", error.localizedDescription)
        }
    }
}
