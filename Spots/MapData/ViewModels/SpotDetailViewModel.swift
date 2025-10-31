import Foundation
import CoreLocation

@MainActor
class SpotDetailViewModel: ObservableObject {
    @Published var contextData = SpotContextData()
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// Capas que han fallado en el último fetch (para mostrar toast en la vista)
    @Published var failedContexts: [String] = []

    var notamVM: NOTAMViewModel?

    func fetchContext(for spot: Spot) async {
        ASDBG.log("DETAIL", "context IN spot=\(spot.id) c=(\(spot.latitude),\(spot.longitude))")
        isLoading = true
        errorMessage = nil
        failedContexts = []                // ← limpiamos antes de empezar
        defer { isLoading = false }

        let spotLocation = CLLocation(latitude: spot.latitude, longitude: spot.longitude)

        // Helper tolerante a fallos que acumula el nombre de la capa si falla
        func safeFetch<T>(name: String, _ op: @escaping () async throws -> T, fallback: T) async -> T {
            do { return try await op() }
            catch {
                print("⚠️ \(name) error: \(error)")
                failedContexts.append(name)
                return fallback
            }
        }

        // Cargas concurrentes (cada una tolerante a fallos)
        async let infraestructurasAsync: [InfraestructuraFeature] = safeFetch(
            name: "Infraestructuras",
            { try await InfraestructurasService.fetchAround(location: spotLocation, km: 40) },
            fallback: []
        )

        async let restriccionesAsync: [ENAIREFeature] = safeFetch(
            name: "Aero (Restricciones)",
            { try await RestriccionesService.fetchAround(location: spotLocation, km: 50) },
            fallback: []
        )

        async let urbanasAsync: [ENAIREFeature] = safeFetch(
            name: "Urbano",
            { try await UrbanoService.fetchAround(location: spotLocation, km: 50) },
            fallback: []
        )

        async let medioambienteAsync: [ENAIREFeature] = safeFetch(
            name: "Medioambiente",
            { try await MedioambienteService.fetchAround(location: spotLocation, km: 50) },
            fallback: []
        )

        // NOTAMs (tu VM no lanza throw; si algún día lo hace, lo pasamos por safeFetch)
        var notamsResult: [NOTAMFeature] = []
        if notamVM == nil { notamVM = NOTAMViewModel() }
        if let notamVM {
            await notamVM.fetchNotams(for: spotLocation.coordinate)
            notamsResult = notamVM.notams
            // si quieres tratar "sin notams" como fallo de capa, descomenta:
            // if notamsResult.isEmpty { failedContexts.append("NOTAMs") }
        }

        // Recogemos resultados
        let (infraestructuras, restricciones, urbanas, medioambiente) =
            await (infraestructurasAsync, restriccionesAsync, urbanasAsync, medioambienteAsync)

        // Montamos el contexto
        contextData = SpotContextData(
            infraestructuras: infraestructuras,
            restricciones: restricciones,
            urbanas: urbanas,
            medioambiente: medioambiente,
            notams: notamsResult
        )
        ASDBG.log("DETAIL", "context OUT spot=\(spot.id) sources=[R:\(contextData.restricciones.count) U:\(contextData.urbanas.count) M:\(contextData.medioambiente.count) I:\(contextData.infraestructuras.count)]")
    }
}
