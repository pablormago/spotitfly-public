
import Foundation
import MapKit

public struct OverlayBBox {
    public let minLon: Double
    public let minLat: Double
    public let maxLon: Double
    public let maxLat: Double

    public init(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) {
        self.minLon = minLon
        self.minLat = minLat
        self.maxLon = maxLon
        self.maxLat = maxLat
    }

    /// Formats as 'minLon,minLat,maxLon,maxLat,EPSG:4326' for WFS bbox param
    public var wfsParam: String {
        return "\(minLon),\(minLat),\(maxLon),\(maxLat),EPSG:4326"
    }
    
}

/// Simple bbox around an MKCoordinateRegion with a small margin to avoid tile edges
public func overlayBBox(for region: MKCoordinateRegion, marginFraction: Double = 0.10) -> OverlayBBox {
    // 1) Limita el overscan a algo sensato (0…50%)
    let mf = max(0.0, min(marginFraction, 0.50))

    // 2) Semiextensión con overscan
    var dLat = region.span.latitudeDelta * (1.0 + mf) / 2.0
    var dLon = region.span.longitudeDelta * (1.0 + mf) / 2.0

    // 3) Evita desbordes por spans absurdos (ej. región “mundo”)
    dLat = min(dLat, 90.0)   // lat siempre [-90, 90]
    dLon = min(dLon, 180.0)  // lon siempre [-180, 180]

    // 4) BBox bruto
    var minLat = region.center.latitude  - dLat
    var maxLat = region.center.latitude  + dLat
    var minLon = region.center.longitude - dLon
    var maxLon = region.center.longitude + dLon

    // 5) Clamp duro a EPSG:4326
    if minLat < -90 { minLat = -90 }
    if maxLat >  90 { maxLat =  90 }
    if minLon < -180 { minLon = -180 }
    if maxLon >  180 { maxLon =  180 }

    // 6) Normaliza por si acaso
    if minLat > maxLat { swap(&minLat, &maxLat) }
    if minLon > maxLon { swap(&minLon, &maxLon) }

    return OverlayBBox(minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat)
}

// MARK: - ArcGIS REST helper (envelope "minX,minY,maxX,maxY" en EPSG:4326)
public extension OverlayBBox {
    var envelope4326: String {
        "\(minLon),\(minLat),\(maxLon),\(maxLat)"
    }
}
public extension OverlayBBox {
    /// Envelope expandido para REST (EPSG:4326) aplicando overscan (factor>1) y acolchado mínimo en grados
    func expandedEnvelope4326(factor: Double, minPadDeg: Double) -> String {
        guard factor > 1.0 else { return envelope4326 }
        let dLat = maxLat - minLat
        let dLon = maxLon - minLon
        let padLat = max((dLat * (factor - 1.0)) / 2.0, minPadDeg)
        let padLon = max((dLon * (factor - 1.0)) / 2.0, minPadDeg)
        let newMinLon = minLon - padLon
        let newMinLat = minLat - padLat
        let newMaxLon = maxLon + padLon
        let newMaxLat = maxLat + padLat
        return "\(newMinLon),\(newMinLat),\(newMaxLon),\(newMaxLat)"
    }
}
