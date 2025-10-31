import Foundation
import CoreLocation

struct InfraestructuraCollection: Decodable {
    let type: String
    let features: [InfraestructuraFeature]
}

struct InfraestructuraFeature: Decodable, Identifiable, Hashable {
    var id: String { properties.identifier ?? UUID().uuidString }
    let type: String
    let geometry: InfraestructuraGeometry
    let properties: InfraestructuraProperties

    func primerPuntoDelPoligono() -> CLLocationCoordinate2D? {
        switch geometry.coordinates {
        case .polygon(let poly):
            guard let pair = poly.first?.first, pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        case .multiPolygon(let mp):
            guard let pair = mp.first?.first?.first, pair.count >= 2 else { return nil }
            return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
        }
    }

    func contains(point: CLLocationCoordinate2D) -> Bool {
        switch geometry.coordinates {
        case .polygon(let rings):
            for ring in rings {
                let coords = ring.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                if pointInsidePolygon(point, polygon: coords) { return true }
            }
        case .multiPolygon(let polys):
            for poly in polys {
                for ring in poly {
                    let coords = ring.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
                    if pointInsidePolygon(point, polygon: coords) { return true }
                }
            }
        }
        return false
    }

    private func pointInsidePolygon(_ point: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let xi = polygon[i].longitude, yi = polygon[i].latitude
            let xj = polygon[j].longitude, yj = polygon[j].latitude
            if ((yi > point.latitude) != (yj > point.latitude)) &&
                (point.longitude < (xj - xi) * (point.latitude - yi) / (yj - yi) + xi) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    // MARK: - Helpers UI
    var displayName: String {
        properties.identifier ?? "(Infraestructura sin nombre)"
    }

    var displayMessageHTML: String {
        properties.message?.normalizadoParaHTML ?? ""
    }

    var displayURL: String? { properties.siteURL }
    var displayEmail: String? { properties.email }

    var displayAltitude: String? {
        if let up = properties.upper {
            return "\(up) \(properties.upperReference ?? "")"
        }
        return nil
    }

    var displayProvider: String? { properties.provider }
    var displayAuthority: String? { properties.nameAuthority }
}

struct InfraestructuraGeometry: Decodable, Hashable {
    let type: String
    let coordinates: Coordinates

    enum Coordinates: Decodable, Hashable {
        case polygon([[[Double]]])
        case multiPolygon([[[[Double]]]])

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let mp = try? c.decode([[[[Double]]]].self) {
                self = .multiPolygon(mp)
            } else if let p = try? c.decode([[[Double]]].self) {
                self = .polygon(p)
            } else {
                throw DecodingError.typeMismatch(
                    Self.self,
                    .init(codingPath: decoder.codingPath,
                          debugDescription: "Coordenadas no son Polygon ni MultiPolygon")
                )
            }
        }
    }
}

struct InfraestructuraProperties: Decodable, Hashable {
    let identifier: String?
    let provider: String?
    let nameAuthority: String?
    let otherReasonInfo: String?
    let message: String?
    let siteURL: String?
    let email: String?
    let upper: Double?
    let upperReference: String?
    let creationDateTime: String?
    let updateDateTime: String?
}


