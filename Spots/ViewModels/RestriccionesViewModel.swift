import Foundation

@MainActor
class RestriccionesViewModel: ObservableObject {
    @Published var restricciones: [ENAIREFeature] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private(set) var hasLoaded = false   // ✅ nuevo flag

    func fetchRestricciones() async {
        // ✅ Evita recargar si ya se hizo antes
        if hasLoaded { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let url = URL(string:
            "https://servais.enaire.es/insignia/services/NSF_SRV/SRV_UAS_ZG_V1/MapServer/WFSServer?service=WFS&version=2.0.0&request=GetFeature&typeName=SRV_UAS_ZG_V1:ZGUAS_Aero&outputFormat=geojson"
        ) else {
            errorMessage = "URL inválida"
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            let decoded = try await Task.detached(priority: .userInitiated) {
                return try JSONDecoder().decode(ENAIRECollection.self, from: data)
            }.value

            self.restricciones = decoded.features
            self.hasLoaded = true   // ✅ marcamos que ya se cargó
        } catch {
            self.errorMessage = "Error cargando datos: \(error.localizedDescription)"
        }
    }
}
