import Foundation
import CoreLocation

// Servicio de geocodificación seguro (actor) con caché, coalescing, throttle y timeout.
actor GeocodingService {
    static let shared = GeocodingService()

    // Estado protegido por el actor
    private var cache: [String: String] = [:]
    private var inflight: [String: Task<String?, Never>] = [:]

    // Throttle (~300 ms entre llamadas) para evitar rate-limit
    private var lastCallNS: UInt64 = 0
    private let gapNS: UInt64 = 300_000_000

    /// Espera el turno respetando el throttle (aislado en el actor)
    private func waitTurn() async {
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = now &- lastCallNS
        if elapsed < gapNS {
            try? await Task.sleep(nanoseconds: gapNS - elapsed)
        }
        lastCallNS = DispatchTime.now().uptimeNanoseconds
    }

    /// Localidad para lat/lon; devuelve nil si no se puede resolver en tiempo razonable.
    func locality(for latitude: Double, longitude: Double) async -> String? {
        let key = Self.key(lat: latitude, lon: longitude)

        if let cached = cache[key] { return cached }
        if let existing = inflight[key] { return await existing.value }

        // Nueva tarea coalescida
        let task = Task<String?, Never> { [weak self] in
            guard let self else { return nil }

            for attempt in 0...1 {
                await self.waitTurn() // ✅ mutate throttle desde el actor

                if let city = await self.reverseOnce(lat: latitude, lon: longitude) {
                    await self.store(key: key, value: city) // ✅ llamada a método del actor
                    return city
                }
                // pequeño backoff antes del reintento
                if attempt == 0 { try? await Task.sleep(nanoseconds: 550_000_000) }
            }
            return nil
        }

        inflight[key] = task
        let result = await task.value
        inflight[key] = nil   // limpia inflight para no crecer
        return result
    }

    // Guarda en caché (aislado por el actor)
    private func store(key: String, value: String) {
        cache[key] = value
    }

    // Una resolución con timeout. Usa un CLGeocoder *nuevo* por petición para evitar cancelaciones cruzadas.
    private func reverseOnce(lat: Double, lon: Double) async -> String? {
        let geocoder = CLGeocoder()
        do {
            let placemarks: [CLPlacemark] = try await withThrowingTaskGroup(of: [CLPlacemark].self) { group in
                // tarea real
                group.addTask {
                    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[CLPlacemark], Error>) in
                        let location = CLLocation(latitude: lat, longitude: lon)
                        geocoder.reverseGeocodeLocation(location) { placemarks, error in
                            if let error { cont.resume(throwing: error) }
                            else { cont.resume(returning: placemarks ?? []) }
                        }
                    }
                }
                // timeout (2.5 s)
                group.addTask {
                    try await Task.sleep(nanoseconds: 2_500_000_000)
                    throw NSError(domain: "GeocodingTimeout", code: -1)
                }

                // Gana el primero (ok o timeout)
                let first = try await group.next()!
                group.cancelAll()
                return first
            }

            let p = placemarks.first
            return p?.locality ?? p?.subLocality ?? p?.administrativeArea ?? p?.country
        } catch {
            geocoder.cancelGeocode() // por si la real perdió la carrera
            return nil
        }
    }

    // Clave de caché (~100 m)
    private static func key(lat: Double, lon: Double) -> String {
        let latQ = (lat * 1000).rounded() / 1000
        let lonQ = (lon * 1000).rounded() / 1000
        return "\(latQ),\(lonQ)"
    }
}
