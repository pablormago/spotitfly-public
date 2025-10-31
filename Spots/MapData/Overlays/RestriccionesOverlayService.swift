
import Foundation

struct RestriccionesOverlayService {
    static func fetch(bbox: OverlayBBox) async throws -> [ENAIREFeature] {
        let url = makeURL(bbox: bbox)
                #if DEBUG
                print("🌍 [Restr] URL → \(url.absoluteString)")
                print("🌍 [Restr] bbox.wfsParam → \(bbox.wfsParam)")
                #endif
                let (data, response) = try await dataWithRetry(from: url)

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // ArcGIS WFS puede devolver XML de excepción si el formato no es correcto
        let mime = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? "unknown"
        if !mime.contains("json") {
            if let s = String(data: data, encoding: .utf8) {
                print("⚠️ [Restricciones/REST] Content-Type no JSON. Snippet:\n\(s.prefix(400))")

            }
            throw URLError(.cannotParseResponse)
        }

        let decoded = try JSONDecoder().decode(ENAIRECollection.self, from: data)
        #if DEBUG
        print("✅ [Restricciones/REST] \(decoded.features.count) features crudas")

        #endif
        return decoded.features
    }

    private static func makeURL(bbox: OverlayBBox) -> URL {
        var comps = URLComponents(string: "https://servais.enaire.es/insignia/rest/services/NSF_SRV/SRV_UAS_ZG_V1/FeatureServer/2/query")!
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

extension RestriccionesOverlayService {
    static func fetchAround(location: CLLocation, km: Double) async throws -> [ENAIREFeature] {
        // Reutilizamos tu helper WFS para calcular el cuadrado, pero lo convertimos a envelope REST
        let bboxWfs = wfsBBoxParam(center: location, km: km) // minLon,minLat,maxLon,maxLat,EPSG:4326
        let parts = bboxWfs.split(separator: ",").map(String.init)
        guard parts.count >= 4 else { return [] }
        let envelope = [parts[0], parts[1], parts[2], parts[3]].joined(separator: ",")

        var comps = URLComponents(string: "https://servais.enaire.es/insignia/rest/services/NSF_SRV/SRV_UAS_ZG_V1/FeatureServer/2/query")!
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
        print("🌍 [Restr] URL(around) → \(url.absoluteString)")
        #endif

        let (data, response) = try await dataWithRetry(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(ENAIRECollection.self, from: data)
        return decoded.features
    }
}

// MARK: - Retry / backoff para respuestas XML o fallos puntuales (Restricciones)
private extension RestriccionesOverlayService {
    static func dataWithRetry(from url: URL, maxAttempts: Int = 3) async throws -> (Data, URLResponse) {
        var delayNs: UInt64 = 250_000_000 // 0.25s
            var lastError: Error?
            
            for attempt in 1...maxAttempts {
                do {
                    // Si el Task ya está cancelado, propaga
                    if Task.isCancelled { throw CancellationError() }
                    
                    let (data, response) = try await URLSession.shared.data(from: url)
                    
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        throw URLError(.badServerResponse)
                    }
                    
                    // Mime check “oler-json” (igual que ya hacías)
                    if !isLikelyJSON(response: response, data: data) {
        #if DEBUG
                        print("⚠️ [Restricciones/WFS] Content-Type no JSON (intento \(attempt)). Reintentando…")
                        if let s = String(data: data.prefix(180), encoding: .utf8) {
                            print("Snippet:", s)
                        }
        #endif
                        if attempt < maxAttempts {
                            try? await Task.sleep(nanoseconds: delayNs + UInt64.random(in: 0...120_000_000))
                            delayNs = min(delayNs * 2, 1_200_000_000)
                            continue
                        } else {
                            throw URLError(.cannotParseResponse)
                        }
                    }
                    
                    return (data, response)
                } catch {
                    // 🔴 CLAVE: si es un cancel de URLSession, mapéalo a CancellationError
                    if let u = error as? URLError, u.code == .cancelled {
                        throw CancellationError()
                    }
                    if error is CancellationError {
                        throw error
                    }
                    
                    lastError = error
        #if DEBUG
                    print("↻ [Restricciones/WFS] retry \(attempt) por error: \(error.localizedDescription)")
        #endif
                    if attempt < maxAttempts {
                        try? await Task.sleep(nanoseconds: delayNs + UInt64.random(in: 0...120_000_000))
                        delayNs = min(delayNs * 2, 1_200_000_000)
                        continue
                    } else {
                        throw lastError ?? error
                    }
                }
            }
            
            throw lastError ?? URLError(.unknown)
    }

    static func isLikelyJSON(response: URLResponse, data: Data) -> Bool {
        if let mime = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type")?
            .lowercased(), mime.contains("json") {
            return true
        }
        if let s = String(data: data.prefix(80), encoding: .utf8) {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return true }
            if trimmed.contains("<ExceptionReport") { return false }
        }
        return false
    }
}
