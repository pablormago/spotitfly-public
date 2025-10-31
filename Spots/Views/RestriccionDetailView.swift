import SwiftUI
import CoreLocation

struct RestriccionDetailView: View {
    let feature: ENAIREFeature

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                Text("Nombre: \(feature.displayName)")
                    .font(.headline)

                Text("Razón: \(feature.displayReason)")
                    .font(.subheadline)

                if let mensaje = feature.properties?.textoPreferidoHTML {
                    HTMLText(html: mensaje)
                        .frame(maxHeight: .infinity)
                }

                if let coordenadas = feature.primerPuntoCLLocation {
                    Text("Primer vértice: lat \(coordenadas.latitude), lon \(coordenadas.longitude)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let email = feature.properties?.email, !email.isEmpty {
                    Text("Email: \(email)")
                        .font(.footnote)
                        .foregroundColor(.blue)
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Detalle Restricción")
        .navigationBarTitleDisplayMode(.inline)
    }
}
