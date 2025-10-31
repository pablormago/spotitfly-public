//
//  AerialContextDisclaimerView.swift
//  Spots
//
//  Created by Pablo Jimenez on 30/9/25.
//


import SwiftUI

struct AerialContextDisclaimerView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 16, weight: .bold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Aviso importante")
                    .font(.subheadline.bold())
                    .foregroundColor(.black)

                Text("""
La información de contexto aéreo (restricciones, NOTAM, accesos y otros datos) puede no ser completa, exacta ni estar actualizada en todo momento. **Debes verificar siempre** la normativa y las condiciones vigentes antes de volar y **actuar bajo tu propia responsabilidad**. **SpotItFly no asume responsabilidad** por el uso de esta información ni por daños o sanciones derivados de la actividad realizada.
""")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.10))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
        .accessibilityLabel("Aviso importante: verifica siempre la normativa vigente. Actúa bajo tu responsabilidad.")
    }
}
