//
//  AirspaceOracle.swift
//  Spots
//
//  Created by Pablo Jimenez on 16/10/25.
//


//
//  AirspaceOracle.swift
//  Spots
//
//  DEBUG-only: telemetría de overlays (esperados vs. pintados), tiempos y claves de tile.
//  No toca UX. Se activa con FeatureFlags.oracleEnabled.
//

import Foundation
import MapKit

extension Notification.Name {
    static let airspaceOracleDidUpdate = Notification.Name("airspaceOracleDidUpdate")
}

#if DEBUG
final class AirspaceOracle: ObservableObject {
    static let shared = AirspaceOracle()
    private init() {}
    
    @inline(__always)
        private func notify() {
            if Thread.isMainThread {
                NotificationCenter.default.post(name: .airspaceOracleDidUpdate, object: nil)
            } else {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: .airspaceOracleDidUpdate, object: nil)
                }
            }
        }

    // Sesión simple por app-foreground
    @Published private(set) var sessionId: String = UUID().uuidString
    private var lastRegionTag: String = "-"
    private var lastRegion: MKCoordinateRegion?
    private var lastRegionChangeAt: CFAbsoluteTime = 0

    // Último tile visto en el store
    @Published private(set) var lastTileKey: String = "-"
    @Published private(set) var lastOverscan: Double = 0
    @Published private(set) var lastBBox: (minLat: Double, maxLat: Double, minLon: Double, maxLon: Double)?
    private var lastStoreStartAt: CFAbsoluteTime = 0
    private var lastStoreEndAt: CFAbsoluteTime = 0

    // Conteos publicados/pintados (por fuente & tipo)
    @Published private(set) var lastPublished: [String: Int] = [:]
    @Published private(set) var lastPainted:   [String: Int] = [:]
    
    // 🆕 Esperados estrictamente en el viewport actual (sin overscan)
        @Published private(set) var lastViewportExpected: [String: Int] = [:]

    // MARK: - Hooks públicos

    func scenePhaseChanged(_ phase: String) {
        guard FeatureFlags.oracleEnabled else { return }
        if phase == "active" {
            sessionId = UUID().uuidString
            ASDBG.log("AS_ORACLE", "session start id=\(sessionId)")
        } else if phase == "background" {
            ASDBG.log("AS_ORACLE", "session end id=\(sessionId)")
        }
        notify()
    }

    func regionChanged(tag: String, region: MKCoordinateRegion) {
        guard FeatureFlags.oracleEnabled else { return }
        lastRegionTag = tag
        lastRegion = region
        lastRegionChangeAt = CFAbsoluteTimeGetCurrent()
        ASDBG.log("AS_ORACLE", "regionChanged tag=\(tag) r=\(region.shortDesc)")
        notify()
    }

    func storeStarted(tag: String?, tileKey: String, bbox: (Double,Double,Double,Double), overscan: Double) {
        guard FeatureFlags.oracleEnabled else { return }
        DispatchQueue.main.async {
            self.lastTileKey = tileKey
            self.lastOverscan = overscan
            self.lastBBox = (bbox.0, bbox.1, bbox.2, bbox.3)
        }
        ASDBG.log("AS_ORACLE", "storeStarted ...")

    }

    func storePublished(tag: String?, bySourceKind: [String:Int]) {
        guard FeatureFlags.oracleEnabled else { return }
        lastStoreEndAt = CFAbsoluteTimeGetCurrent()
        DispatchQueue.main.async {
            self.lastPublished = bySourceKind
        }
        ASDBG.log("AS_ORACLE", "storePublished ...")

    }

    func mapPainted(bySourceKind: [String:Int], overlaysAdded: Int) {
        guard FeatureFlags.oracleEnabled else { return }
        DispatchQueue.main.async {
            self.lastPainted = bySourceKind
        }
        ASDBG.log("AS_ORACLE", "mapPainted ...")
    }
    
    // 🆕 Reportar "esperados en viewport" (recorte a pantalla)
        func viewportExpected(bySourceKind: [String:Int]) {
            guard FeatureFlags.oracleEnabled else { return }
            DispatchQueue.main.async {
                self.lastViewportExpected = bySourceKind
            }
            ASDBG.log("AS_ORACLE", "viewportExpected kinds=\(bySourceKind)")
            notify()
        }
}
#endif
