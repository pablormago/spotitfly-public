//
//  ChatsHomeBadgeViewModel.swift
//  Spots
//
//  Created by Pablo Jimenez on 20/9/25.
//


//
//  ChatsHomeBadgeViewModel.swift
//  Spots
//
//  Created by Pablo Jimenez on 23/9/25.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
final class ChatsHomeBadgeViewModel: ObservableObject {
    @Published var badgeCount: Int = 0

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    deinit {
        listener?.remove()
    }

    func startListening(userId: String) {
        listener?.remove()

        listener = db.collection("chats")
            .whereField("participants", arrayContains: userId)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }
                if let err {
                    print("⚠️ Chats badge listener error:", err)
                    return
                }
                guard let docs = snap?.documents else {
                    self.badgeCount = 0
                    return
                }

                var unread = 0
                for doc in docs {
                    let data = doc.data()
                    let lastSenderId = data["lastSenderId"] as? String
                    let ts = data["updatedAt"] as? Timestamp
                    let updatedAt = ts?.dateValue()

                    var lastRead: [String: Date] = [:]
                    if let map = data["lastRead"] as? [String: Any] {
                        for (k, v) in map {
                            if let t = v as? Timestamp {
                                lastRead[k] = t.dateValue()
                            }
                        }
                    }

                    // Si no hay fecha de actualización, no cuenta
                    guard let updatedAt else { continue }

                    // Si yo envié el último mensaje, no cuenta como no leído
                    if lastSenderId == userId { continue }

                    // Si no hay registro de lectura o es anterior al último mensaje => no leído
                    let readDate = lastRead[userId]
                    if readDate == nil || readDate! < updatedAt {
                        unread += 1
                    }
                }

                Task { @MainActor in
                    self.badgeCount = unread
                }
            }
    }
}
