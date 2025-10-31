import SwiftUI
import MapKit

/// Sheet que muestra el contexto (restricciones, NOTAM, etc.) para un punto cualquiera.
/// Reutiliza `SpotDetailContextViewLoaded` y el mismo ViewModel de detalle,
/// construyendo un Spot temporal solo para calcular el contexto. Ahora además
/// muestra la "localidad" resuelta por geocoding para el centro.
struct PointContextSheet: View {
    let center: CLLocationCoordinate2D

    @State private var loading = true
    @State private var contextData: SpotContextData?
    @State private var locality: String?

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                // Encabezado con coordenadas + localidad
                HStack(spacing: 8) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(String(format: "%.5f, %.5f", center.latitude, center.longitude))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }

                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle")
                    Text(locality ?? "Localizando…")
                }
                .font(.footnote)
                .foregroundColor(.secondary)

                Divider().padding(.vertical, 4)

                // Contenido del contexto
                Group {
                    if let contextData, !loading {
                        SpotDetailContextViewLoaded(contextData: contextData)
                            .transition(.opacity.combined(with: .scale))
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Cargando contexto…")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .padding()
            .navigationTitle("Restricciones")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        defer { loading = false }

        // Spot temporal para aprovechar el fetch existente
        let temp = Spot(
            id: UUID().uuidString,
            name: "Punto",
            description: "",
            latitude: center.latitude,
            longitude: center.longitude,
            rating: 0,
            bestDate: nil,
            category: .otros,
            imageUrl: nil,
            createdBy: "",
            createdAt: Date(),
            locality: nil
        )

        // Lanza en paralelo: geocoding + contexto
        async let loc: String? = GeocodingService.shared.locality(for: center.latitude, longitude: center.longitude)

        let vm = SpotDetailViewModel()
        await vm.fetchContext(for: temp)
        self.contextData = vm.contextData

        // ✅ Publica el contexto para que SpotsMapView pinte overlays
        if let ctx = self.contextData {
            NotificationCenter.default.post(
                name: Notification.Name("AirContextDidUpdate"),
                object: nil,
                userInfo: ["context": ctx]
            )
        }

        self.locality = await loc
    }

}
