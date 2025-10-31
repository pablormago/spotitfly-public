//
//  FavoritesViewModel.swift
//  Spots
//
//  Created by Pablo Jimenez on 29/9/25.
//


//
//  FavoritesViewModel.swift
//  Spots
//
//  Gestión de favoritos del usuario actual.
//  Guarda favoritos en: users/{uid}/favorites/{spotId}
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class FavoritesViewModel: ObservableObject {
    @Published var favoriteIds: Set<String> = []

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    deinit {
        listener?.remove()
    }

    // MARK: - Listener en tiempo real
    func listenFavorites(userId: String) {
        // Reiniciar si ya había uno
        listener?.remove()

        listener = db.collection("users")
            .document(userId)
            .collection("favorites")
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }
                if let err {
                    print("⚠️ listenFavorites error:", err.localizedDescription)
                    return
                }
                let ids = snap?.documents.map { $0.documentID } ?? []
                self.favoriteIds = Set(ids)
                // Debug:
                // print("❤️ Favoritos actualizados (\(ids.count)):", ids)
            }
    }

    // MARK: - Toggle
    func toggleFavorite(spotId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        if favoriteIds.contains(spotId) {
            await removeFavorite(spotId: spotId, userId: uid)
        } else {
            await addFavorite(spotId: spotId, userId: uid)
        }
    }

    // Conveniencia si se llama con el modelo
    func toggleFavorite(spot: Spot) async {
        await toggleFavorite(spotId: spot.id)
    }

    // MARK: - Add / Remove
    func addFavorite(spotId: String, userId: String) async {
        let ref = db.collection("users").document(userId).collection("favorites").document(spotId)

        // Actualización optimista local (opcional)
        let hadIt = favoriteIds.contains(spotId)
        if !hadIt { favoriteIds.insert(spotId) }

        do {
            try await ref.setData(["createdAt": FieldValue.serverTimestamp()])
        } catch {
            print("❌ Error al añadir favorito:", error.localizedDescription)
            // Revertir si falló
            if !hadIt { favoriteIds.remove(spotId) }
        }
    }

    func removeFavorite(spotId: String, userId: String) async {
        let ref = db.collection("users").document(userId).collection("favorites").document(spotId)

        // Actualización optimista local (opcional)
        let hadIt = favoriteIds.contains(spotId)
        if hadIt { favoriteIds.remove(spotId) }

        do {
            try await ref.delete()
        } catch {
            print("❌ Error al quitar favorito:", error.localizedDescription)
            // Revertir si falló
            if hadIt { favoriteIds.insert(spotId) }
        }
    }
}
