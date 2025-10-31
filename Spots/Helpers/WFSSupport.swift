// WFSSupport.swift
import CoreLocation

/// Construye el parámetro bbox para WFS (EPSG:4326) a partir de un centro y un radio en km.
/// Añade overscan para cubrir bordes del viewport.
func wfsBBoxParam(center: CLLocation, km: Double, overscan: Double = 0.15) -> String {
    let lat = center.coordinate.latitude
    let lon = center.coordinate.longitude

    let dLat = (km / 111.0) * (1.0 + overscan)
    let dLon = (km / (111.0 * max(0.2, cos(lat * .pi / 180.0)))) * (1.0 + overscan)

    let minLat = lat - dLat
    let maxLat = lat + dLat
    let minLon = lon - dLon
    let maxLon = lon + dLon

    // Formato ArcGIS WFS: minLon,minLat,maxLon,maxLat,EPSG:4326
    return "\(minLon),\(minLat),\(maxLon),\(maxLat),EPSG:4326"
}
