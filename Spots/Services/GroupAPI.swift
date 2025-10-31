//
//  CreateGroupParams.swift
//  Spots
//
//  Created by Pablo Jimenez on 24/10/25.
//


import Foundation
import FirebaseFunctions
import FirebaseFirestore

struct CreateGroupParams: Codable {
    var name: String
    var memberIds: [String]
    var photoURL: String?
}

final class GroupAPI {
    static let shared = GroupAPI()
    private init() {}

    private var functions = Functions.functions(region: "europe-west1")
    private var db = Firestore.firestore()

    // Crea el chat con participants = owner + miembros; NO sube foto todavía
    func createGroup(name: String, memberIds: [String]) async throws -> String {
        let data: [String: Any] = [
            "name": name,
            "memberIds": memberIds
        ]
        let result = try await functions.httpsCallable("createGroup").call(data)
        guard let dict = result.data as? [String: Any],
              let chatId = dict["chatId"] as? String else {
            throw NSError(domain: "GroupAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Respuesta inválida"])
        }
        return chatId
    }

    func addMembers(chatId: String, memberIds: [String]) async throws {
        let data: [String: Any] = ["chatId": chatId, "memberIds": memberIds]
        _ = try await functions.httpsCallable("addMembers").call(data)
    }

    func removeMember(chatId: String, uid: String) async throws {
        let data: [String: Any] = ["chatId": chatId, "uid": uid]
        _ = try await functions.httpsCallable("removeMember").call(data)
    }

    func leaveGroup(chatId: String) async throws {
        let data: [String: Any] = ["chatId": chatId]
        _ = try await functions.httpsCallable("leaveGroup").call(data)
    }

    func renameGroup(chatId: String, name: String) async throws {
        let data: [String: Any] = ["chatId": chatId, "name": name]
        _ = try await functions.httpsCallable("renameGroup").call(data)
    }

    func setGroupPhoto(chatId: String, photoURL: String) async throws {
        // ✅ Arreglo defensivo: si viene con '?bust=' y ya hay alt=media&token=..., conviértelo a '&bust='
        let fixed: String = {
            if photoURL.contains("alt=media"), photoURL.contains("?bust=") {
                return photoURL.replacingOccurrences(of: "?bust=", with: "&bust=")
            } else {
                return photoURL
            }
        }()

        try await db.collection("chats").document(chatId).setData([
            "photoURL": fixed,
            "updatedAt": FieldValue.serverTimestamp()
        ], merge: true)
    }
    
    // MARK: - Invitaciones

    public func createInviteLink(chatId: String) async throws -> String {
        let fn = Functions.functions(region: "europe-west1").httpsCallable("createInviteLink")
        let res = try await fn.call([ "chatId": chatId ])
        if let dict = res.data as? [String: Any], let url = dict["url"] as? String {
            return url // p.ej. "spots://invite/ABCD1234"
        }
        throw NSError(domain: "GroupAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Respuesta inválida"])
    }

    public func revokeInviteLink(chatId: String) async throws {
        let fn = Functions.functions(region: "europe-west1").httpsCallable("revokeInviteLink")
        _ = try await fn.call([ "chatId": chatId ])
    }

    public func joinByInvite(code: String) async throws -> String {
        let fn = Functions.functions(region: "europe-west1").httpsCallable("joinByInvite")
        let res = try await fn.call([ "code": code ])
        if let dict = res.data as? [String: Any], let chatId = dict["chatId"] as? String {
            return chatId
        }
        throw NSError(domain: "GroupAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Respuesta inválida"])
    }

    // MARK: - Añadir miembros respetando límite (cliente + server)
    // Reemplaza el uso antiguo por esta función
    public func addMembersRespectingLimit(chatId: String, userIds: [String]) async throws {
        // Pre-chequeo cliente: recorta si es necesario (defensivo; el límite real lo aplica el server)
        let chatSnap = try await Firestore.firestore().collection("chats").document(chatId).getDocument()
        let data = chatSnap.data() ?? [:]
        let current = (data["participants"] as? [String]) ?? []
        let limit = (data["maxMembers"] as? Int) ?? 64
        let unique = userIds.filter { !current.contains($0) }
        let allowed = max(0, limit - current.count)
        let finalList = Array(unique.prefix(allowed))
        guard !finalList.isEmpty else { return }

        let fn = Functions.functions(region: "europe-west1").httpsCallable("addMembersWithLimit")
        _ = try await fn.call([ "chatId": chatId, "userIds": finalList ])
    }



}
