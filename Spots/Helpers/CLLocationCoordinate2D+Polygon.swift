import Foundation
import CoreLocation

extension Array where Element == CLLocationCoordinate2D {
    /// Devuelve true si el punto está dentro del polígono (ray-casting)
    func contains(_ point: CLLocationCoordinate2D) -> Bool {
        guard count > 2 else { return false }

        var intersects = 0
        for i in 0..<count {
            let j = (i + 1) % count
            let a = self[i]
            let b = self[j]

            // Comprobación de cruce en horizontal (latitud)
            if ((a.latitude > point.latitude) != (b.latitude > point.latitude)) {
                let lonAtLat = (b.longitude - a.longitude) * (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude
                if point.longitude < lonAtLat {
                    intersects += 1
                }
            }
        }
        return intersects % 2 == 1
    }
}
