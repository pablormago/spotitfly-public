import Foundation
import MapKit

/// Logger mínimo para depurar overlays (activable por flag).
enum ASDBG {
    static var enabled: Bool = true
    static func log(_ category: String, _ message: String) {
        guard enabled else { return }
        print("🧩 [\(category)] \(message)")
    }
}

extension MKCoordinateRegion {
    var shortDesc: String {
        String(format: "c=(%.5f,%.5f) Δ=(%.3f,%.3f)",
               center.latitude, center.longitude,
               span.latitudeDelta, span.longitudeDelta)
    }
}
