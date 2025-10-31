//
//  CommentReadService.swift
//  Spots
//
//  Created by Pablo Jimenez on 21/9/25.
//

import Foundation
import FirebaseFirestore

actor CommentReadService {
    static let shared = CommentReadService()
    private let db = Firestore.firestore()

    /// Marcar un spot como visto por el usuario (actualiza lastSeenAt)
    func markSeen(spotId: String, userId: String) async {
        let ref = db.collection("users").document(userId)
            .collection("spotReads").document(spotId)
        do {
            try await ref.setData([
                "lastSeenAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            print("❌ Error marcando spot \(spotId) como visto:", error.localizedDescription)
        }
    }

    /// Devuelve los IDs de spots con comentarios nuevos (para el owner)
    func fetchUnreadSpotIds(for userId: String, ownedSpots: [Spot]) async -> [String] {
        do {
            let readsSnap = try await db.collection("users").document(userId)
                .collection("spotReads").getDocuments()

            var lastSeen: [String: Date] = [:]
            for doc in readsSnap.documents {
                if let ts = doc.data()["lastSeenAt"] as? Timestamp {
                    lastSeen[doc.documentID] = ts.dateValue()
                }
            }

            let unread = ownedSpots.compactMap { spot -> String? in
                guard let lastCommentAt = spot.lastCommentAt else { return nil }
                let seen = lastSeen[spot.id]
                if seen == nil || lastCommentAt > seen! {
                    return spot.id
                }
                return nil
            }
            return unread
        } catch {
            print("❌ Error obteniendo unread spots:", error.localizedDescription)
            return []
        }
    }
}
