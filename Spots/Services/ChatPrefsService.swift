//
//  ChatPrefsService.swift
//  Spots
//
//  Created by Pablo Jimenez on 24/10/25.
//


import Foundation
import FirebaseAuth
import FirebaseFirestore

final class ChatPrefsService {
    static let shared = ChatPrefsService()
    private init() {}

    private var db: Firestore { Firestore.firestore() }
    private var uid: String? { Auth.auth().currentUser?.uid }

    /// Guarda mute por chat en users/{uid}/meta/chatPrefs/{chatId} { mute: Bool }
    func setMute(chatId: String, mute: Bool) async throws {
        guard let uid = uid else { return }
        try await db.collection("users").document(uid)
            .collection("meta").document("chatPrefs")
            .collection("prefs").document(chatId)
            .setData(["mute": mute], merge: true)
    }

    /// Lee mute por chat (default = false)
    func getMute(chatId: String) async -> Bool {
        guard let uid = uid else { return false }
        do {
            let snap = try await db.collection("users").document(uid)
                .collection("meta").document("chatPrefs")
                .collection("prefs").document(chatId)
                .getDocument()
            return (snap.data()?["mute"] as? Bool) ?? false
        } catch { return false }
    }
}
