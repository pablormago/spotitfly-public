//
//  AdminAPI.swift
//  Spots
//

import Foundation
import FirebaseFunctions

enum ModerationKind: String {
    case spot
    case comment
}

struct AdminAPI {
    private static var functions = Functions.functions(region: "europe-west1")

    static func setSpotState(spotId: String, state: String, reason: String? = nil) async throws {
        let data: [String: Any] = [
            "kind": "spot",
            "spotId": spotId,
            "state": state,            // "public" | "review" | "hidden"
            "reason": reason ?? "manual"
        ]
        _ = try await functions.httpsCallable("adminModerate").call(data)
    }

    static func setCommentState(spotId: String, commentId: String, status: String, reason: String? = nil) async throws {
        let data: [String: Any] = [
            "kind": "comment",
            "spotId": spotId,
            "commentId": commentId,
            "status": status,         // "visible" | "hidden" | "deleted"
            "reason": reason ?? "manual"
        ]
        _ = try await functions.httpsCallable("adminModerate").call(data)
    }

    // Enviar como Soporte (escribe senderId = SUPPORT_BOT_ID en Firestore)
    static func sendSupportAsBot(chatId: String, text: String) async throws {
        let payload: [String: Any] = [
            "chatId": chatId,
            "text": text
        ]
        _ = try await functions.httpsCallable("sendSupportAsBot").call(payload)
        
    }
    // BEGIN INSERT — AdminAPI.unblockUserAsAdmin
    static func unblockUserAsAdmin(userId: String) async throws {
        let payload: [String: Any] = [
            "userId": userId
        ]
        _ = try await functions.httpsCallable("adminUnblockUser").call(payload)
    }
    // END INSERT — AdminAPI.unblockUserAsAdmin

}
