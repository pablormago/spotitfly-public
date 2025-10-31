import Foundation
import CoreLocation

struct InfraestructurasService {

    // BBox local (para no depender de tipos externos)
    private struct BBox {
        let minLon: Double
        let minLat: Double
        let maxLon: Double
        let maxLat: Double
    }

    // Cálculo sencillo de bbox (aprox.) en grados a partir de km
    private static func bboxAround(_ coord: CLLocationCoordinate2D, km: Double) -> BBox {
        let latDegPerKm = 1.0 / 110.574
        let lonDegPerKm = 1.0 / (111.320 * cos(coord.latitude * .pi / 180.0))
        let dLat = km * latDegPerKm
        let dLon = km * lonDegPerKm
        return BBox(
            minLon: coord.longitude - dLon,
            minLat: coord.latitude  - dLat,
            maxLon: coord.longitude + dLon,
            maxLat: coord.latitude  + dLat
        )
    }

    static func fetchAround(location: CLLocation,
                            km: Double = 15) async throws -> [InfraestructuraFeature] {
        let bbox = bboxAround(location.coordinate, km: km)

        // ===== BEGIN REPLACE CHUNK: InfraestructurasService.fetchAround (WFS → REST) =====
            // 🔹 REST (FeatureServer/0)
            var comps = URLComponents(string: "https://servais.enaire.es/insignia/rest/services/NSF_SRV/SRV_UAS_ZG_V1/FeatureServer/0/query")!
            let envelope = "\(bbox.minLon),\(bbox.minLat),\(bbox.maxLon),\(bbox.maxLat)"
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
            print("🌍 InfraestructurasService(REST) → URL:\n\(url.absoluteString)")
            #endif

            let (data, response) = try await dataWithRetry(from: url)

            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                if let s = try? String(data: data, encoding: .utf8) {
                    print("⚠️ [Infra/REST] cuerpo no-2xx (primeros 400):\n\(s.prefix(400))")
                }
                throw URLError(.badServerResponse)
            }

            // Validación rápida de JSON crudo (igual que antes)
            _ = try JSONSerialization.jsonObject(with: data, options: [])

            do {
                let decoded = try JSONDecoder().decode(InfraestructuraCollection.self, from: data)
                #if DEBUG
                print("✅ [Infra/REST] \(decoded.features.count) features crudas")
                #endif
                let filtered = decoded.features.filter { $0.contains(point: location.coordinate) }
                #if DEBUG
                print("🔹 [Infra/REST] features que CONTAIN el punto: \(filtered.count)")
                #endif
                return filtered
            } catch {
                print("❌ [Infra/REST] decode error:", error.localizedDescription)
                throw error
            }
        // ===== END REPLACE CHUNK =====

    }

    // MARK: - URL WFS

    /// WFS — GeoJSON con bbox en EPSG:4326
    private static func makeWFSURL(bbox: BBox) -> URL {
        let urlString =
        "https://servais.enaire.es/insignia/services/NSF_SRV/SRV_UAS_ZG_V1/MapServer/WFSServer?service=WFS&version=2.0.0&request=GetFeature&typeName=SRV_UAS_ZG_V1:ZGUAS_Infraestructuras&outputFormat=geojson&srsName=EPSG:4326&resultType=results&bbox=\(bbox.minLon),\(bbox.minLat),\(bbox.maxLon),\(bbox.maxLat),EPSG:4326&count=1000&startIndex=0"
        return URL(string: urlString)!
    }

    // MARK: - Debug dump (solo DEBUG)
    private static func debugDumpJSON(_ data: Data, tag: String) {
        #if DEBUG
        let safeTag = tag
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        let filename = "infra_dump_\(safeTag).json"
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            print("📝 [Infra] dump guardado en Documents: \(filename)")
        } catch {
            print("⚠️ [Infra] no se pudo escribir dump:", error.localizedDescription)
        }
        #endif
    }
}
// ===== BEGIN: InfraestructurasService REST helpers =====
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
            return (data, response)
        } catch {
            if (error as? URLError)?.code == .cancelled || error is CancellationError { throw CancellationError() }
            lastError = error
            #if DEBUG
            print("↻ [Infra/REST] retry \(attempt) por error: \(error.localizedDescription)")
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
// ===== END: InfraestructurasService REST helpers =====
