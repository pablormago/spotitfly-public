//
//  AppLockManager.swift
//  Spots
//
//  Created by Pablo Jimenez on 2/10/25.
//


import LocalAuthentication
import SwiftUI

@MainActor
final class AppLockManager: ObservableObject {
    @Published var locked: Bool = false
    @AppStorage("applock_enabled") var enabled: Bool = false

    func lockIfNeeded() {
        locked = enabled
    }

    func unlockWithBiometrics() async {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Si no hay biometría, desbloquea si quieres permitir fallback
            locked = false
            return
        }
        let reason = "Desbloquear Spots"
        do {
            let success = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            if success { locked = false }
        } catch {
            // Falló FaceID/TouchID -> se queda bloqueado
        }
    }
}
