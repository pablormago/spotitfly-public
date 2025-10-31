//
//  SupportInboxVM.swift
//  Spots
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class SupportInboxVM: ObservableObject {
    @Published var chats: [Chat] = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private let SUPPORT_BOT_ID = "26CSxWS7R7eZlrvXUV1qJFyL7Oc2"

    func start() {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        listener?.remove()
        listener = db.collection("chats")
            .whereField("isSupport", isEqualTo: true)
            .whereField("participants", arrayContains: uid)
            .order(by: "updatedAt", descending: true)
            .addSnapshotListener { [weak self] snap, _ in
                guard let self else { return }
                let docs = snap?.documents ?? []
                Task { await self.processDocuments(docs, uid: uid) }
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    private func processDocuments(_ docs: [QueryDocumentSnapshot], uid: String) async {
        var result: [Chat] = []

        for d in docs {
            let data = d.data()
            let id = d.documentID
            let participants = data["participants"] as? [String] ?? []
            let lastMessage = data["lastMessage"] as? String
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
            let lastSenderId = data["lastSenderId"] as? String

            var lastReadDates: [String: Date] = [:]
            if let lastReadMap = data["lastRead"] as? [String: Any] {
                for (k, v) in lastReadMap {
                    if let t = v as? Timestamp { lastReadDates[k] = t.dateValue() }
                }
            }

            // En soporte (lado admin), el "otro" debe ser SIEMPRE el humano (ni yo, ni el bot)
            let otherUserId = participants.first { $0 != uid && $0 != SUPPORT_BOT_ID }

            var displayName: String? = "Soporte"
            if let other = otherUserId {
                if let cached = ChatsViewModel.shared.usernames[other] {
                    displayName = "Soporte con \(cached)"
                } else if let name = await UserService.shared.username(for: other) {
                    await MainActor.run { ChatsViewModel.shared.usernames[other] = name }
                    displayName = "Soporte con \(name)"
                } else {
                    displayName = "Soporte con \(other.prefix(6))"
                }
            }

            let chat = Chat(
                id: id,
                participants: participants,
                lastMessage: lastMessage,
                updatedAt: updatedAt,
                displayName: displayName,
                lastRead: lastReadDates,
                lastSenderId: lastSenderId
            )
            result.append(chat)
        }

        // Aseguramos orden por fecha descendente
        result.sort { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        self.chats = result
    }

    // MARK: - Unread helpers

    func hasUnread(_ chat: Chat, uid: String) -> Bool {
        let updated = chat.updatedAt ?? .distantPast
        let last = (chat.lastRead?[uid]) ?? .distantPast   // ← FIX: opcional
        let lastSender = chat.lastSenderId ?? ""
        // En soporte tratamos mensajes del bot como “propios” (no generan no leído)
        return updated > last && lastSender != uid && lastSender != SUPPORT_BOT_ID
    }

    /// Marca el chat como leído para el usuario actual (lastRead.<uid> = serverTimestamp)
    func markAsRead(chatId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("chats").document(chatId)
            .setData(["lastRead.\(uid)": FieldValue.serverTimestamp()], merge: true)
    }
}
