//
//  AirspaceOverlaysView.swift
//  Spots
//
//  Overlays en vivo (ENAIRE + Urbano + Medioambiente + Infraestructura)
//  - Contornos (doble trazo: halo + línea) y relleno de baja opacidad.
//  - Fetch por span (radio aprox), debounce y caché por tile.
//  - EXCLUYE TMA (en store y en render).
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Tipos comunes

enum AirspaceKind: String {
    case CTR, TMA, ATZ
    case prohibited = "P"
    case restricted = "R"
    case danger     = "D"
    case other      = "OTHER"
}

struct AirspaceStyle {
    let stroke: Color
    let halo: Color
    let lineWidth: CGFloat
    let fill: Color
    
    static func style(for kind: AirspaceKind) -> AirspaceStyle {
        // Colores base del trazo
        let base: Color
        let width: CGFloat
        switch kind {
        case .prohibited:  base = .red;    width = 1.6
        case .restricted:  base = .orange; width = 1.6
        case .danger:      base = .yellow; width = 1.6
        case .CTR:         base = .blue;   width = 1.6
        case .TMA:         base = .purple; width = 1.6   // (no se dibuja, pero dejamos estilo coherente)
        case .ATZ:         base = .brown;  width = 1.6
        case .other:       base = .gray;   width = 1.6
        }
        // Relleno con opacidad baja; halo blanco suave
        return .init(
            stroke: base,
            halo: .white.opacity(0.9),
            lineWidth: width,
            fill: base.opacity(0.08) // 👈 baja opacidad, NO transparente
        )
    }
}

// Identidad de la “fuente” para poder filtrar por capa
enum AirspaceSource: String, CaseIterable, Hashable {
    case restricciones
    case urbano
    case medioambiente
    case infraestructura
}

// Geometría para pintar (sin Hashable/Equatable para evitar choques con CLLocationCoordinate2D)
enum AirspaceGeometry {
    case polygon([CLLocationCoordinate2D])
    case polyline([CLLocationCoordinate2D])
}

// Identificable basta para ForEach
struct AirspaceFeature: Identifiable {
    var id = UUID()
    var kind: AirspaceKind
    var geometry: AirspaceGeometry
    var title: String
    var source: AirspaceSource
}

// MARK: - Helpers

private extension MKCoordinateRegion {
    /// Radio (km) aproximado a partir del span visible.
    var approxRadiusKm: Double {
        let maxDelta = max(span.latitudeDelta, span.longitudeDelta)
        // 1º ~ 111 km; usamos la mitad del delta como radio, con límites razonables.
        return max(3.0, min(60.0, 0.5 * maxDelta * 111.0))
    }
}

// MARK: - Mappers (modelos reales → AirspaceFeature)

extension ENAIREFeature {
    // Heurística basada en campos existentes (NO usamos .type/.className).
    fileprivate var inferredKind: AirspaceKind {
        let name    = (properties?.name ?? "").uppercased()
        let ident   = (properties?.identifier ?? "").uppercased()
        let reasons = (properties?.reasons ?? "").uppercased()
        let message = (properties?.message ?? "").uppercased()

        // P / R / D pueden apoyarse también en textos débiles (reasons/message)
        if name.contains(" PROHIB") || ident.hasPrefix("P-") || reasons.contains("PROHIB") || message.contains("PROHIB") {
            return .prohibited
        }
        if name.contains(" RESTR") || ident.hasPrefix("R-") || reasons.contains("RESTR") || message.contains("RESTR") {
            return .restricted
        }
        if name.contains(" DANGER") || name.contains(" PELIG") || ident.hasPrefix("D-")
            || reasons.contains("DANGER") || message.contains("PELIG") {
            return .danger
        }

        // CTR / ATZ / TMA SOLO por señales “fuertes” (nombre/identificador), no por textos débiles
        if name.contains(" CTR") || ident.hasPrefix("CTR") { return .CTR }
        if name.contains(" ATZ") || ident.hasPrefix("ATZ") { return .ATZ }
        if name.contains(" TMA") || ident.hasPrefix("TMA") { return .TMA }

        return .other
    }


    fileprivate var enaireDisplayName: String {
        if let n = properties?.textoPreferido, !n.isEmpty { return n }
        if let n = properties?.name, !n.isEmpty { return n }
        if let n = properties?.identifier, !n.isEmpty { return n }
        return "(Zona)"
    }
    
    func toAirspaceFeatures(source: AirspaceSource) -> [AirspaceFeature] {
        var out: [AirspaceFeature] = []
        switch geometry.coordinates {
        case .polygon(let rings):
            if let exterior = rings.first {
                let coords = exterior.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                out.append(.init(kind: inferredKind, geometry: .polygon(coords), title: enaireDisplayName, source: source))
            }
        case .multiPolygon(let polys):
            for poly in polys {
                if let exterior = poly.first {
                    let coords = exterior.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                    out.append(.init(kind: inferredKind, geometry: .polygon(coords), title: enaireDisplayName, source: source))
                }
            }
        }
        return out
    }
}

extension InfraestructuraFeature {
    fileprivate var infraDisplayName: String { properties.identifier ?? "(Infraestructura)" }
    func toAirspaceFeatures() -> [AirspaceFeature] {
        var out: [AirspaceFeature] = []
        switch geometry.coordinates {
        case .polygon(let rings):
            if let exterior = rings.first {
                let coords = exterior.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                out.append(.init(kind: .other, geometry: .polygon(coords), title: infraDisplayName, source: .infraestructura))
            }
        case .multiPolygon(let polys):
            for poly in polys {
                if let exterior = poly.first {
                    let coords = exterior.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                    out.append(.init(kind: .other, geometry: .polygon(coords), title: infraDisplayName, source: .infraestructura))
                }
            }
        }
        return out
    }
}

// MARK: - Store (vivo + caché + debounce)

@MainActor
final class AirspaceStore: ObservableObject {
    @Published var features: [AirspaceFeature] = []
    private var cache: [String: [AirspaceFeature]] = [:]
    private var lastTask: Task<Void, Never>?
    // LRU de tiles
    var cacheOrder: [String] = []
    let maxCacheTiles: Int = 36

    
    init() {}
    
    func refresh(for region: MKCoordinateRegion) {
        let tileKey = Self.tileKey(for: region.center)
        if let cached = cache[tileKey] {
            self.features = cached
            // LRU
            if let idx = cacheOrder.firstIndex(of: tileKey) { cacheOrder.remove(at: idx) }
            cacheOrder.append(tileKey)
        }
        lastTask?.cancel()
        lastTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 350_000_000) // ~350 ms
            await self.loadLive(region: region)
        }
    }
    
    
    private func loadLive(region: MKCoordinateRegion) async {
        // BBox del viewport (lat/lon min/max) con un pequeño margen para bordes
        let bbox = Self.bbox(for: region, marginFraction: 0.08)
        let tileKey = Self.tileKey(for: region.center)
        
        // Centros de muestreo: centro + 4 cuadrantes
        let samples = Self.viewportSamples(for: region)
        
        // Radio (km) para cada muestra: cubrir cada celda con holgura
        let cellKm = max(3.0, min(60.0, region.approxRadiusKm * 0.75))
        
        do {
            // Lanzamos peticiones en paralelo por muestra y por servicio
            var accR: [ENAIREFeature] = []
            var accU: [ENAIREFeature] = []
            var accM: [ENAIREFeature] = []
            var accI: [InfraestructuraFeature] = []
            
            var hadFailure = false
            var failedSourcesOrdered: [String] = []   // mantiene orden de inserción
            
            await withTaskGroup(of: (Int, Int, Result<Any, Error>).self) { group in
                for (si, sample) in samples.enumerated() {
                    // 👇 Cada closure captura su propia ubicación y radio
                    let cl = sample
                    let km = cellKm

                    // Restricciones
                    group.addTask {
                        do {
                            let arr = try await RestriccionesOverlayService.fetchAround(location: cl, km: km)
                            #if DEBUG
                            print("✅ [R] sample \(si) → \(arr.count) items")
                            #endif
                            return (si, 0, .success(arr as Any))
                        } catch {
                            #if DEBUG
                            print("⚠️ [R] sample \(si) failed:", error.localizedDescription)
                            #endif
                            return (si, 0, .failure(error))
                        }
                    }

                    // Urbano
                    group.addTask {
                        do {
                            let arr = try await UrbanoOverlayService.fetchAround(location: cl, km: km)
                            #if DEBUG
                            print("✅ [U] sample \(si) → \(arr.count) items")
                            #endif
                            return (si, 1, .success(arr as Any))
                        } catch {
                            #if DEBUG
                            print("⚠️ [U] sample \(si) failed:", error.localizedDescription)
                            #endif
                            return (si, 1, .failure(error))
                        }
                    }

                    // Medioambiente
                    group.addTask {
                        do {
                            let arr = try await MedioambienteOverlayService.fetchAround(location: cl, km: km)
                            #if DEBUG
                            print("✅ [M] sample \(si) → \(arr.count) items")
                            #endif
                            return (si, 2, .success(arr as Any))
                        } catch {
                            #if DEBUG
                            print("⚠️ [M] sample \(si) failed:", error.localizedDescription)
                            #endif
                            return (si, 2, .failure(error))
                        }
                    }

                    // Infraestructura
                    group.addTask {
                        do {
                            let arr = try await InfraestructurasOverlayService.fetchAround(location: cl, km: km)
                            #if DEBUG
                            print("✅ [I] sample \(si) → \(arr.count) items")
                            #endif
                            return (si, 3, .success(arr as Any))
                        } catch {
                            #if DEBUG
                            print("⚠️ [I] sample \(si) failed:", error.localizedDescription)
                            #endif
                            return (si, 3, .failure(error))
                        }
                    }
                }

                // … resto igual …
            }

            
            // 🟡 Aviso al usuario si alguna capa falló
            if hadFailure, !failedSourcesOrdered.isEmpty {
                let capas = failedSourcesOrdered.joined(separator: ", ")
                let msg = failedSourcesOrdered.count == 1
                ? "En estos momentos la capa \(capas) no está disponible desde ENAIRE."
                : "En estos momentos las capas \(capas) no están disponibles desde ENAIRE."
                
                #if DEBUG
                print("🚩 Enviando toast: \(msg)")
                #endif
                
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: Notification.Name("ShowToast"),
                        object: nil,
                        userInfo: [
                            "message": msg,
                            "icon": "exclamationmark.triangle.fill"
                        ]
                    )
                }
            }
            
            // Mapear a AirspaceFeature etiquetando la fuente
            let mappedR = accR.flatMap { $0.toAirspaceFeatures(source: .restricciones) }
            let mappedU = accU.flatMap { $0.toAirspaceFeatures(source: .urbano) }
            let mappedM = accM.flatMap { $0.toAirspaceFeatures(source: .medioambiente) }
            let mappedI = accI.flatMap { $0.toAirspaceFeatures() }
            /*
            // Excluir TMA siempre
            let noTMA = (mappedR + mappedU + mappedM + mappedI).filter { $0.kind != .TMA }
            
            // Recortar por BBox del viewport (intersección aproximada por vértices)
            let clipped: [AirspaceFeature] = noTMA.filter { feature in
                return Self.geometryIntersectsBBox(feature.geometry, bbox: bbox)
            }
            */
            // Incluir TMA en overlays (no se filtra aquí)
             let all = (mappedU + mappedM + mappedR + mappedI)
            //Recortar por BBox del viewport (intersección aproximada por vértices)
             let clipped: [AirspaceFeature] = all.filter { feature in
             return Self.geometryIntersectsBBox(feature.geometry, bbox: bbox)
             }
            
            // Deduplicar (clave blanda)
            let unique = Self.dedupFeatures(clipped)
            
            // Cache + publicar (mantener caché previa si hubo fallos y quedó vacío) + LRU
            if !unique.isEmpty || !hadFailure {
                cache[tileKey] = unique

                // LRU: mover/añadir al final
                if let idx = cacheOrder.firstIndex(of: tileKey) { cacheOrder.remove(at: idx) }
                cacheOrder.append(tileKey)

                // Evicción si excede el límite
                if cacheOrder.count > maxCacheTiles {
                    let drop = cacheOrder.count - maxCacheTiles
                    for _ in 0..<drop {
                        let old = cacheOrder.removeFirst()
                        cache.removeValue(forKey: old)
                    }
                }

                features = unique
            } // si unique.isEmpty y hubo fallos, conservamos lo último bueno

            
            #if DEBUG
            let byKind = Dictionary(grouping: unique, by: { $0.kind }).mapValues { $0.count }
            print("✅ AirspaceStore viewport: total \(unique.count) | kinds: \(byKind)")
            #endif
        } catch {
            #if DEBUG
            switch error {
            case let DecodingError.dataCorrupted(ctx):
                print("❌ AirspaceStore viewport DecodingError.dataCorrupted:",
                      "path=\(ctx.codingPath.map{$0.stringValue}.joined(separator: "."))",
                      "reason=\(ctx.debugDescription)")
            case let DecodingError.keyNotFound(key, ctx):
                print("❌ AirspaceStore viewport DecodingError.keyNotFound:",
                      "missing=\(key.stringValue)",
                      "path=\(ctx.codingPath.map{$0.stringValue}.joined(separator: "."))",
                      "reason=\(ctx.debugDescription)")
            case let DecodingError.typeMismatch(type, ctx):
                print("❌ AirspaceStore viewport DecodingError.typeMismatch:",
                      "type=\(type)",
                      "path=\(ctx.codingPath.map{$0.stringValue}.joined(separator: "."))",
                      "reason=\(ctx.debugDescription)")
            case let DecodingError.valueNotFound(type, ctx):
                print("❌ AirspaceStore viewport DecodingError.valueNotFound:",
                      "type=\(type)",
                      "path=\(ctx.codingPath.map{$0.stringValue}.joined(separator: "."))",
                      "reason=\(ctx.debugDescription)")
            default:
                print("❌ AirspaceStore viewport error:", error.localizedDescription)
            }
            #endif
        }
    }


    
    
    private static func tileKey(for c: CLLocationCoordinate2D) -> String {
        // Redondeo a 2 decimales (~1.1 km).
        let lat = (c.latitude * 100).rounded() / 100
        let lon = (c.longitude * 100).rounded() / 100
        return "\(lat),\(lon)"
    }
}

// MARK: - Capa MapContent

// MARK: - Capa MapContent

// MARK: - Capa MapContent (diagnóstico: sin logs dentro del body)

// MARK: - Capa MapContent (contorno-only, sin relleno; versión robusta)

// MARK: - Capa MapContent (robusta + sin relleno)

// MARK: - Capa MapContent (robusta, sin relleno)

struct AirspaceOverlaysLayer: MapContent {
    var enabled: Bool
    var region: MKCoordinateRegion
    var features: [AirspaceFeature]
    /// Capas visibles (por defecto todas)
    var visibleSources: Set<AirspaceSource> = Set(AirspaceSource.allCases)

    var body: some MapContent {
        // Filtrado explícito y tipado claro (evita [] sin tipo)
        let items: [AirspaceFeature] = enabled
        ? features.filter { visibleSources.contains($0.source) }
            : [AirspaceFeature]()

        // ForEach con Identifiable y sin declaraciones dentro del builder
        ForEach(items) { f in
            switch f.geometry {

            case .polygon(let coords):
                // Contorno como polilínea (sin relleno posible)
                let style = AirspaceStyle.style(for: f.kind)
                MapPolyline(coordinates: closedRing(coords))
                    .stroke(style.halo, lineWidth: style.lineWidth + 4)
                MapPolyline(coordinates: closedRing(coords))
                    .stroke(style.stroke, lineWidth: style.lineWidth)

            case .polyline(let coords):
                let style = AirspaceStyle.style(for: f.kind)
                MapPolyline(coordinates: coords)
                    .stroke(style.halo, lineWidth: style.lineWidth + 3)
                MapPolyline(coordinates: coords)
                    .stroke(style.stroke, lineWidth: style.lineWidth)
            }
        }
    }

    // Helper fuera del builder (no introduce '()' en el contenido)
    private func closedRing(_ coords: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        guard let first = coords.first, let last = coords.last else { return coords }
        if first.latitude == last.latitude && first.longitude == last.longitude {
            return coords
        } else {
            var c = coords
            c.append(first)
            return c
        }
    }
}


// === BEGIN INSERT: Viewport helpers (BBox, samples, intersect, dedup) ===
private extension AirspaceStore {
    static func bbox(for region: MKCoordinateRegion, marginFraction: Double = 0.08)
    -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        let latPad = region.span.latitudeDelta * marginFraction
        let lonPad = region.span.longitudeDelta * marginFraction
        let minLat = region.center.latitude - region.span.latitudeDelta/2 - latPad
        let maxLat = region.center.latitude + region.span.latitudeDelta/2 + latPad
        let minLon = region.center.longitude - region.span.longitudeDelta/2 - lonPad
        let maxLon = region.center.longitude + region.span.longitudeDelta/2 + lonPad
        return (minLat, maxLat, minLon, maxLon)
    }

    static func viewportSamples(for region: MKCoordinateRegion) -> [CLLocation] {
        let c = region.center
        let dLat = region.span.latitudeDelta / 4.0
        let dLon = region.span.longitudeDelta / 4.0
        return [
            CLLocation(latitude: c.latitude, longitude: c.longitude),
            CLLocation(latitude: c.latitude + dLat, longitude: c.longitude - dLon), // NW
            CLLocation(latitude: c.latitude + dLat, longitude: c.longitude + dLon), // NE
            CLLocation(latitude: c.latitude - dLat, longitude: c.longitude - dLon), // SW
            CLLocation(latitude: c.latitude - dLat, longitude: c.longitude + dLon), // SE
        ]
    }

    // Bounding box de una geometría (rápido)
    static func geometryBounds(_ geom: AirspaceGeometry)
    -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)? {
        switch geom {
        case .polygon(let pts), .polyline(let pts):
            guard let first = pts.first else { return nil }
            var minLat = first.latitude, maxLat = first.latitude
            var minLon = first.longitude, maxLon = first.longitude
            for p in pts {
                if p.latitude  < minLat { minLat = p.latitude }
                if p.latitude  > maxLat { maxLat = p.latitude }
                if p.longitude < minLon { minLon = p.longitude }
                if p.longitude > maxLon { maxLon = p.longitude }
            }
            return (minLat, maxLat, minLon, maxLon)
        }
    }

    // Overlap de dos BBoxes
    static func bboxesOverlap(
        _ a: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double),
        _ b: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)
    ) -> Bool {
        // Se solapan si hay intersección en ambos ejes
        return !(a.minLat > b.maxLat || a.maxLat < b.minLat || a.minLon > b.maxLon || a.maxLon < b.minLon)
    }

    // Intersección con BBox del viewport: primero bbox-vs-bbox, luego vértices dentro como fallback
    static func geometryIntersectsBBox(
        _ geom: AirspaceGeometry,
        bbox: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)
    ) -> Bool {
        if let gb = geometryBounds(geom), bboxesOverlap(gb, bbox) { return true }
        switch geom {
        case .polygon(let pts), .polyline(let pts):
            for p in pts {
                if p.latitude >= bbox.minLat && p.latitude <= bbox.maxLat &&
                   p.longitude >= bbox.minLon && p.longitude <= bbox.maxLon {
                    return true
                }
            }
            return false
        }
    }

    static func dedupFeatures(_ features: [AirspaceFeature]) -> [AirspaceFeature] {
        var seen = Set<String>()
        var out: [AirspaceFeature] = []
        out.reserveCapacity(features.count)
        for f in features {
            let key: String = {
                switch f.geometry {
                case .polygon(let pts):
                    let head = pts.first.map { "\($0.latitude.rounded(to: 5))|\($0.longitude.rounded(to: 5))" } ?? "_"
                    return "\(f.source.rawValue)|\(f.title)|poly|\(pts.count)|\(head)"
                case .polyline(let pts):
                    let head = pts.first.map { "\($0.latitude.rounded(to: 5))|\($0.longitude.rounded(to: 5))" } ?? "_"
                    return "\(f.source.rawValue)|\(f.title)|line|\(pts.count)|\(head)"
                }
            }()
            if !seen.contains(key) {
                seen.insert(key)
                out.append(f)
            }
        }
        return out
    }
}

private extension Double {
    func rounded(to decimals: Int) -> Double {
        let p = pow(10.0, Double(decimals))
        return (self * p).rounded() / p
    }
}
// === END INSERT ===


