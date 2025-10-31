import Foundation
import MapKit

/// Store independiente para overlays (no afecta al flujo de 'spot detalle').
@MainActor
final class AirspaceOverlayStore: ObservableObject {
    @Published private(set) var features: [AirspaceFeature] = []
    
    private var cache: [String: [AirspaceFeature]] = [:]
    private var lastToastKey: String? = nil
    // LRU de tiles
    private var cacheOrder: [String] = []
    private let maxCacheTiles: Int = 36   // ~6x6 tiles recientes

    
    /// Secuencia para evitar condiciones de carrera: solo aplica el último resultado.
    private var loadSeq: UInt64 = 0
    // Cancela la carga anterior (útil en recenter desde búsqueda)
    private var currentTask: Task<Void, Never>? = nil

    
    init() {}
    
    /// Lanza una carga cancelando la anterior. Úsalo siempre desde la UI.
    /// - Parameters:
    ///   - region: región a consultar
    ///   - tag: usa "map#recenter#..." cuando venga de búsqueda para activar bypass de cache
    func requestLoad(for region: MKCoordinateRegion, tag: String? = nil) {
        // Cancela en caliente la tarea previa
        currentTask?.cancel()

        // Lanza una nueva tarea aislada
        currentTask = Task { [weak self] in
            guard let self else { return }
            await self.load(for: region, tag: tag)
        }
    }

    
    func load(for region: MKCoordinateRegion, tag: String? = nil) async {
        // 🔢 Secuencia al principio + alias local para logs
        loadSeq &+= 1
        let mySeq = loadSeq

        ASDBG.log("STORE", "IN \(tag ?? "-") -> \(region.shortDesc)")
        print("📦 [Store] IN -> center=(\(region.center.latitude), \(region.center.longitude)) span=(\(region.span.latitudeDelta), \(region.span.longitudeDelta))")

        // 🛑 Guard anti-"mundo": evita pedir WFS si el viewport es enorme
        if region.span.latitudeDelta > 30 || region.span.longitudeDelta > 60 {
            #if DEBUG
            let tileKeyStr = Self.tileKey(for: region.center, span: region.span)
            print("🟥 [OVERLAYS #\(mySeq)] skip huge viewport Δ=(\(region.span.latitudeDelta),\(region.span.longitudeDelta)) tile=\(tileKeyStr)")
            #endif
            return
        }

        // ⏱️ Inicio de medición
        let t0 = CFAbsoluteTimeGetCurrent()

        
#if DEBUG
let tileKeyStr = Self.tileKey(for: region.center, span: region.span)
let span = region.span
let c = region.center
let latStr = String(format: "%.5f", c.latitude)
let lonStr = String(format: "%.5f", c.longitude)
let dLatStr = String(format: "%.3f", span.latitudeDelta)
let dLonStr = String(format: "%.3f", span.longitudeDelta)
print("🟦 [OVERLAYS #\(mySeq)] start tile=\(tileKeyStr) center=(\(latStr),\(lonStr)) Δ=(\(dLatStr),\(dLonStr))")
#endif

        
        
        
        
        // 🧭 ¿Es un recenter programático?
        let isRecenter = (tag ?? "").contains("recenter")

        // Overscan dinámico según zoom; si es recenter, subimos margen para asegurar contexto
        let baseMargin = Self.overscan(for: region)
        let margin = isRecenter ? max(baseMargin, 0.50) : baseMargin

        // BBOX con el margen decidido
        let bbox = overlayBBox(for: region, marginFraction: margin)

        // Clave de caché más “estable” para micro movimientos
        let tileKey = Self.tileKey(for: region.center, span: region.span)
        ASDBG.log("STORE", "tileKey \(tag ?? "-") => \(tileKey)")
        print("🗺️ [Store] tileKey=\(tileKey)")

        #if DEBUG
        if FeatureFlags.oracleEnabled {
            AirspaceOracle.shared.storeStarted(tag: tag,
                                               tileKey: tileKey,
                                               bbox: (bbox.minLat, bbox.maxLat, bbox.minLon, bbox.maxLon),
                                               overscan: margin)
        }
        #endif

        // Política de caché:
        //  - Normal: si hay cache, muéstrala suave.
        //  - Recenter: **bypass** en el primer tick para forzar fetch y no mezclar lo anterior.
        if let cached = cache[tileKey], !cached.isEmpty {
            print("⚡️ [Store] cacheHit=true -> features=\(cached.count)")
            features = cached
            // LRU → toca este tile
            if let idx = cacheOrder.firstIndex(of: tileKey) { cacheOrder.remove(at: idx) }
            cacheOrder.append(tileKey)
        } else {
            print("🔄 [Store] cacheHit=false -> fetching services…")
        }

        

        
        var accR: [ENAIREFeature] = []
        var accU: [ENAIREFeature] = []
        var accM: [ENAIREFeature] = []
        var accI: [InfraestructuraFeature] = []
        
        var failedSources: [String] = []
        var cancelledSources: [String] = []   // 🆕 para distinguir cancelaciones
        
        // ⛔️ Anti-ruido: si otra llamada arrancó mientras llegábamos aquí, aborta esta sin pedir red
        guard mySeq == loadSeq else {
            #if DEBUG
            print("🟥 [OVERLAYS #\(mySeq)] abort early: newer seq #\(loadSeq) already started")
            #endif
            return
        }
        
        // ⚡️ Descargas en paralelo, manejo de errores por capa
        async let rTask: [ENAIREFeature] = {
            do { return try await RestriccionesOverlayService.fetch(bbox: bbox) }
            catch is CancellationError { cancelledSources.append("Restricciones"); return [] }
            catch { failedSources.append("Restricciones"); return [] }
        }()
        
        async let uTask: [ENAIREFeature] = {
            do { return try await UrbanoOverlayService.fetch(bbox: bbox) }
            catch is CancellationError { cancelledSources.append("Urbano"); return [] }
            catch { failedSources.append("Urbano"); return [] }
        }()
        
        async let mTask: [ENAIREFeature] = {
            do { return try await MedioambienteOverlayService.fetch(bbox: bbox) }
            catch is CancellationError { cancelledSources.append("Medioambiente"); return [] }
            catch { failedSources.append("Medioambiente"); return [] }
        }()
        
        async let iTask: [InfraestructuraFeature] = {
            do { return try await InfraestructurasOverlayService.fetch(bbox: bbox) }
            catch is CancellationError { cancelledSources.append("Infraestructuras"); return [] }
            catch { failedSources.append("Infraestructuras"); return [] }
        }()

        
        accR = await rTask
        accU = await uTask
        accM = await mTask
        accI = await iTask
        
        // 🛡️ Anti-race: si durante la espera ha entrado otra carga, abortamos aplicar este resultado.
        guard mySeq == loadSeq else {
            #if DEBUG
            let tileKeyStr = Self.tileKey(for: region.center, span: region.span)
            print("🟥 [OVERLAYS #\(mySeq)] canceled → newer seq #\(loadSeq) already in flight (tile=\(tileKeyStr))")
            #endif
            return
        }


                // 🛑 Si TODO está vacío y hubo cancelaciones, no publiques “0 features” fantasma
                               let allEmpty = accR.isEmpty && accU.isEmpty && accM.isEmpty && accI.isEmpty
                               if allEmpty {
                                   if !cancelledSources.isEmpty {
                                       #if DEBUG
                                       print("🟦 [OVERLAYS #\(mySeq)] skip publish (all empty & cancelled=\(cancelledSources))")
                                       #endif
                                       return
                                   }
                                   if !failedSources.isEmpty {
                                       #if DEBUG
                                       print("🟦 [OVERLAYS #\(mySeq)] keep cache (all empty & failed=\(failedSources))")
                                       #endif
                                       return
                                   }
                               }

        
        // Mapear a AirspaceFeature
        let mappedR = accR.flatMap { $0.toAirspaceFeatures(source: .restricciones) }
        let mappedU = accU.flatMap { $0.toAirspaceFeatures(source: .urbano) }
        let mappedM = accM.flatMap { $0.toAirspaceFeatures(source: .medioambiente) }
        let mappedI = accI.flatMap { $0.toAirspaceFeatures() }
        
        // ⚠️ Filtrado TMA solo en Restricciones (evita falsos positivos por textos que mencionan “TMA”)
        let safeR = mappedR.filter { $0.kind != .TMA }
        
        // No aplicamos Filtro de TMA
        let merged = mappedU + mappedM + mappedR + mappedI
        
        // Cache + publicar (LRU)
        cache[tileKey] = merged

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

        features = merged

#if DEBUG
        // Construir pares "source.kind" → count para el Oráculo
        func pair(_ s: AirspaceSource, _ k: AirspaceKind) -> String { "\(s.rawValue).\(k.rawValue)" }
        var bySourceKind: [String:Int] = [:]
        for f in features {
            bySourceKind[pair(f.source, f.kind), default: 0] += 1
        }
        if FeatureFlags.oracleEnabled {
            AirspaceOracle.shared.storePublished(tag: tag, bySourceKind: bySourceKind)
        }
#endif

        print("🧩 [Store] publish -> features.count=\(merged.count)")
        
#if DEBUG
        let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
        
        let rawBySource: [AirspaceSource:Int] = [
            .restricciones: mappedR.count,
            .urbano: mappedU.count,
            .medioambiente: mappedM.count,
            .infraestructura: mappedI.count
        ]
        //let filteredTMA = mappedR.count - safeR.count
        let pubBySource: [AirspaceSource:Int] = [
            .restricciones: mappedR.count,
            .urbano: mappedU.count,
            .medioambiente: mappedM.count,
            .infraestructura: mappedI.count
        ]
        
        let publishedByKind = Dictionary(grouping: merged, by: { $0.kind }).mapValues { $0.count }
        
        func fmtSources(_ dict: [AirspaceSource:Int]) -> String {
            let order: [AirspaceSource] = [.restricciones, .urbano, .medioambiente, .infraestructura]
            return order.map { "\($0): \(dict[$0, default: 0])" }.joined(separator: ", ")
        }
        func fmtKinds(_ dict: [AirspaceKind:Int]) -> String {
            let order: [AirspaceKind] = [.prohibited, .restricted, .danger, .CTR, .ATZ, .TMA, .other]
            return order.compactMap { k in dict[k].map { "\(k): \($0)" } }.joined(separator: ", ")
        }
        
        print("🟨 [OVERLAYS #\(mySeq)] raw by source → \(fmtSources(rawBySource))")
        print("🟩 [OVERLAYS #\(mySeq)] published by source → \(fmtSources(pubBySource)) | by kind → \(fmtKinds(publishedByKind)) | \(elapsedMs) ms")

        ASDBG.log("STORE", "OUT \(tag ?? "-") src=\(pubBySource) kinds=\(publishedByKind) elapsed=\(Int(elapsedMs))ms")
        
        
#endif
        
        
        
#if DEBUG
        let bySrc = Dictionary(grouping: merged, by: { $0.source }).mapValues { $0.count }
        let byKind = Dictionary(grouping: merged, by: { $0.kind }).mapValues { $0.count }
        print("✅ Overlays pintables → por fuente: \(bySrc) | por tipo: \(byKind)")
#endif
        
        
        // Toast si hubo fallos (evita spam con la misma combinación consecutiva)
        if !failedSources.isEmpty {
            let unique = Array(Set(failedSources)).sorted()
            let key = unique.joined(separator: ",")
            if key != lastToastKey {
                let text = (unique.count == 1)
                ? "En estos momentos la capa \(unique[0]) no está disponible desde ENAIRE."
                : "En estos momentos las capas \(unique.joined(separator: ", ")) no están disponibles desde ENAIRE."
                NotificationCenter.default.post(name: Notification.Name("ShowToast"), object: text)
                lastToastKey = key
            }
        }
    }
    
    // MARK: - Heurística de overscan por zoom
    private static func overscan(for region: MKCoordinateRegion) -> Double {
        // Δlat en grados → metros aproximados
        let latMeters = region.span.latitudeDelta * 111_000.0
        
        // Más cerca ⇒ mayor margen. Valores empíricos para líneas finas (infraestructuras).
        if latMeters <= 2_000   { return 0.45 }  // muy cerca (barrio)
        if latMeters <= 5_000   { return 0.35 }  // ciudad cerca
        if latMeters <= 15_000  { return 0.28 }  // ciudad
        if latMeters <= 50_000  { return 0.22 }  // área metropolitana
        return 0.15                               // lejos
    }
    
    // MARK: - Clave de caché estable para micro movimientos
    private static func tileKey(for center: CLLocationCoordinate2D, span: MKCoordinateSpan) -> String {
        // Grilla que depende del viewport pero con pasos ligeramente mayores para reducir “thrash”
        let latStep = max(0.06, span.latitudeDelta * 0.85)
        let lonStep = max(0.06, span.longitudeDelta * 0.85)
        let lat = (center.latitude / latStep).rounded(.toNearestOrAwayFromZero) * latStep
        let lon = (center.longitude / lonStep).rounded(.toNearestOrAwayFromZero) * lonStep
        return String(format: "%.5f_%.5f_%.5f_%.5f", lat, lon, latStep, lonStep)
    }
}
