import Foundation

/// Caché en memoria del contexto de cada spot durante la sesión (hasta cerrar la app).
/// Actor = estado aislado y seguro frente a concurrencia.
actor SpotContextCache {
    static let shared = SpotContextCache()

    // Almacén: clave = spot.id
    private var store: [String: SpotContextData] = [:]

    // MARK: - API por ID
    func get(for id: String) -> SpotContextData? {
        store[id]
    }

    func set(_ data: SpotContextData, for id: String) {
        store[id] = data
    }

    func remove(id: String) {
        store.removeValue(forKey: id)
    }

    func clear() {
        store.removeAll()
    }

    // MARK: - Conveniences si prefieres pasar el Spot entero
    func get(for spot: Spot) -> SpotContextData? {
        get(for: spot.id)
    }

    func set(_ data: SpotContextData, for spot: Spot) {
        set(data, for: spot.id)
    }
}
