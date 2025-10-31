import Foundation
import CoreLocation

struct UrbanoService {
    // ===== BEGIN REPLACE: UrbanoService.fetchAround (WFS → REST) =====
    static func fetchAround(location: CLLocation, km: Double = 20) async throws -> [ENAIREFeature] {
        let bbox = location.coordinate.boundingBox(km: km)
        let envelope = "\(bbox.minLon),\(bbox.minLat),\(bbox.maxLon),\(bbox.maxLat)"

        var comps = URLComponents(string: "https://servais.enaire.es/insignia/rest/services/NSF_SRV/SRV_UAS_ZG_V1/FeatureServer/3/query")!
        comps.queryItems = [
            .init(name: "where", value: "1=1"),
            .init(name: "geometry", value: envelope),
            .init(name: "geometryType", value: "esriGeometryEnvelope"),
            .init(name: "inSR", value: "4326"),
            .init(name: "spatialRel", value: "esriSpatialRelIntersects"),
            .init(name: "outFields", value: "*"),
            .init(name: "returnGeometry", value: "true"),
            .init(name: "outSR", value: "4326"),
            .init(name: "f", value: "geojson")
        ]
        let url = comps.url!

        #if DEBUG
        print("🌍 UrbanoService(REST) → URL:\n\(url.absoluteString)")
        #endif

        let (data, response) = try await dataWithRetry(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(ENAIRECollection.self, from: data)
        let dentro = decoded.features.filter { $0.contains(point: location.coordinate) }

        #if DEBUG
        print("✅ UrbanoService(REST) → \(decoded.features.count) crudas, dentro spot: \(dentro.count)")
        #endif

        return dentro
    }
    // ===== END REPLACE =====

}


private func dataWithRetry(from url: URL, maxAttempts: Int = 3) async throws -> (Data, URLResponse) {
    var delayNs: UInt64 = 250_000_000
    var lastError: Error?
    for attempt in 1...maxAttempts {
        do {
            if Task.isCancelled { throw CancellationError() }
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            // “Oler” JSON por si el servidor etiqueta mal
            if let mime = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.lowercased(),
               !mime.contains("json") {
                // A veces devuelve HTML/XML de error
                throw URLError(.cannotParseResponse)
            }
            return (data, response)
        } catch {
            if (error as? URLError)?.code == .cancelled || error is CancellationError { throw CancellationError() }
            lastError = error
            #if DEBUG
            print("↻ [Urbano/REST] retry \(attempt) por error: \(error.localizedDescription)")
            #endif
            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: delayNs + UInt64.random(in: 0...120_000_000))
                delayNs = min(delayNs * 2, 1_200_000_000)
            } else {
                throw lastError ?? error
            }
        }
    }
    throw lastError ?? URLError(.unknown)
}


