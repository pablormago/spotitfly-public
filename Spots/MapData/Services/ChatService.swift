//
//  ChatService.swift
//  Spots
//
//  Created by Pablo Jimenez on 17/9/25.
//


//
//  ChatService.swift
//  Spots
//
//  Created by Pablo Jimenez on 17/9/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

struct ChatService {
    private static let db = Firestore.firestore()

    /// Busca o crea un chat entre el usuario actual y otro
    static func getOrCreateChat(with otherUserId: String, firstMessage: String? = nil) async throws -> String {
        guard let currentUid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "ChatService", code: 401, userInfo: [NSLocalizedDescriptionKey: "Usuario no autenticado"])
        }

        // 1. Buscar si ya existe un chat con estos dos participantes
        let snapshot = try await db.collection("chats")
            .whereField("participants", arrayContains: currentUid)
            .getDocuments()

        for doc in snapshot.documents {
            let participants = doc["participants"] as? [String] ?? []
            if participants.contains(otherUserId) && participants.count == 2 {
                return doc.documentID
            }
        }

        // 2. Si no existe, crear chat
        let newRef = db.collection("chats").document()
        var data: [String: Any] = [
            "participants": [currentUid, otherUserId],
            "updatedAt": FieldValue.serverTimestamp()
        ]
        if let firstMessage, !firstMessage.isEmpty {
            data["lastMessage"] = firstMessage
        }
        try await newRef.setData(data)

        return newRef.documentID
    }

    /// Envía un mensaje a un usuario (crea chat si no existe)
    static func sendMessage(to otherUserId: String, text: String) async throws {
        guard let currentUid = Auth.auth().currentUser?.uid else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // 1. Obtener o crear chat
        let chatId = try await getOrCreateChat(with: otherUserId, firstMessage: trimmed)

        // 2. Crear mensaje en subcolección
        let msgRef = db.collection("chats").document(chatId).collection("messages").document()
        try await msgRef.setData([
            "id": msgRef.documentID,
            "senderId": currentUid,
            "text": trimmed,
            "createdAt": FieldValue.serverTimestamp()
        ])

        // 3. Actualizar chat con último mensaje
        try await db.collection("chats").document(chatId).updateData([
            "lastMessage": trimmed,
            "updatedAt": FieldValue.serverTimestamp()
        ])
    }
}
