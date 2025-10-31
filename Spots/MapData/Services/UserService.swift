//
//  UserService.swift
//  Spots
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import UIKit

final class UserService {
    static let shared = UserService()
    private init() {}

    private let db = Firestore.firestore()

    // MARK: - Datos básicos
    func getUsername(for uid: String) async -> String? {
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            return doc["username"] as? String
        } catch {
            print("❌ Error getUsername:", error)
            return nil
        }
    }

    func getProfileImageUrl(for uid: String) async -> String? {
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            return doc["profileImageUrl"] as? String
        } catch {
            print("❌ Error getProfileImageUrl:", error)
            return nil
        }
    }

    // 🔹 Wrappers para compatibilidad con ChatsViewModel / SpotsViewModel
    func username(for uid: String) async -> String? {
        return await getUsername(for: uid)
    }

    func profileImageUrl(for uid: String) async -> String? {
        return await getProfileImageUrl(for: uid)
    }

    // MARK: - Actualizar nombre
    func updateUsername(_ username: String, for uid: String) async throws {
        try await db.collection("users").document(uid).updateData([
            "username": username,
            "usernameLower": username.lowercased()
        ])
    }

    func updateUsername(_ username: String, session: UserSession) async {
        guard let uid = session.uid else { return }
        do {
            try await updateUsername(username, for: uid)
            await MainActor.run {
                session.username = username
            }
        } catch {
            print("❌ Error al actualizar username:", error)
        }
    }

    // MARK: - Actualizar imagen de perfil
    func updateProfileImage(_ image: UIImage, for uid: String) async throws -> (String, String) {
        guard let data = ImageCompressor.avatarData(from: image) else {
            throw NSError(domain: "ImageCompressor", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "No se pudo comprimir la imagen"])
        }

        let ref = Storage.storage().reference().child("profileImages/\(uid)/avatar.jpg")
        _ = try await ref.putDataAsync(data)
        let url = try await ref.downloadURL()
        let newBustToken = UUID().uuidString

        try await db.collection("users").document(uid).updateData([
            "profileImageUrl": url.absoluteString,
            "avatarBustToken": newBustToken
        ])

        return (url.absoluteString, newBustToken)
    }

    func updateProfileImage(_ image: UIImage, session: UserSession) async {
        guard let uid = session.uid else { return }
        do {
            let (url, newBustToken) = try await updateProfileImage(image, for: uid)
            await MainActor.run {
                session.profileImageUrl = url
                session.avatarBustToken = newBustToken
            }
        } catch {
            print("❌ Error al actualizar foto de perfil:", error)
        }
    }

    // MARK: - Eliminar imagen de perfil
    func deleteProfileImage(for uid: String) async {
        let ref = Storage.storage().reference().child("profileImages/\(uid)/avatar.jpg")
        do {
            try await ref.delete()
            let newBustToken = UUID().uuidString
            try await db.collection("users").document(uid).updateData([
                "profileImageUrl": FieldValue.delete(),
                "avatarBustToken": newBustToken
            ])
            // 🆕 borrar copia local del avatar
            UserSession.deleteLocalAvatar()
        } catch {
            print("⚠️ Error al eliminar la imagen de perfil:", error)
        }
    }
}
