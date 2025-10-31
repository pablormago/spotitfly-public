//
//  AppLockView.swift
//  Spots
//
//  Created by Pablo Jimenez on 2/10/25.
//


import SwiftUI

struct AppLockView: View {
    @ObservedObject var lock: AppLockManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "faceid").font(.system(size: 56))
            Text("Verifica tu identidad").font(.headline)
            Button("Usar Face ID / Touch ID") {
                Task { await lock.unlockWithBiometrics() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
