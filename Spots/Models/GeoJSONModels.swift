import Foundation
import CoreLocation

// MARK: - Colección
struct ENAIRECollection: Decodable {
    let type: String
    let features: [ENAIREFeature]
}

// MARK: - Feature
struct ENAIREFeature: Decodable, Identifiable, Hashable {
    let uuid = UUID()
    var id: UUID { uuid }

    let type: String
    let geometry: ENAIREGeometry
    let properties: ENAIREProperties?
}

// MARK: - Geometría
struct ENAIREGeometry: Decodable, Hashable {
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

// MARK: - Propiedades
struct ENAIREProperties: Decodable, Hashable {
    let identifier: String?
    let typeString: String?
    let name: String?
    let message: String?
    let descriptionText: String?
    let reasons: String?
    let otherReason: String?
    let email: String?

    let lower: Double?
    let upper: Double?

    enum CodingKeys: String, CodingKey {
        case identifier = "Identifier"
        case typeString = "Type"
        case name = "Name"
        case message = "Message"

        // ✅ Description puede llegar con mayúscula o minúscula
        case description = "Description"
        case descriptionLower = "description"

        case reasons = "Reasons"

        // ✅ OtherReasonInfo también puede variar
        case otherReason = "OtherReasonInfo"
        case otherReasonLower = "otherReasonInfo"

        case email = "Email"
        case lower = "Lower"
        case upper = "Upper"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        identifier = try container.decodeIfPresent(String.self, forKey: .identifier)
        typeString = try container.decodeIfPresent(String.self, forKey: .typeString)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        message = try container.decodeIfPresent(String.self, forKey: .message)

        // ✅ soporta description o Description
        descriptionText =
            try container.decodeIfPresent(String.self, forKey: .description) ??
            container.decodeIfPresent(String.self, forKey: .descriptionLower)

        reasons = try container.decodeIfPresent(String.self, forKey: .reasons)

        // ✅ soporta OtherReasonInfo o otherReasonInfo
        otherReason =
            try container.decodeIfPresent(String.self, forKey: .otherReason) ??
            container.decodeIfPresent(String.self, forKey: .otherReasonLower)

        email = try container.decodeIfPresent(String.self, forKey: .email)

        lower = try container.decodeIfPresent(Double.self, forKey: .lower)
        upper = try container.decodeIfPresent(Double.self, forKey: .upper)
    }
}

// MARK: - Helpers String
extension String {
    /// Normaliza etiquetas no estándar del JSON a HTML válido
    var normalizadoParaHTML: String {
        self
            .replacingOccurrences(of: "<elem>", with: "<b>")
            .replacingOccurrences(of: "</elem>", with: "</b>")
    }

    /// Decodifica entidades tipo \u003c → "<"
    var decodedHTMLEntities: String {
        self
            .replacingOccurrences(of: "\\u003c", with: "<")
            .replacingOccurrences(of: "\\u003e", with: ">")
            .replacingOccurrences(of: "\\\"", with: "\"")
    }

    
}

// MARK: - ENAIREProperties helpers
extension ENAIREProperties {
    /// Texto plano preferido
    var textoPreferido: String? {
        if let n = name, !n.trimmingCharacters(in: .whitespaces).isEmpty, n.lowercased() != "null" {
            return n
        }
        if let m = message, !m.trimmingCharacters(in: .whitespaces).isEmpty, m.lowercased() != "null" {
            return m.sinEtiquetasHTML
        }
        if let d = descriptionText, !d.trimmingCharacters(in: .whitespaces).isEmpty, d.lowercased() != "null" {
            return d
        }
        return nil
    }

    /// Texto en HTML válido
    var textoPreferidoHTML: String? {
        if let m = message, !m.isEmpty {
            return m.decodedHTMLEntities.normalizadoParaHTML
        }
        if let d = descriptionText, !d.isEmpty {
            return d.decodedHTMLEntities.normalizadoParaHTML
        }
        return nil
    }
}

// MARK: - ENAIREFeature helpers
extension ENAIREFeature {
    func primerPuntoDelPoligono() -> (Double, Double)? {
        switch geometry.coordinates {
        case .polygon(let poly):
            guard let pair = poly.first?.first, pair.count >= 2 else { return nil }
            return (pair[1], pair[0])
        case .multiPolygon(let mp):
            guard let pair = mp.first?.first?.first, pair.count >= 2 else { return nil }
            return (pair[1], pair[0])
        }
    }

    var primerPuntoCLLocation: CLLocationCoordinate2D? {
        guard let (lat, lon) = primerPuntoDelPoligono() else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
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

    private func pointInsidePolygon(_ point: CLLocationCoordinate2D,
                                    polygon: [CLLocationCoordinate2D]) -> Bool {
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

    // MARK: - UI
    var displayName: String {
        if let preferido = properties?.textoPreferido, !preferido.isEmpty {
            return preferido
        }
        if let id = properties?.identifier, !id.isEmpty {
            return id
        }
        return "(Restricción sin nombre)"
    }

    var displayIdentifier: String { properties?.identifier ?? "-" }
    var displayReason: String { properties?.reasons ?? "-" }
    var displayMessage: String { properties?.message?.sinEtiquetasHTML ?? "" }
    var displayMessageHTML: String { properties?.textoPreferidoHTML ?? "" }
    var displayEmail: String { properties?.email ?? "" }
}
