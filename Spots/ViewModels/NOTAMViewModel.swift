import Foundation
import CoreLocation
import SwiftUI
import CoreGraphics

// MARK: - API models
struct NOTAMResponse: Decodable {
    let features: [NOTAMFeature]
}

struct NOTAMFeature: Decodable, Identifiable {
    let id = UUID()
    let attributes: NOTAMAttributes
    let geometry: NOTAMGeometry?
}

struct NOTAMGeometry: Decodable {
    let rings: [[[Double]]]
}

struct NOTAMAttributes: Decodable {
    // IDs / nombres
    let notamId: String?
    let areaSactaName: String?
    let affectedElement: String?
    let qcode: String?

    // Texto principal
    let itemE: String?          // descripción “E) …”
    let DESCRIPTION: String?    // HTML con DESDE/HASTA/HORARIO/DESCRIPCIÓN (cuando viene)

    // Fechas formateadas por el backend
    let itemBstr: String?       // “DESDE”
    let itemCstr: String?       // “HASTA”

    // Alturas u otros
    let itemF: String?
    let itemG: String?

    // 🔹 Horario (el que faltaba)
    let itemD: String?          // “HORARIO”

    // Otros (por si acaso los necesitas)
    let incidenceType: String?
    let incidenceQualifier: String?
    let sourceInformationNotam: String?
    let icaoFormatText: String?
    let LOWER_VAL: Int?
    let UPPER_VAL: Int?
}

// MARK: - ViewModel
@MainActor
class NOTAMViewModel: ObservableObject {
    @Published var notams: [NOTAMFeature] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    func fetchNotams(for location: CLLocationCoordinate2D) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let lat = location.latitude
        let lon = location.longitude
        let urlStr =
        "https://servais.enaire.es/insignias/rest/services/NOTAM/NOTAM_UAS_APP_V2/MapServer/1/query?where=1=1&outFields=*&geometry=\(lon),\(lat)&geometryType=esriGeometryPoint&inSR=4326&spatialRel=esriSpatialRelIntersects&f=json"

        guard let url = URL(string: urlStr) else {
            errorMessage = "URL de NOTAM inválida"
            return
        }

        do {
            print("NOTAM URL: ")
            print(url)
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(NOTAMResponse.self, from: data)
            self.notams = decoded.features
        } catch {
            errorMessage = "Error cargando NOTAMs: \(error.localizedDescription)"
            print("❌ Error fetch NOTAMs: \(error)")
        }
    }

    func hasNotam(for feature: ENAIREFeature) -> Bool {
        let nombre = feature.displayName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nombre.isEmpty, nombre != "(sin nombre)" else { return false }
        return notams.contains { $0.matches(feature) }
    }
}

// MARK: - Geo helpers para NOTAM
extension NOTAMFeature {
    func matches(_ feature: ENAIREFeature) -> Bool {
        if let coordinate = feature.primerPuntoCLLocation,
           contains(latitude: coordinate.latitude, longitude: coordinate.longitude) {
            return true
        }

        let nombre = feature.displayName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let area = attributes.areaSactaName?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
            if area.contains(nombre) || nombre.contains(area) { return true }
        }
        if let affected = attributes.affectedElement?.lowercased(), affected.contains(nombre) { return true }
        return false
    }

    func contains(latitude: Double, longitude: Double) -> Bool {
        guard let geometry else { return false }
        for ring in geometry.rings {
            let points = ring.map { CGPoint(x: $0[0], y: $0[1]) }
            if pointInsidePolygon(point: CGPoint(x: longitude, y: latitude), polygon: points) {
                return true
            }
        }
        return false
    }

    private func pointInsidePolygon(point: CGPoint, polygon: [CGPoint]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let xi = polygon[i].x, yi = polygon[i].y
            let xj = polygon[j].x, yj = polygon[j].y
            if ((yi > point.y) != (yj > point.y)) &&
                (point.x < (xj - xi) * (point.y - yi) / (yj - yi) + xi) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
