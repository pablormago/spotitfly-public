//
//  BadgeSync.swift
//  Spots
//
//  Created by Pablo Jimenez on 21/10/25.
//


import Foundation
import FirebaseAuth
import FirebaseFirestore
import UIKit

final class BadgeSync {
    static let shared = BadgeSync()
    private init() {}

    private var listener: ListenerRegistration?

    /// Empieza a escuchar el doc de contadores del usuario y reflejarlo en el badge.
    func start() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        stop()

        let ref = Firestore.firestore()
            .collection("users").document(uid)
            .collection("meta").document("counters")

        listener = ref.addSnapshotListener { snap, _ in
            let badge = (snap?.data()?["badge"] as? Int) ?? 0
            DispatchQueue.main.async {
                UIApplication.shared.applicationIconBadgeNumber = badge
            }
        }
    }

    /// Deja de escuchar y limpia el badge.
    func stop() {
        listener?.remove()
        listener = nil
        DispatchQueue.main.async {
            UIApplication.shared.applicationIconBadgeNumber = 0
        }
    }

    /// Pull puntual (útil justo después de marcar leído desde el detalle).
    func syncOnce() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        do {
            let snap = try await Firestore.firestore()
                .collection("users").document(uid)
                .collection("meta").document("counters")
                .getDocument()
            let badge = (snap.data()?["badge"] as? Int) ?? 0
            await MainActor.run {
                UIApplication.shared.applicationIconBadgeNumber = badge
            }
        } catch {
            // Silencioso: si falla, el listener continuo lo arreglará cuando vuelva el foco/red.
            print("BadgeSync.syncOnce error:", error.localizedDescription)
        }
    }
}
