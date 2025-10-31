
import Foundation

struct InfraestructurasOverlayService {
    
    private static let overscanFactor: Double = 1.6   // ensancha el bbox solo para Infra
    private static let minPadDeg: Double = 0.010      // acolchado mínimo en grados (~1.1 km lat)
    // ⬇️ fallback único si la primera llamada viene vacía/errática
       private static let overscanFactorFallback: Double = 2.2
       private static let minPadDegFallback: Double = 0.015
    
    // -- REST envelope expansion helper (sustituye expandBBoxParam de WFS) --
    private static func restExpandedEnvelope(for bbox: OverlayBBox,
                                             factor: Double,
                                             minPadDeg: Double) -> String {
        guard factor > 1.0 else { return bbox.envelope4326 }
        let dLat = bbox.maxLat - bbox.minLat
        let dLon = bbox.maxLon - bbox.minLon
        let padLat = max((dLat * (factor - 1.0)) / 2.0, minPadDeg)
        let padLon = max((dLon * (factor - 1.0)) / 2.0, minPadDeg)
        let newMinLon = bbox.minLon - padLon
        let newMinLat = bbox.minLat - padLat
        let newMaxLon = bbox.maxLon + padLon
        let newMaxLat = bbox.maxLat + padLat
        return "\(newMinLon),\(newMinLat),\(newMaxLon),\(newMaxLat)"
    }

    // MARK: - REST: fetch por tile (OverlayBBox) con fallback overscan
    static func fetch(bbox: OverlayBBox) async throws -> [InfraestructuraFeature] {
        // Intento primario con el tile exacto
        let url1 = makeURL(bbox: bbox)
        #if DEBUG
        print("🌍 [Infra] URL(tile) → \(url1.absoluteString)")
        #endif

        var (data, response) = try await dataWithRetry(from: url1)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard isLikelyJSON(response: response, data: data) else {
            throw URLError(.cannotParseResponse)
        }

        var decoded = try JSONDecoder().decode(InfraestructuraCollection.self, from: data)
        if !decoded.features.isEmpty {
            #if DEBUG
            print("✅ [Infraestructuras/REST] \(decoded.features.count) features (tile)")
            #endif
            return decoded.features
        }

        // Fallback con overscan más generoso
        let env2 = restExpandedEnvelope(for: bbox,
                                        factor: overscanFactorFallback,
                                        minPadDeg: minPadDegFallback)
        let url2 = makeURL(envelope: env2)
        #if DEBUG
        print("🟦 [Infra] URL(tile fallback) → \(url2.absoluteString)")
        #endif

        (data, response) = try await dataWithRetry(from: url2)
        guard let http2 = response as? HTTPURLResponse, (200...299).contains(http2.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard isLikelyJSON(response: response, data: data) else {
            throw URLError(.cannotParseResponse)
        }

        decoded = try JSONDecoder().decode(InfraestructuraCollection.self, from: data)
        #if DEBUG
        print("✅ [Infraestructuras/REST] \(decoded.features.count) features (fallback)")
        #endif
        return decoded.features
    }

    // Fetch REST a partir de un envelope "minLon,minLat,maxLon,maxLat" (EPSG:4326)
    static func fetch(envelope4326: String) async throws -> [InfraestructuraFeature] {
        let url = makeURL(envelope: envelope4326)
        #if DEBUG
        print("🌍 [Infra] URL(envelope) → \(url.absoluteString)")
        #endif

        let (data, response) = try await dataWithRetry(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard isLikelyJSON(response: response, data: data) else {
            throw URLError(.cannotParseResponse)
        }

        let decoded = try JSONDecoder().decode(InfraestructuraCollection.self, from: data)
        #if DEBUG
        print("✅ [Infraestructuras/REST] \(decoded.features.count) features (envelope)")
        #endif
        return decoded.features
    }

    // Compat con llamadas antiguas: "minLon,minLat,maxLon,maxLat,EPSG:4326" → usa REST por envelope
    static func fetch(bboxParam: String) async throws -> [InfraestructuraFeature] {
        let parts = bboxParam.split(separator: ",")
        guard parts.count >= 4 else { return [] }
        let env = "\(parts[0]),\(parts[1]),\(parts[2]),\(parts[3])"
        return try await fetch(envelope4326: env)
    }


    
    private static func makeURL(bbox: OverlayBBox) -> URL {
        var comps = URLComponents(string: "https://servais.enaire.es/insignia/rest/services/NSF_SRV/SRV_UAS_ZG_V1/FeatureServer/0/query")!
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
    // Builder REST alternativo cuando ya traemos el envelope expandido
    private static func makeURL(envelope: String) -> URL {
        var comps = URLComponents(string: "https://servais.enaire.es/insignia/rest/services/NSF_SRV/SRV_UAS_ZG_V1/FeatureServer/0/query")!
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
        return comps.url!
    }

    
    


    
    /// Expande un bbox WFS "minLon,minLat,maxLon,maxLat,EPSG:4326" en grados
    

    // MARK: - Retry / backoff para respuestas XML o fallos puntuales
    private static func dataWithRetry(from url: URL, maxAttempts: Int = 3) async throws -> (Data, URLResponse) {
        var delayNs: UInt64 = 250_000_000 // 0.25s
            var lastError: Error?
            
            for attempt in 1...maxAttempts {
                do {
                    if Task.isCancelled { throw CancellationError() }
                    
                    let (data, response) = try await URLSession.shared.data(from: url)
                    
                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        throw URLError(.badServerResponse)
                    }
                    
                    if !isLikelyJSON(response: response, data: data) {
        #if DEBUG
                        print("⚠️ [Infraestructuras/REST] Content-Type no JSON (intento \(attempt)). Reintentando…")
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
                    if let u = error as? URLError, u.code == .cancelled {
                        throw CancellationError()
                    }
                    if error is CancellationError {
                        throw error
                    }
                    
                    lastError = error
        #if DEBUG
                    print("↻ [Infraestructuras/REST] retry \(attempt) por error: \(error.localizedDescription)")
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
    
    private static func isLikelyJSON(response: URLResponse, data: Data) -> Bool {
        if let mime = (response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Type")?
            .lowercased(), mime.contains("json") {
            return true
        }
        // Algunos servidores etiquetan mal: olfatea el primer char
        if let s = String(data: data.prefix(80), encoding: .utf8) {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return true }
            if trimmed.contains("<ExceptionReport") { return false }
        }
        return false
    }
    
}
// MARK: - Wrapper viewport: fetchAround(location:km:)
import CoreLocation

extension InfraestructurasOverlayService {
    static func fetchAround(location: CLLocation, km: Double) async throws -> [InfraestructuraFeature] {
        // Partimos del bbox por kilómetros (utilidad existente) y lo convertimos a envelope REST,
        // aplicando overscan normal y, si viene vacío, un fallback más ancho.
        let wfs = wfsBBoxParam(center: location, km: km) // "minLon,minLat,maxLon,maxLat,EPSG:4326"
        let p = wfs.split(separator: ",").compactMap { Double($0) }
        guard p.count >= 4 else { return [] }
        let minLon = p[0], minLat = p[1], maxLon = p[2], maxLat = p[3]
        let dLat = maxLat - minLat
        let dLon = maxLon - minLon

        func expandedEnv(factor: Double, minPad: Double) -> String {
            let padLat = max((dLat * (factor - 1.0)) / 2.0, minPad)
            let padLon = max((dLon * (factor - 1.0)) / 2.0, minPad)
            return "\(minLon - padLon),\(minLat - padLat),\(maxLon + padLon),\(maxLat + padLat)"
        }

        // Primario
        let env1 = expandedEnv(factor: overscanFactor, minPad: minPadDeg)
        var url = makeURL(envelope: env1)
        #if DEBUG
        print("🌍 [Infra] URL(around) → \(url.absoluteString)")
        #endif

        var (data, resp) = try await dataWithRetry(from: url)
        guard let http = resp as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard isLikelyJSON(response: resp, data: data) else { throw URLError(.cannotParseResponse) }
        var decoded = try JSONDecoder().decode(InfraestructuraCollection.self, from: data)
        if !decoded.features.isEmpty { return decoded.features }

        // Fallback
        let env2 = expandedEnv(factor: overscanFactorFallback, minPad: minPadDegFallback)
        url = makeURL(envelope: env2)
        #if DEBUG
        print("🟦 [Infra] URL(around fallback) → \(url.absoluteString)")
        #endif

        (data, resp) = try await dataWithRetry(from: url)
        guard let http2 = resp as? HTTPURLResponse, (200...299).contains(http2.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard isLikelyJSON(response: resp, data: data) else { throw URLError(.cannotParseResponse) }
        decoded = try JSONDecoder().decode(InfraestructuraCollection.self, from: data)
        return decoded.features
    }
}

