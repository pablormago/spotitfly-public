
import Foundation

struct MedioambienteOverlayService {
    static func fetch(bbox: OverlayBBox) async throws -> [ENAIREFeature] {
        let url = makeURL(bbox: bbox)
        #if DEBUG
        //print("🌍 MedioambienteOverlayService → URL:\n\(url.absoluteString)")
        #endif
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let mime = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? "unknown"
        if !mime.contains("json") {
            if let s = String(data: data, encoding: .utf8) {
                print("⚠️ [Medioambiente/REST] Content-Type no JSON. Snippet:\n\(s.prefix(400))")
            }
            throw URLError(.cannotParseResponse)
        }

        let decoded = try JSONDecoder().decode(ENAIRECollection.self, from: data)
        #if DEBUG
        print("✅ [Medioambiente/REST] \(decoded.features.count) features crudas")
        #endif
        return decoded.features
    }

    private static func makeURL(bbox: OverlayBBox) -> URL {
        var comps = URLComponents(string: "https://servais.enaire.es/insignia/rest/services/NSF_SRV/SRV_UAS_ZG_V1/FeatureServer/1/query")!
        comps.queryItems = [
            .init(name: "where", value: "1=1"),
            .init(name: "geometry", value: bbox.envelope4326),
            .init(name: "geometryType", value: "esriGeometryEnvelope"),
            .init(name: "inSR", value: "4326"),
            .init(name: "spatialRel", value: "esriSpatialRelIntersects"),
            .init(name: "outFields", value: "*"),
            .init(name: "returnGeometry", value: "true"),
            .init(name: "outSR", value: "4326"),
            .init(name: "f", value: "geojson")
        ]
        return comps.url!
    }


}
// MARK: - Wrapper viewport: fetchAround(location:km:)
import CoreLocation

extension MedioambienteOverlayService {
    static func fetchAround(location: CLLocation, km: Double) async throws -> [ENAIREFeature] {
        // Reutiliza tu helper para obtener "minLon,minLat,maxLon,maxLat,EPSG:4326"
        let bboxWfs = wfsBBoxParam(center: location, km: km)
        let parts = bboxWfs.split(separator: ",").map(String.init)
        guard parts.count >= 4 else { return [] }
        // Envelope REST = sin el "EPSG:4326" del final
        let envelope = [parts[0], parts[1], parts[2], parts[3]].joined(separator: ",")

        var comps = URLComponents(string: "https://servais.enaire.es/insignia/rest/services/NSF_SRV/SRV_UAS_ZG_V1/FeatureServer/1/query")!
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
        print("🌍 [Medioambiente] URL(around) → \(url.absoluteString)")
        #endif

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ENAIRECollection.self, from: data)
        return decoded.features
    }
}

// MARK: - Retry / backoff y mapeo de cancelaciones
private func dataWithRetry(from url: URL, maxAttempts: Int = 3) async throws -> (Data, URLResponse) {
    var delayNs: UInt64 = 200_000_000
    var lastError: Error?
    
    for attempt in 1...maxAttempts {
        do {
            if Task.isCancelled { throw CancellationError() }
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            return (data, response)
        } catch {
            if let u = error as? URLError, u.code == .cancelled { throw CancellationError() }
            if error is CancellationError { throw error }
            lastError = error
#if DEBUG
            print("↻ [Medioambiente/REST] retry \(attempt) por error: \(error.localizedDescription)")
#endif
            if attempt < maxAttempts {
                try? await Task.sleep(nanoseconds: delayNs + UInt64.random(in: 0...100_000_000))
                delayNs = min(delayNs * 2, 800_000_000)
                continue
            } else {
                throw lastError ?? error
            }
        }
    }
    throw lastError ?? URLError(.unknown)
}
