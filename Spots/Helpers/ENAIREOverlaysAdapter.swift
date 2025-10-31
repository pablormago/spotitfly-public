//
//  ENAIREOverlaysAdapter.swift
//  Spots
//
//  Convierte tus ENAIREFeature en overlays de MapKit con estilo por categoría.
//  No pinta NOTAMs. Pensado para usar con SpotContextData.
//
//  Uso rápido:
//    let overlays = ENAIREOverlaysAdapter.build(from: ctx.restricciones, group: .aero)
//                 + ENAIREOverlaysAdapter.build(from: ctx.urbanas, group: .urbano)
//                 + ENAIREOverlaysAdapter.build(from: ctx.medioambiente, group: .medioambiente)
//    mapView.addOverlays(overlays, level: .aboveRoads)
//
import Foundation
import MapKit
import UIKit

enum ENAIREGroup {
    case aero
    case urbano
    case medioambiente
    case infra
    case other
}

// Subclases para adjuntar metadatos de estilo
final class ThemedPolygon: MKPolygon {
    var group: ENAIREGroup = .other
    var name: String?
}

final class ThemedPolyline: MKPolyline {
    var group: ENAIREGroup = .other
    var name: String?
}

struct OverlayStyle {
    let stroke: UIColor
    let fill: UIColor
    let width: CGFloat
    let dash: [NSNumber]?
}

enum ENAIREOverlaysAdapter {

    // MARK: Build overlays for a group
    static func build(from features: [ENAIREFeature], group: ENAIREGroup) -> [MKOverlay] {
        var result: [MKOverlay] = []
        result.reserveCapacity(features.count)

        for f in features {
            switch f.geometry.coordinates {
            case .polygon(let rings):
                if let poly = polygon(from: rings) {
                    poly.group = group
                    poly.name = f.displayName
                    result.append(poly)
                }
            case .multiPolygon(let polys):
                for rings in polys {
                    if let poly = polygon(from: rings) {
                        poly.group = group
                        poly.name = f.displayName
                        result.append(poly)
                    }
                }
            }
        }

        return result
    }

    // exterior + holes
    private static func polygon(from rings: [[[Double]]]) -> ThemedPolygon? {
        guard let outer = rings.first else { return nil }
        var outerCoords = outer.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }

        var innerPolys: [MKPolygon] = []
        if rings.count > 1 {
            for hole in rings.dropFirst() {
                var inner = hole.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                let innerPoly = MKPolygon(coordinates: &inner, count: inner.count)
                innerPolys.append(innerPoly)
            }
        }
        return ThemedPolygon(coordinates: &outerCoords, count: outerCoords.count, interiorPolygons: innerPolys)
    }

    // MARK: Renderer helper (llámalo desde MKMapViewDelegate)
    static func renderer(for overlay: MKOverlay) -> MKOverlayRenderer? {
        if let p = overlay as? ThemedPolygon {
            let r = MKPolygonRenderer(polygon: p)
            let style = style(for: p.group, name: p.name)
            r.strokeColor = style.stroke
            r.fillColor = style.fill
            r.lineWidth = style.width
            r.lineDashPattern = style.dash
            return r
        } else if let l = overlay as? ThemedPolyline {
            let r = MKPolylineRenderer(polyline: l)
            let style = style(for: l.group, name: l.name)
            r.strokeColor = style.stroke
            r.lineWidth = max(1.0, style.width - 0.5)
            r.lineDashPattern = style.dash
            return r
        }
        return nil
    }

    // MARK: Style mapping
    private static func style(for group: ENAIREGroup, name: String?) -> OverlayStyle {
        switch group {
        case .aero:
            // Heurística simple: resalta P/R/D si aparece en el nombre/identificador
            if let n = name?.uppercased() {
                if n.contains(" PROHIB") || n.contains(" P ") || n.hasPrefix("P-") {
                    return OverlayStyle(stroke: .systemRed, fill: UIColor.systemRed.withAlphaComponent(0.16), width: 2.0, dash: nil)
                }
                if n.contains(" RESTRI") || n.contains(" R ") || n.hasPrefix("R-") {
                    return OverlayStyle(stroke: .systemOrange, fill: UIColor.systemOrange.withAlphaComponent(0.14), width: 2.0, dash: [6,4])
                }
                if n.contains(" PELIG") || n.contains(" D ") || n.hasPrefix("D-") {
                    return OverlayStyle(stroke: .systemYellow, fill: UIColor.systemYellow.withAlphaComponent(0.16), width: 2.0, dash: [2,3])
                }
                if n.contains("CTR") {
                    return OverlayStyle(stroke: .systemBlue, fill: UIColor.systemBlue.withAlphaComponent(0.10), width: 2.0, dash: nil)
                }
                if n.contains("ATZ") {
                    return OverlayStyle(stroke: .systemTeal, fill: UIColor.systemTeal.withAlphaComponent(0.10), width: 2.0, dash: [4,3])
                }
                if n.contains("RMZ") || n.contains("TMZ") {
                    return OverlayStyle(stroke: .systemPurple, fill: UIColor.systemPurple.withAlphaComponent(0.10), width: 2.0, dash: [8,4])
                }
                if n.contains("TSA") || n.contains("TRA") {
                    return OverlayStyle(stroke: .systemPink, fill: UIColor.systemPink.withAlphaComponent(0.10), width: 2.0, dash: [2,2])
                }
            }
            // por defecto aero
            return OverlayStyle(stroke: .systemBlue, fill: UIColor.systemBlue.withAlphaComponent(0.08), width: 1.5, dash: nil)
        case .urbano:
            return OverlayStyle(stroke: .systemIndigo, fill: UIColor.systemIndigo.withAlphaComponent(0.10), width: 1.5, dash: [6,4])
        case .medioambiente:
            return OverlayStyle(stroke: .systemGreen, fill: UIColor.systemGreen.withAlphaComponent(0.12), width: 1.5, dash: [4,3])
        case .infra:
            return OverlayStyle(stroke: .brown, fill: UIColor.brown.withAlphaComponent(0.10), width: 1.5, dash: nil)
        case .other:
            return OverlayStyle(stroke: .darkGray, fill: UIColor.darkGray.withAlphaComponent(0.10), width: 1.0, dash: nil)
        }
    }
}
