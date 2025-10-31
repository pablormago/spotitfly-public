import Foundation

@MainActor
class InfraestructurasViewModel: ObservableObject {
    @Published var infraestructuras: [InfraestructuraFeature] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func fetchInfraestructuras(around feature: ENAIREFeature, km: Double = 2.0) async {
        guard let centro = feature.primerPuntoCLLocation else {
            errorMessage = "No se pudo calcular el centro del polígono"
            return
        }

        let bbox = centro.boundingBox(km: km)

        let urlString = """
        https://servais.enaire.es/insignia/services/NSF_SRV/SRV_UAS_ZG_V1/MapServer/WFSServer?\
        service=WFS&version=2.0.0&request=GetFeature&typeName=ZGUAS_Infraestructuras&\
        outputFormat=geojson&bbox=\(bbox.minLon),\(bbox.minLat),\(bbox.maxLon),\(bbox.maxLat)
        """

        guard let url = URL(string: urlString) else {
            errorMessage = "URL de Infraestructuras inválida"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(InfraestructuraCollection.self, from: data)

            // 🧹 Deduplicar por identifier (o usar el id generado si viene vacío)
            let uniques = Dictionary(grouping: decoded.features, by: { $0.properties.identifier ?? $0.id })
                .compactMap { $0.value.first }

            self.infraestructuras = uniques
        } catch {
            self.errorMessage = "Error cargando infraestructuras: \(error.localizedDescription)"
        }
    }
}
