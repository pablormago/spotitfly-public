import Foundation
import CoreLocation

extension CLLocationCoordinate2D {
    /// Bounding box alrededor del punto, en kilómetros.
    /// Devuelve (minLon, minLat, maxLon, maxLat) en EPSG:4326 (lon,lat).
    func boundingBox(km: Double) -> (minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        // Aproximaciones: 1º lat ≈ 111.32 km; 1º lon ≈ 111.32 * cos(lat)
        let kmPerDegLat = 111.32
        let dLat = km / kmPerDegLat

        let rad = latitude * .pi / 180.0
        let kmPerDegLon = kmPerDegLat * cos(rad)
        let dLon = kmPerDegLon > 0 ? km / kmPerDegLon : 0

        let minLat = max(-90.0, latitude - dLat)
        let maxLat = min( 90.0, latitude + dLat)

        var minLon = longitude - dLon
        var maxLon = longitude + dLon

        // Normaliza a [-180, 180]
        if minLon < -180 { minLon += 360 }
        if maxLon >  180 { maxLon -= 360 }

        return (minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat)
    }
}
