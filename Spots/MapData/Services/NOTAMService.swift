//
//  NOTAMService.swift
//  Spots
//
//  Created by Pablo Jimenez on 9/9/25.
//

import Foundation
import CoreLocation

struct NOTAMService {
    static func fetchAround(location: CLLocation, km: Double = 50) async throws -> [NOTAMFeature] {
        let bbox = location.coordinate.boundingBox(km: km)

        let urlString = """
        https://servais.enaire.es/insignias/rest/services/NOTAM/NOTAM_UAS_APP_V2/MapServer/1/query?
        f=json
        &outFields=*
        &geometry=\(bbox.minLon),\(bbox.minLat),\(bbox.maxLon),\(bbox.maxLat)
        &geometryType=esriGeometryEnvelope
        &inSR=4326
        &spatialRel=esriSpatialRelIntersects
        """.replacingOccurrences(of: "\n", with: "")

        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        print("🌍 NOTAMService → URL:\n\(url.absoluteString)")

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let decoded = try JSONDecoder().decode(NOTAMResponse.self, from: data)

        print("✅ NOTAMService → recibidos \(decoded.features.count) NOTAMs en el área")

        return decoded.features
    }
}
