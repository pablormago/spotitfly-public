import SwiftUI

struct RestriccionRow: View {
    let feature: ENAIREFeature
    let hasNotam: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                // Nombre de la restricción
                Text(feature.displayName)
                    .font(.headline)

                // Identificador
                Text("ID: \(feature.displayIdentifier)")
                    .font(.subheadline)

                // Razón
                Text("Motivo: \(feature.displayReason)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Mensaje resumido
                if !feature.displayMessage.isEmpty {
                    Text("Mensaje: \(feature.displayMessage)")
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .lineLimit(3)
                }

                // Email de contacto
                if !feature.displayEmail.isEmpty {
                    Text("Email: \(feature.displayEmail)")
                        .font(.footnote)
                }

                // Coordenadas
                if let (lat, lon) = feature.primerPuntoDelPoligono() {
                    Text(String(format: "Lat: %.6f, Lon: %.6f", lat, lon))
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            Spacer()

            // Badge rojo si hay NOTAMs en general
            if hasNotam {
                Text("NOTAM")
                    .font(.caption2)
                    .bold()
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.red)
                    .clipShape(Capsule())
            }
        }
        .padding(.vertical, 4)
    }
}
