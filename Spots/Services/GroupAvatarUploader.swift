//
//  GroupAvatarUploader.swift
//  Spots
//
//  Created by Pablo Jimenez on 24/10/25.
//


import Foundation
import UIKit
import FirebaseStorage
import FirebaseAuth // ✅ necesitamos el uid para cumplir reglas

enum GroupAvatarUploader {
    /// Sube el avatar a `chats/{chatId}/avatar/v{ts}.jpg` con compresión JPEG 0.75.
    /// Devuelve `photoURL` con `?bust={ts}` para invalidar caché.
    static func upload(chatId: String, image: UIImage) async throws -> String {
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "GroupAvatarUploader", code: -2, userInfo: [NSLocalizedDescriptionKey: "Sesión inválida"])
        }
        // ✅ cumple tus reglas: chats/{chatId}/{uploaderUid}/...
        let path = "chats/\(chatId)/\(uid)/avatar_v\(ts).jpg"
        let ref = Storage.storage().reference().child(path)


        // Compresión: alineada con el proyecto (JPEG 0.75).
        // Si tienes un util de compresión propio (p.ej. ImageCompressor),
        // puedes sustituir esta línea, manteniendo calidad 0.75.
        guard let data = image.jpegData(compressionQuality: 0.75) else {
            throw NSError(domain: "GroupAvatarUploader", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo codificar JPEG"])
        }

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        let _ = try await ref.putDataAsync(data, metadata: metadata)
        let url = try await ref.downloadURL()
        // ✅ Si la URL ya trae query (?alt=media&token=...), usar &bust= en vez de ?bust=
        let sep = (url.query == nil) ? "?" : "&"
        let photoURL = "\(url.absoluteString)\(sep)bust=\(ts)"
        print("✅ Group avatar uploaded:", photoURL) // debug
        return photoURL

    }
}
