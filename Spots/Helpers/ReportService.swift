//
//  ReportService.swift
//  Spots
//

import Foundation
import FirebaseFirestore
import FirebaseAuth

enum ReportType: String {
    case comment
    case user        // ✅ usar para reportar usuario (desde chat)
    case spot        // reportar un Spot completo
    // Nota: mantenemos compatibilidad con "chat" a nivel de API via reportChat(), pero lo traducimos a "user"
}

struct ReportService {

    // MARK: - Público

    /// Reporte genérico (usa este si quieres pasar un motivo libre)
    /// IMPORTANTE: Sólo se admiten "user" | "spot" | "comment" por las reglas.
    static func report(
        type: ReportType,
        targetId: String,
        spotId: String? = nil,
        commentId: String? = nil,
        reason: String
    ) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("❌ ReportService: usuario no autenticado")
            return
        }

        let db = Firestore.firestore()

        var data: [String: Any] = [
            "type": type.rawValue,
            "reporterId": uid,
            "reason": reason,
            "createdAt": FieldValue.serverTimestamp()
        ]

        switch type {
        case .user:
            // rules: targetId obligatorio (uid del reportado)
            data["targetId"] = targetId

        case .spot:
            // rules: targetId obligatorio (spotId)
            data["targetId"] = targetId
            if let spotId { data["spotId"] = spotId } // opcional mantenerlo duplicado

        case .comment:
            // rules: spotId y commentId obligatorios; targetId NO es necesario (lo evitamos)
            if let spotId, let commentId {
                data["spotId"] = spotId
                data["commentId"] = commentId
            } else {
                print("❌ ReportService: faltan spotId/commentId para reportar comentario")
                return
            }
        }

        do {
            try await db.collection("reports").addDocument(data: data)
            print("✅ Reporte guardado (\(type.rawValue))")
        } catch {
            print("❌ Error al guardar reporte: \(error.localizedDescription)")
        }
    }

    /// Atajo para reportar comentario (cumple reglas: spotId + commentId)
    static func reportComment(
        commentId: String,
        spotId: String,
        reason: String
    ) async {
        await report(type: .comment, targetId: "", spotId: spotId, commentId: commentId, reason: reason)
    }

    /// Atajo directo para reportar usuario (desde chat u otro contexto)
    static func reportUser(
        otherUserId: String,
        reason: String
    ) async {
        await report(type: .user, targetId: otherUserId, spotId: nil, commentId: nil, reason: reason)
    }

    /// Compat: reportar "chat" → traduce a type:"user" resolviendo el otherUserId a partir del chatId.
    /// Úsalo si en la llamada sólo tienes chatId. Si puedes, prefiere reportUser(otherUserId:).
    static func reportChat(
        chatId: String,
        reason: String
    ) async {
        guard let uid = Auth.auth().currentUser?.uid else {
            print("❌ ReportService: usuario no autenticado")
            return
        }
        let db = Firestore.firestore()
        do {
            let doc = try await db.collection("chats").document(chatId).getDocument()
            guard let parts = doc.get("participants") as? [String], parts.count >= 2 else {
                print("❌ ReportService: chat sin participants")
                return
            }
            // other = el que no soy yo
            guard let other = parts.first(where: { $0 != uid }) else {
                print("❌ ReportService: no se pudo resolver otherUserId")
                return
            }
            await reportUser(otherUserId: other, reason: reason) // ✅ traduce a "user"
        } catch {
            print("❌ ReportService: error obteniendo chat \(chatId): \(error.localizedDescription)")
        }
    }

    /// Atajo para reportar un Spot completo
    static func reportSpot(
        spotId: String,
        reason: String
    ) async {
        await report(type: .spot, targetId: spotId, spotId: spotId, commentId: nil, reason: reason)
    }
}
