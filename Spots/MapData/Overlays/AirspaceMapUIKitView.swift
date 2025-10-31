//
//  AirspaceMapUIKitView.swift
//  Spots
//
//  MKMapView + overlays + pins + user dot.
//  - LOD (far/mid/near) para reducir overlays
//  - Debounce adaptativo por zoom
//  - Simplificación Douglas–Peucker con caché por LOD
//

import SwiftUI
import MapKit
import CoreLocation

@inline(__always) private func zOrder(_ s: AirspaceSource) -> Int {
    // Orden de abajo a arriba:
    // 0: Urbano, 1: Medioambiente, 2: Restricciones (Aero), 3: Infraestructuras
    switch s {
    case .urbano:          return 0
    case .medioambiente:   return 1
    case .restricciones:   return 2
    case .infraestructura: return 3
    }
}


// MARK: - Pin de Spot
final class SpotMKAnnotation: NSObject, MKAnnotation {
    let id: String
    let title: String?
    let coordinate: CLLocationCoordinate2D
    let ratingMean: Double?
    let ratingCount: Int?
    
    init(id: String,
         title: String?,
         coordinate: CLLocationCoordinate2D,
         ratingMean: Double? = nil,
         ratingCount: Int? = nil) {
        self.id = id
        self.title = title
        self.coordinate = coordinate
        self.ratingMean = ratingMean
        self.ratingCount = ratingCount
        super.init()
    }
}

// MARK: - Representable
struct AirspaceMapUIKitView: UIViewRepresentable {
    
    struct Spot {
        let id: String
        let name: String?
        let coordinate: CLLocationCoordinate2D
        let ratingMean: Double?
        let ratingCount: Int?
    }
    
    @Binding var region: MKCoordinateRegion
    let features: [AirspaceFeature]
    let visibleSources: Set<AirspaceSource>
    let overlaysEnabled: Bool
    let spots: [Spot]
    let mapType: MKMapType
    let onSelectSpot: (String) -> Void
    let onRegionDidChange: (MKCoordinateRegion) -> Void
    let onMapFullyRendered: () -> Void   // ⬅️ nuevo callback
    
    let centerOnUserTick: Int
    let fallbackUser: CLLocationCoordinate2D?
    let centerTarget: CLLocationCoordinate2D?
    let forceFullReloadTick: Int
    
    
    init(region: Binding<MKCoordinateRegion>,
         mapType: MKMapType,
         features: [AirspaceFeature],
         visibleSources: Set<AirspaceSource>,
         overlaysEnabled: Bool,
         spots: [Spot],
         onSelectSpot: @escaping (String) -> Void,
         onRegionDidChange: @escaping (MKCoordinateRegion) -> Void,
         onMapFullyRendered: @escaping () -> Void,
         centerOnUserTick: Int,
         fallbackUser: CLLocationCoordinate2D?,
         centerTarget: CLLocationCoordinate2D?,
         forceFullReloadTick: Int) {
        self._region = region
        self.mapType = mapType
        self.features = features
        self.visibleSources = visibleSources
        self.overlaysEnabled = overlaysEnabled
        self.spots = spots
        self.onSelectSpot = onSelectSpot
        self.onRegionDidChange = onRegionDidChange
        self.onMapFullyRendered = onMapFullyRendered   // ⬅️ nuevo
        self.centerOnUserTick = centerOnUserTick
        self.fallbackUser = fallbackUser
        self.centerTarget = centerTarget
        self.forceFullReloadTick = forceFullReloadTick
    }
    
    
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.mapType = mapType
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false
        
        map.showsUserLocation = true
        map.setUserTrackingMode(.follow, animated: false)
        DispatchQueue.main.async { map.setUserTrackingMode(.none, animated: false) }
        
        let target = map.userLocation.location?.coordinate ?? fallbackUser ?? region.center
        if overlaysEnabled {
            let reg = MKCoordinateRegion(center: target, latitudinalMeters: 2000, longitudinalMeters: 2000)
            map.setRegion(reg, animated: false)
        } else {
            map.setRegion(region, animated: false)
        }
        
        DispatchQueue.main.async { context.coordinator.fireRegionChangeNow(map) }
        context.coordinator.reload(map: map,
                                   region: region,
                                   features: features,
                                   visibleSources: visibleSources,
                                   overlaysEnabled: overlaysEnabled,
                                   spots: spots,
                                   forceFullReloadTick: forceFullReloadTick)
        return map
    }
    
    func updateUIView(_ map: MKMapView, context: Context) {
        var skipReload = false
        // --- FIX: no devolvemos cuando overlays están apagados ---
            if !overlaysEnabled {
                if !map.overlays.isEmpty {
                    map.removeOverlays(map.overlays)
                }
                // No return: dejamos que se actualice mapType, recentrados, etc.
            } else {
                if features.isEmpty && !map.overlays.isEmpty {
                    skipReload = true
                }
            }

            // Siempre permitir cambiar el tipo de mapa:
            if map.mapType != mapType { map.mapType = mapType }

            // Sólo recargar overlays si están encendidos:
            if overlaysEnabled && !skipReload {
                context.coordinator.reload(map: map,
                                           region: region,
                                           features: features,
                                           visibleSources: visibleSources,
                                           overlaysEnabled: overlaysEnabled,
                                           spots: spots,
                                           forceFullReloadTick: forceFullReloadTick)
            }

            // Mantén el resto tal cual (zoom inicial, recentrados, user location, etc.)
            if overlaysEnabled && !context.coordinator.didApplyInitialZoom {
                context.coordinator.didApplyInitialZoom = true
                let reg = MKCoordinateRegion(center: region.center, latitudinalMeters: 2000, longitudinalMeters: 2000)
                map.setRegion(reg, animated: false)
            }
        
        if centerOnUserTick != context.coordinator.lastCenterTick {
            context.coordinator.lastCenterTick = centerOnUserTick
            let target = centerTarget
            ?? map.userLocation.location?.coordinate
            ?? fallbackUser
            ?? region.center
            let reg = MKCoordinateRegion(center: target, latitudinalMeters: 2000, longitudinalMeters: 2000)
            map.setRegion(reg, animated: true)
            // Fuera del ciclo de updateUIView para evitar "Publishing changes..."
            DispatchQueue.main.async {
                context.coordinator.fireRegionChangeImmediately(map)
            }
        }
        
        
        let status = CLLocationManager.authorizationStatus()
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            if !map.showsUserLocation { map.showsUserLocation = true }
            else if map.userLocation.location == nil {
                map.showsUserLocation = false
                DispatchQueue.main.async { map.showsUserLocation = true }
            }
        }
        
        if context.coordinator.lastOverlaysEnabled != overlaysEnabled {
            context.coordinator.lastOverlaysEnabled = overlaysEnabled
            if overlaysEnabled {
                if !context.coordinator.didFireInitialFetch {
                    DispatchQueue.main.async {
                        context.coordinator.fireRegionChangeNow(map)
                    }
                } else {
                    DispatchQueue.main.async {
                        context.coordinator.fireRegionChangeImmediately(map)
                    }
                }
            }
        }
        
    }
    
    // MARK: - Coordinator
    final class Coordinator: NSObject, MKMapViewDelegate {
        
        private var parent: AirspaceMapUIKitView
        var lastCenterTick: Int = 0
        var didApplyInitialZoom = false
        var lastForceTick: Int = -1
        var isResetInFlight: Bool = false
        private var regionDebounceWork: DispatchWorkItem?
        private var regionDebounceInterval: TimeInterval = 0.30
        var didFireInitialFetch = false
        private var didFireAfterFirstRender = false
        fileprivate var lastOverlaysEnabled: Bool? = nil
        
        // Caché de simplificaciones por LOD
        private var dpCache: [String: [CLLocationCoordinate2D]] = [:]
        
        // LRU para dpCache
        private var dpCacheOrder: [String] = []
        private let maxDPCacheEntries = 1200
        
        // LOD
        private enum LOD: String { case far, mid, near }
        private func latMeters(for region: MKCoordinateRegion) -> Double {
            return region.span.latitudeDelta * 111000.0
        }
        private func lod(for region: MKCoordinateRegion) -> LOD {
            let m = latMeters(for: region)
            if m >= 150000 { return .far }
            if m >= 35000  { return .mid }
            return .near
        }
        private func tolerance(for level: LOD, at latitude: Double) -> Double {
            switch level {
                //Subietos valorsndi  ganamos rendimiento pero perdemos fidelidad y viceversa
            case .far: return 120.0
            case .mid: return 40.0
            case .near: return 3.0
            }
        }
        
        // Cap adaptativo por zoom (nº de FEATURES)
        private func featureCap(for level: LOD, in region: MKCoordinateRegion) -> Int {
            switch level {
            case .far:  return 400    // lejos → menos
            case .mid:  return 800
            case .near: return 1600   // cerca → más detalle
            }
        }
        
        
        // Pin scaling
        private let baseSize = CGSize(width: 240, height: 270)
        private let baseOffsetY: CGFloat = -100
        private func pinScale(for region: MKCoordinateRegion) -> CGFloat {
            let m = latMeters(for: region)
            if m >= 400000 { return 0.20 }
            if m >= 250000 { return 0.35 }
            if m >= 100000 { return 0.50 }
            if m >=  50000 { return 0.70 }
            if m >=  10000 { return 0.85 }
            if m >=   1500 { return 1.00 }
            return 1.15
        }
        private func applyScale(_ scale: CGFloat, to view: MKAnnotationView) {
            view.transform = CGAffineTransform(scaleX: scale, y: scale)
            view.centerOffset = CGPoint(x: 0, y: baseOffsetY * scale)
        }
        private func adjustPinScales(for mapView: MKMapView) {
            let scale = pinScale(for: mapView.region)
            for ann in mapView.annotations where !(ann is MKUserLocation) {
                if let v = mapView.view(for: ann) {
                    UIView.animate(withDuration: 0.12) { self.applyScale(scale, to: v) }
                }
            }
        }
        
        // DP helpers
        private func metersXY(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, latRef: Double) -> (dx: Double, dy: Double) {
            let mLat = 111000.0
            let mLon = 111000.0 * cos(latRef * .pi / 180.0)
            let dx = (b.longitude - a.longitude) * mLon
            let dy = (b.latitude  - a.latitude ) * mLat
            return (dx, dy)
        }
        private func perpDistMeters(p: CLLocationCoordinate2D, a: CLLocationCoordinate2D, b: CLLocationCoordinate2D, latRef: Double) -> Double {
            let (dx, dy) = metersXY(a, b, latRef: latRef)
            if dx == 0 && dy == 0 {
                let (_, dyp) = metersXY(a, p, latRef: latRef)
                return abs(dyp)
            }
            let (px, py) = metersXY(a, p, latRef: latRef)
            let areaTwice = abs(dy * px - dx * py)
            let base = hypot(dx, dy)
            return areaTwice / base
        }
        private func douglasPeucker(_ pts: [CLLocationCoordinate2D], epsMeters: Double) -> [CLLocationCoordinate2D] {
            guard pts.count >= 3 else { return pts }
            let latRef = pts[pts.count/2].latitude
            var keep = [Bool](repeating: false, count: pts.count)
            keep[0] = true; keep[pts.count - 1] = true
            func simplify(_ s: Int, _ e: Int) {
                if e <= s + 1 { return }
                var maxDist = 0.0
                var idx = 0
                let A = pts[s], B = pts[e]
                for i in (s+1)..<e {
                    let d = perpDistMeters(p: pts[i], a: A, b: B, latRef: latRef)
                    if d > maxDist { maxDist = d; idx = i }
                }
                if maxDist > epsMeters {
                    keep[idx] = true
                    simplify(s, idx)
                    simplify(idx, e)
                }
            }
            simplify(0, pts.count - 1)
            var out: [CLLocationCoordinate2D] = []
            out.reserveCapacity(pts.count)
            for i in 0..<pts.count where keep[i] { out.append(pts[i]) }
            return out
        }
        
        //SIMPLIFICAR POLIGONOS
        /*private func simplify(coords: [CLLocationCoordinate2D], level: LOD, isPolygon: Bool, baseKey: String) -> [CLLocationCoordinate2D] {
            if coords.count < 5 { return coords }
            let key = baseKey + "|lod:" + level.rawValue
            
            // Cache hit → refresca LRU
            if let cached = dpCache[key] {
                if let idx = dpCacheOrder.firstIndex(of: key) { dpCacheOrder.remove(at: idx) }
                dpCacheOrder.append(key)
                return cached
            }
            
            let eps = tolerance(for: level, at: coords[coords.count/2].latitude)
            var simplified = douglasPeucker(coords, epsMeters: eps)
            
            if isPolygon {
                if let first = simplified.first, let last = simplified.last,
                   (first.latitude != last.latitude || first.longitude != last.longitude) {
                    simplified.append(first)
                }
                if simplified.count < 4 { simplified = coords }
            } else {
                if simplified.count < 2 { simplified = coords }
            }
            
            // Insertar en caché + LRU
            dpCache[key] = simplified
            dpCacheOrder.append(key)
            
            // Evicción LRU si nos pasamos del límite
            if dpCacheOrder.count > maxDPCacheEntries {
                let drop = dpCacheOrder.count - maxDPCacheEntries
                for _ in 0..<drop {
                    let old = dpCacheOrder.removeFirst()
                    dpCache.removeValue(forKey: old)
                }
            }
            
            return simplified
        }*/
        
        //SIN SIMPLIFICAR POLIGONOS
        
        private func simplify(coords: [CLLocationCoordinate2D], level: LOD, isPolygon: Bool, baseKey: String) -> [CLLocationCoordinate2D] {
            if coords.count < 5 { return coords }
            let key = baseKey + "|nosimplify"   // clave estable: sin depender del LOD

            // Cache hit → refresca LRU
            if let cached = dpCache[key] {
                if let idx = dpCacheOrder.firstIndex(of: key) { dpCacheOrder.remove(at: idx) }
                dpCacheOrder.append(key)
                return cached
            }

            // SIN Douglas–Peucker: usamos los vértices originales
            var simplified = coords

            if isPolygon {
                if let first = simplified.first, let last = simplified.last,
                   (first.latitude != last.latitude || first.longitude != last.longitude) {
                    simplified.append(first)
                }
                if simplified.count < 4 { simplified = coords }
            } else {
                if simplified.count < 2 { simplified = coords }
            }

            // Insertar en caché + LRU
            dpCache[key] = simplified
            dpCacheOrder.append(key)

            // Evicción LRU si nos pasamos del límite
            if dpCacheOrder.count > maxDPCacheEntries {
                let drop = dpCacheOrder.count - maxDPCacheEntries
                for _ in 0..<drop {
                    let old = dpCacheOrder.removeFirst()
                    dpCache.removeValue(forKey: old)
                }
            }

            return simplified
        }

        
        
        // 🆕 Huella geométrica estable basada en los coords ORIGINALES (no simplificados)
        @inline(__always)
        private func geomFingerprint(_ coords: [CLLocationCoordinate2D]) -> String {
            var hasher = Hasher()
            for p in coords {
                hasher.combine(Int64((p.latitude  * 1e6).rounded()))
                hasher.combine(Int64((p.longitude * 1e6).rounded()))
            }
            return String(hasher.finalize(), radix: 36)
        }
        
        init(_ parent: AirspaceMapUIKitView) { self.parent = parent }
        
        fileprivate func fireRegionChangeNow(_ mapView: MKMapView) {
            guard !didFireInitialFetch else { return }
            didFireInitialFetch = true
#if DEBUG
            if FeatureFlags.oracleEnabled {
                let tag = "map#fireNow#\(Int(Date().timeIntervalSince1970))"
                AirspaceOracle.shared.regionChanged(tag: tag, region: mapView.region)
            }
#endif
            parent.onRegionDidChange(mapView.region)
        }
        fileprivate func fireRegionChangeImmediately(_ mapView: MKMapView) {
#if DEBUG
            if FeatureFlags.oracleEnabled {
                let tag = "map#fireImmediate#\(Int(Date().timeIntervalSince1970))"
                AirspaceOracle.shared.regionChanged(tag: tag, region: mapView.region)
            }
#endif
            parent.onRegionDidChange(mapView.region)
        }
        
        // MARK: - Coordinator methods
        
        // 🆕 Utils viewport/bbox
        @inline(__always)
        private func bbox(of region: MKCoordinateRegion) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
            let minLat = region.center.latitude  - region.span.latitudeDelta / 2.0
            let maxLat = region.center.latitude  + region.span.latitudeDelta / 2.0
            let minLon = region.center.longitude - region.span.longitudeDelta / 2.0
            let maxLon = region.center.longitude + region.span.longitudeDelta / 2.0
            return (minLat, maxLat, minLon, maxLon)
        }
        
        @inline(__always)
        private func bbox(of geometry: AirspaceGeometry) -> (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
            switch geometry {
            case .polygon(let coords):
                var minLat = Double.greatestFiniteMagnitude, maxLat = -Double.greatestFiniteMagnitude
                var minLon = Double.greatestFiniteMagnitude, maxLon = -Double.greatestFiniteMagnitude
                for c in coords {
                    minLat = min(minLat, c.latitude);  maxLat = max(maxLat, c.latitude)
                    minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
                }
                return (minLat, maxLat, minLon, maxLon)
            case .polyline(let coords):
                var minLat = Double.greatestFiniteMagnitude, maxLat = -Double.greatestFiniteMagnitude
                var minLon = Double.greatestFiniteMagnitude, maxLon = -Double.greatestFiniteMagnitude
                for c in coords {
                    minLat = min(minLat, c.latitude);  maxLat = max(maxLat, c.latitude)
                    minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
                }
                return (minLat, maxLat, minLon, maxLon)
            }
        }
        
        @inline(__always)
        private func intersects(_ a: (Double,Double,Double,Double), _ b: (Double,Double,Double,Double)) -> Bool {
            let (aMinLat, aMaxLat, aMinLon, aMaxLon) = a
            let (bMinLat, bMaxLat, bMinLon, bMaxLon) = b
            // Intersección AABB 2D
            return !(aMaxLat < bMinLat || aMinLat > bMaxLat || aMaxLon < bMinLon || aMinLon > bMaxLon)
        }
        
        // Convierte un MKCoordinateRegion a MKMapRect
        private func mapRect(for region: MKCoordinateRegion) -> MKMapRect {
            let topLeft = CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta/2.0,
                                                 longitude: region.center.longitude - region.span.longitudeDelta/2.0)
            let bottomRight = CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta/2.0,
                                                     longitude: region.center.longitude + region.span.longitudeDelta/2.0)
            let p1 = MKMapPoint(topLeft)
            let p2 = MKMapPoint(bottomRight)
            let rect = MKMapRect(x: min(p1.x, p2.x),
                                 y: min(p1.y, p2.y),
                                 width: abs(p1.x - p2.x),
                                 height: abs(p1.y - p2.y))
            return rect
        }
        
        // Poda los overlays cuyo boundingMapRect ya no intersecta el viewport (con margen)
        private func pruneOverlaysOutsideViewport(_ map: MKMapView,
                                                  region: MKCoordinateRegion,
                                                  overscanMeters: Double) {
            var vp = mapRect(for: region)
            // ensancha un poco el rectángulo para evitar popping al borde
            let metersPerPoint = MKMetersPerMapPointAtLatitude(region.center.latitude)
            let pad = overscanMeters / metersPerPoint
            vp = vp.insetBy(dx: -pad, dy: -pad)
            
            let toRemove = map.overlays.filter { overlay in
                !overlay.boundingMapRect.intersects(vp)
            }
            if !toRemove.isEmpty { map.removeOverlays(toRemove) }
        }
        
        
        func reload(map: MKMapView,
                    region: MKCoordinateRegion,
                    features: [AirspaceFeature],
                    visibleSources: Set<AirspaceSource>,
                    overlaysEnabled: Bool,
                    spots: [Spot],
                    forceFullReloadTick: Int) {
            guard overlaysEnabled else {
                map.removeOverlays(map.overlays)
                return
            }
            let items = features.filter { visibleSources.contains($0.source) }
            .sorted { zOrder($0.source) < zOrder($1.source) }
            let level = lod(for: map.region)
            // Poda adaptativa por zoom (cap por nº de features)
            let featureLimit = featureCap(for: level, in: map.region)
            var remaining = featureLimit
            var hitCap = false
            
            
#if DEBUG
            // 🔢 Pintados (se llenará en el bucle)
            var paintBySourceKind: [String:Int] = [:]
            @inline(__always) func sk(_ s: AirspaceSource, _ k: AirspaceKind) -> String { "\(s.rawValue).\(k.rawValue)" }
            
            // 🆕 Esperados EN VIEWPORT (recorte a pantalla)
            let vp = bbox(of: map.region)
            var viewportBySourceKind: [String:Int] = [:]
            @inline(__always) func pk(_ s: AirspaceSource, _ k: AirspaceKind) -> String { "\(s.rawValue).\(k.rawValue)" }
            
            // Filtramos por intersección AABB de la geometría con el viewport
            for f in items {
                if remaining <= 0 { hitCap = true; break }
                let gbb = bbox(of: f.geometry)
                if intersects( (vp.minLat, vp.maxLat, vp.minLon, vp.maxLon),
                               (gbb.minLat, gbb.maxLat, gbb.minLon, gbb.maxLon) ) {
                    viewportBySourceKind[pk(f.source, f.kind), default: 0] += 1
                }
            }
            
            if FeatureFlags.oracleEnabled {
                AirspaceOracle.shared.viewportExpected(bySourceKind: viewportBySourceKind)
            }
#endif
            
            var existingTitles = Set(map.overlays.compactMap { $0.title ?? nil })
            
            var addedTitles: [String] = []
            ASDBG.log("MAP", "reload start items=\(items.count) level=\(level) region=\(map.region.shortDesc)")
            if lastForceTick != forceFullReloadTick {
                ASDBG.log("MAP", "soft prune overlays tick=\(forceFullReloadTick)")
                lastForceTick = forceFullReloadTick
                pruneOverlaysOutsideViewport(map, region: map.region, overscanMeters: 1500)
                existingTitles = Set(map.overlays.compactMap { $0.title ?? nil })
            }
            
            
            
            // Overlays
            for f in items {
#if DEBUG
                paintBySourceKind[sk(f.source, f.kind), default: 0] += 1
#endif
                switch f.geometry {
                case .polygon(var coords):
                    // 1) Cierra anillo original de forma segura
                    if let first = coords.first, let last = coords.last,
                       (first.latitude != last.latitude || first.longitude != last.longitude) {
                        coords.append(first)
                    }
                    
                    // 2) Huella estable sobre coords ORIGINALES (no simplificados)
                    let gid = geomFingerprint(coords)
                    let base = "poly|\(f.source.rawValue)|\(f.kind.rawValue)|gid:\(gid)"
                    
                    // 3) Simplifica SOLO para líneas (halo+stroke)
                    let simp = simplify(coords: coords, level: level, isPolygon: true, baseKey: base)
                    
                    // 4) Near/Mid: fill SIEMPRE con coords ORIGINALES (evita degeneraciones)
                    func addFillIfNeeded(using ring: inout [CLLocationCoordinate2D]) {
                        let tf = "fill|\(f.source.rawValue)|\(f.kind.rawValue)|gid:\(gid)|cnt:\(ring.count)"
                        if !existingTitles.contains(tf) {
                            let poly = MKPolygon(coordinates: &ring, count: ring.count)
                            poly.title = tf
                            map.addOverlay(poly, level: .aboveRoads)
                            addedTitles.append(tf) // contabiliza también en near
                        }
                    }
                    
                    switch level {
                    case .far:
                        // sin fill en far: solo stroke simplificado
                        var s = simp
                        let ts = "stroke|\(f.source.rawValue)|\(f.kind.rawValue)|gid:\(gid)|cnt:\(s.count)"
                        if !existingTitles.contains(ts) {
                            let stroke = MKPolyline(coordinates: &s, count: s.count)
                            stroke.title = ts
                            map.addOverlay(stroke, level: .aboveRoads)
                            addedTitles.append(ts)
                        }
                        
                    case .mid:
                        // fill con anillo original + stroke simplificado
                        var ringFill = coords
                        addFillIfNeeded(using: &ringFill)
                        
                        var s2 = simp
                        let ts = "stroke|\(f.source.rawValue)|\(f.kind.rawValue)|gid:\(gid)|cnt:\(s2.count)"
                        if !existingTitles.contains(ts) {
                            let stroke = MKPolyline(coordinates: &s2, count: s2.count)
                            stroke.title = ts
                            map.addOverlay(stroke, level: .aboveRoads)
                            addedTitles.append(ts)
                        }
                        
                    case .near:
                        // fill con anillo original + halo/ stroke simplificados
                        var ringFill = coords
                        addFillIfNeeded(using: &ringFill)
                        
                        var sH = simp
                        let th = "halo|\(f.source.rawValue)|\(f.kind.rawValue)|gid:\(gid)|cnt:\(sH.count)"
                        if !existingTitles.contains(th) {
                            let halo = MKPolyline(coordinates: &sH, count: sH.count)
                            halo.title = th
                            map.addOverlay(halo, level: .aboveRoads)
                            addedTitles.append(th)
                        }
                        
                        var s = simp
                        let ts = "stroke|\(f.source.rawValue)|\(f.kind.rawValue)|gid:\(gid)|cnt:\(s.count)"
                        if !existingTitles.contains(ts) {
                            let stroke = MKPolyline(coordinates: &s, count: s.count)
                            stroke.title = ts
                            map.addOverlay(stroke, level: .aboveRoads)
                            addedTitles.append(ts)
                        }
                    }
                    
                    
                    
                case .polyline(let coords0):
                    // 🆕 Huella geométrica estable
                    let gid = geomFingerprint(coords0)
                    // 🆕 Clave de caché por-feature (incluye gid)
                    let base = "line|\(f.source.rawValue)|\(f.kind.rawValue)|gid:\(gid)"
                    let simp = simplify(coords: coords0, level: level, isPolygon: false, baseKey: base)
                    
                    switch level {
                    case .far, .mid:
                        var s = simp
                        let ts = "stroke|\(f.source.rawValue)|\(f.kind.rawValue)|gid:\(gid)|cnt:\(s.count)"
                        if !existingTitles.contains(ts) {
                            let stroke = MKPolyline(coordinates: &s, count: s.count)
                            stroke.title = ts
                            map.addOverlay(stroke, level: .aboveRoads)
                            addedTitles.append(ts)
                        }
                    case .near:
                        var sH = simp
                        let th = "halo|\(f.source.rawValue)|\(f.kind.rawValue)|gid:\(gid)|cnt:\(sH.count)"
                        if !existingTitles.contains(th) {
                            let halo = MKPolyline(coordinates: &sH, count: sH.count)
                            halo.title = th
                            map.addOverlay(halo, level: .aboveRoads)
                            addedTitles.append(th)
                        }
                        var s = simp
                        let ts = "stroke|\(f.source.rawValue)|\(f.kind.rawValue)|gid:\(gid)|cnt:\(s.count)"
                        if !existingTitles.contains(ts) {
                            let stroke = MKPolyline(coordinates: &s, count: s.count)
                            stroke.title = ts
                            map.addOverlay(stroke, level: .aboveRoads)
                            // (igual que antes, aquí no añadíamos el stroke al sample en near; lo dejamos igual)
                        }
                    }
                    remaining -= 1   // contamos 1 feature, independientemente de overlays que genere
                    
                }
            }
            
            // Anotaciones (diff por id)
            let existingSpotAnns = map.annotations.compactMap { $0 as? SpotMKAnnotation }
            let existingById = Dictionary(uniqueKeysWithValues: existingSpotAnns.map { ($0.id, $0) })
            let targetById = Dictionary(uniqueKeysWithValues: spots.map { ($0.id, $0) })
            
            // remove
            let toDelete = existingSpotAnns.filter { targetById[$0.id] == nil }
            if !toDelete.isEmpty { map.removeAnnotations(toDelete) }
            
            // add
            let toAdd = spots.filter { existingById[$0.id] == nil }
            for s in toAdd {
                let ann = SpotMKAnnotation(id: s.id,
                                           title: s.name,
                                           coordinate: s.coordinate,
                                           ratingMean: s.ratingMean,
                                           ratingCount: s.ratingCount)
                map.addAnnotation(ann)
            }
            
            // update
            let hostTag = 999_001
            for (id, spot) in targetById {
                guard let ann = existingById[id] else { continue }
                if ann.coordinate.latitude != spot.coordinate.latitude || ann.coordinate.longitude != spot.coordinate.longitude {
                    map.removeAnnotation(ann)
                    let newAnn = SpotMKAnnotation(id: spot.id,
                                                  title: spot.name,
                                                  coordinate: spot.coordinate,
                                                  ratingMean: spot.ratingMean,
                                                  ratingCount: spot.ratingCount)
                    map.addAnnotation(newAnn)
                    continue
                }
                if let v = map.view(for: ann) {
                    if let old = v.viewWithTag(hostTag) { old.removeFromSuperview() }
                    let host = UIHostingController(
                        rootView: SpotPinView(
                            title: spot.name ?? "",
                            ratingMean: spot.ratingMean,
                            ratingCount: spot.ratingCount,
                            onInfo: { [weak self] in self?.parent.onSelectSpot(spot.id) },
                            onTapMain: { [weak map] in
                                guard let map = map else { return }
                                let reg = MKCoordinateRegion(center: spot.coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
                                map.setRegion(reg, animated: true)
                            }
                        )
                    )
                    host.view.backgroundColor = .clear
                    host.view.translatesAutoresizingMaskIntoConstraints = false
                    host.view.tag = hostTag
                    v.addSubview(host.view)
                    NSLayoutConstraint.activate([
                        host.view.leadingAnchor.constraint(equalTo: v.leadingAnchor),
                        host.view.trailingAnchor.constraint(equalTo: v.trailingAnchor),
                        host.view.topAnchor.constraint(equalTo: v.topAnchor),
                        host.view.bottomAnchor.constraint(equalTo: v.bottomAnchor)
                    ])
                }
            }
            UIView.performWithoutAnimation { adjustPinScales(for: map) }
#if DEBUG
            if FeatureFlags.oracleEnabled {
                AirspaceOracle.shared.mapPainted(bySourceKind: paintBySourceKind, overlaysAdded: addedTitles.count)
            }
#endif
            if hitCap {
                ASDBG.log("MAP", "feature cap hit level=\(level) cap=\(featureLimit) items=\(items.count)")
            }
            
            ASDBG.log("MAP", "reload end added=\(addedTitles.count) sample=\(addedTitles.prefix(3))")
        }
        
        // MARK: - MKMapViewDelegate
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let newRegion = mapView.region
            // Evita "Publishing changes..." moviendo la mutación del Binding fuera del ciclo de render del delegate
            DispatchQueue.main.async { [weak self] in
                self?.parent.region = newRegion
            }
            
            adjustPinScales(for: mapView)
            
            let m = latMeters(for: mapView.region)
            let target: TimeInterval = (m >= 150000) ? 0.90 : ((m >= 35000) ? 0.60 : 0.30)
            if abs(regionDebounceInterval - target) > 0.05 { regionDebounceInterval = target }
            
            regionDebounceWork?.cancel()
            let work = DispatchWorkItem { [weak self, weak mapView] in
                guard let self = self, let map = mapView else { return }
                // También fuera del ciclo de render del delegate
                DispatchQueue.main.async { [weak self] in
                    self?.parent.onRegionDidChange(map.region)
                }
            }
            regionDebounceWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + regionDebounceInterval, execute: work)
        }
        
        
        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            guard fullyRendered, !didFireAfterFirstRender else { return }
            didFireAfterFirstRender = true
            parent.onMapFullyRendered()               // ⬅️ avisa a SwiftUI
            if !didFireInitialFetch { fireRegionChangeNow(mapView) }
        }
        
        
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            guard let ann = annotation as? SpotMKAnnotation else { return nil }
            
            let reuse = "spotHosting"
            let v = mapView.dequeueReusableAnnotationView(withIdentifier: reuse) ?? MKAnnotationView(annotation: annotation, reuseIdentifier: reuse)
            v.annotation = annotation
            v.canShowCallout = false
            v.clusteringIdentifier = nil
            v.isEnabled = true
            v.isUserInteractionEnabled = true
            v.backgroundColor = .clear
            v.frame = CGRect(origin: .zero, size: baseSize)
            
            let hostTag = 999_001
            if let old = v.viewWithTag(hostTag) { old.removeFromSuperview() }
            let host = UIHostingController(
                rootView: SpotPinView(
                    title: ann.title ?? "",
                    ratingMean: ann.ratingMean,
                    ratingCount: ann.ratingCount,
                    onInfo: { [weak self] in self?.parent.onSelectSpot(ann.id) },
                    onTapMain: { [weak mapView] in
                        guard let map = mapView else { return }
                        let reg = MKCoordinateRegion(center: ann.coordinate, latitudinalMeters: 500, longitudinalMeters: 500)
                        map.setRegion(reg, animated: true)
                        self.fireRegionChangeImmediately(map)
                    }
                )
            )
            host.view.backgroundColor = UIColor.clear
            host.view.translatesAutoresizingMaskIntoConstraints = false
            host.view.tag = hostTag
            v.addSubview(host.view)
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: v.leadingAnchor),
                host.view.trailingAnchor.constraint(equalTo: v.trailingAnchor),
                host.view.topAnchor.constraint(equalTo: v.topAnchor),
                host.view.bottomAnchor.constraint(equalTo: v.bottomAnchor)
            ])
            
            let scale = pinScale(for: mapView.region)
            applyScale(scale, to: v)
            return v
        }
        
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            func styleFor(sourceRaw: String) -> (stroke: UIColor, halo: UIColor, line: CGFloat, fill: UIColor) {
                let halo = UIColor.white.withAlphaComponent(0.3)
                if let src = AirspaceSource(rawValue: sourceRaw) {
                    switch src {
                    case .restricciones:   return (UIColor.systemOrange, halo, 2.2, UIColor.systemOrange.withAlphaComponent(0.16))
                    case .urbano:          return (UIColor.systemPurple, halo, 2.2, UIColor.systemPurple.withAlphaComponent(0.16))
                    case .medioambiente:   return (UIColor.systemGreen,  halo, 2.2, UIColor.systemGreen.withAlphaComponent(0.16))
                    case .infraestructura: return (UIColor.systemBlue,   halo, 2.2, UIColor.systemBlue.withAlphaComponent(0.16))
                    }
                }
                return (UIColor.gray, UIColor.white.withAlphaComponent(0.3), 1.8, UIColor.gray.withAlphaComponent(0.12))
            }
            
            if let poly = overlay as? MKPolygon {
                let parts = (poly.title ?? "").split(separator: "|")
                let sourceRaw = parts.count >= 2 ? String(parts[1]) : AirspaceSource.infraestructura.rawValue
                let s = styleFor(sourceRaw: sourceRaw)
                let r = MKPolygonRenderer(polygon: poly)
                r.fillColor = s.fill
                r.strokeColor = s.stroke.withAlphaComponent(0.75)
                r.lineWidth = max(0.3, s.line * 0.5)
                return r
            } else if let line = overlay as? MKPolyline {
                let parts = (line.title ?? "").split(separator: "|")
                let tag       = parts.count >= 1 ? String(parts[0]) : "stroke"
                let sourceRaw = parts.count >= 2 ? String(parts[1]) : AirspaceSource.infraestructura.rawValue
                let s = styleFor(sourceRaw: sourceRaw)
                let r = MKPolylineRenderer(polyline: line)
                if tag == "halo" { r.strokeColor = s.halo; r.lineWidth = s.line + 4.0 }
                else { r.strokeColor = s.stroke; r.lineWidth = s.line }
                r.lineJoin = .round
                r.lineCap = .round
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}

// MARK: - SpotPinView (SwiftUI dentro del MKAnnotationView)
private struct SpotPinView: View {
    let title: String
    let ratingMean: Double?
    let ratingCount: Int?
    let onInfo: () -> Void
    let onTapMain: () -> Void
    
    private var cappedTitle: String {
        if title.count > 42 {
            let idx = title.index(title.startIndex, offsetBy: 42)
            return String(title[..<idx]) + "…"
        }
        return title
    }
    
    private let iconSize: CGFloat = 126
    
    var body: some View {
        VStack(spacing: 12) {
            if !cappedTitle.isEmpty {
                Text(cappedTitle)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .lineLimit(1).truncationMode(.tail)
                    .padding(.vertical, 6).padding(.horizontal, 14)
                    .background(Color.white, in: Capsule())
                    .onTapGesture { onTapMain() }
            }
            
            ratingRow()
                .padding(.top, -8).padding(.bottom, -30)
                .onTapGesture { onTapMain() }
            
            ZStack {
                Image("dronePin")
                    .resizable().renderingMode(.template)
                    .foregroundColor(Color(red: 0.25, green: 0.88, blue: 0.82))
                    .scaledToFit().frame(width: iconSize, height: iconSize)
                    .accessibilityLabel("Spot")
                    .onTapGesture { onTapMain() }
            }
            .padding(.top, -8)
            
            Button(action: onInfo) {
                ZStack {
                    Circle().fill(Color.white).frame(width: 40, height: 40)
                        .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1)
                    Image(systemName: "info.circle.fill")
                        .font(.system(size: 27, weight: .semibold))
                        .foregroundColor(.blue)
                }
            }
            .offset(y: -22)
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(Color.clear)
    }
    
    private func ratingRow() -> some View {
        let text: String = {
            if let mean = ratingMean { return String(format: "%.1f", mean) }
            return "—"
        }()
        return HStack(spacing: 10) {
            stars(ratingMean ?? 0)
            Text(text)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }
    
    private func stars(_ value: Double) -> some View {
        let clamped = max(0, min(5, value))
        let full = Int(clamped)
        let hasHalf = (clamped - Double(full)) >= 0.5
        let empties = 5 - full - (hasHalf ? 1 : 0)
        
        return HStack(spacing: 3) {
            ForEach(0..<full, id: \.self) { _ in Image(systemName: "star.fill").font(.system(size: 16)).foregroundColor(.yellow) }
            if hasHalf { Image(systemName: "star.lefthalf.fill").font(.system(size: 16)).foregroundColor(.yellow) }
            ForEach(0..<max(0, empties), id: \.self) { _ in Image(systemName: "star").font(.system(size: 16)).foregroundColor(.yellow) }
        }
    }
}
