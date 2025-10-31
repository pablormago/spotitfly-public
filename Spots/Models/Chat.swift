//
//  Chat.swift
//  Spots
//

import Foundation

struct Chat: Identifiable {
    let id: String
    let participants: [String]
    let lastMessage: String?
    let updatedAt: Date?
    var displayName: String?

    // Estado de lectura por usuario (uid -> fecha)
    var lastRead: [String: Date]?

    // Quién envió el último mensaje (para no marcar no leído al emisor)
    var lastSenderId: String?

    // Nuevo: visibilidad por usuario (uid -> Bool)
    var isHidden: [String: Bool]?
    var hiddenFor: [String]?
    // END INSERT
}

extension Chat {
    /// True si hay mensajes no leídos para el usuario dado.
    /// Si el último mensaje lo envié yo, nunca se considera no leído.
    func isUnread(for uid: String?) -> Bool {
        guard let uid, let updatedAt else { return false }
        if lastSenderId == uid { return false }
        let readDate = lastRead?[uid]
        return readDate == nil || updatedAt > (readDate!)
    }

    /// True si este chat está oculto para un usuario concreto.
    /// True si este chat está oculto para un usuario concreto.
    func hidden(for uid: String?) -> Bool {
        guard let uid else { return false }
        if isHidden?[uid] == true { return true }
        if hiddenFor?.contains(uid) == true { return true } // fallback legacy
        return false
    }

}
