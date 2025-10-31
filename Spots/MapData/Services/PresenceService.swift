//
//  PresenceService.swift
//  Spots
//

import Foundation
import FirebaseAuth
import FirebaseFirestore
import UIKit

final class PresenceService {
    static let shared = PresenceService()

    private let db = Firestore.firestore()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var currentUid: String?

    private init() {}

    // MARK: - Iniciar presencia
    func start() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        currentUid = uid

        // Marca online inmediatamente
        setPresence(uid: uid, online: true)

        // Refresca cada 60s (heartbeat)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            guard let self, let uid = self.currentUid else { return }
            self.setPresence(uid: uid, online: true)
        }
        if let t = timer {
            RunLoop.main.add(t, forMode: .common)
        }

        // Observadores de ciclo de vida
        observers.append(NotificationCenter.default.addObserver(
            forName: UIScene.didActivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let uid = self.currentUid else { return }
            self.setPresence(uid: uid, online: true)
        })

        observers.append(NotificationCenter.default.addObserver(
            forName: UIScene.willDeactivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self, let uid = self.currentUid else { return }
            self.setPresence(uid: uid, online: false)
        })
    }

    // MARK: - Parar presencia
    func stop() {
        timer?.invalidate()
        timer = nil

        for obs in observers {
            NotificationCenter.default.removeObserver(obs)
        }
        observers.removeAll()

        if let uid = currentUid {
            setPresence(uid: uid, online: false)
        }
        currentUid = nil
    }

    // MARK: - Escritura en Firestore
    private func setPresence(uid: String, online: Bool) {
        let data: [String: Any] = [
            "lastSeen": FieldValue.serverTimestamp(),
            "isOnline": online
        ]
        db.collection("users").document(uid).setData(data, merge: true)
    }
}
