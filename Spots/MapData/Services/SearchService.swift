
//
//  SearchService.swift
//  Spots
//
//  Prioriza resultados del país del usuario (según el centro del viewport) y del área cercana.
//  Mantiene region bias + ranking por distancia y coincidencia de tokens.
//

import Foundation
import MapKit
import Contacts
import CoreLocation

// Resultado de lugares (MKLocalSearch) para el panel de sugerencias
struct SearchPlaceItem: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String?
    let coordinate: CLLocationCoordinate2D
}

// BEGIN INSERT — Conformidad manual para evitar problemas con CLLocationCoordinate2D
extension SearchPlaceItem: Equatable {
    static func == (lhs: SearchPlaceItem, rhs: SearchPlaceItem) -> Bool {
        let sameName = lhs.name.caseInsensitiveCompare(rhs.name) == .orderedSame
        let latOK = abs(lhs.coordinate.latitude - rhs.coordinate.latitude) < 1e-6
        let lonOK = abs(lhs.coordinate.longitude - rhs.coordinate.longitude) < 1e-6
        return sameName && latOK && lonOK
    }
}

extension SearchPlaceItem: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(name.lowercased())
        hasher.combine(Int((coordinate.latitude * 1e6).rounded()))
        hasher.combine(Int((coordinate.longitude * 1e6).rounded()))
    }
}
// END INSERT — Conformidad manual

private enum _SearchRank {
    static func tokens(from query: String) -> [String] {
        query.lowercased()
            .replacingOccurrences(of: ",", with: " ")
            .split { !$0.isLetter && !$0.isNumber }
            .map { String($0) }
            .filter { !$0.isEmpty }
    }

    static func tokenHits(_ tokens: [String], in s: String?) -> Int {
        guard let s = s?.lowercased() else { return 0 }
        var c = 0
        for t in tokens where !t.isEmpty {
            if s.contains(t) { c += 1 }
        }
        return c
    }
}

enum SearchService {
    /// Busca lugares/POIs con MKLocalSearch en la región visible del mapa.
    /// Prioriza el país detectado en el centro del viewport (país del usuario).
    static func searchPlaces(query: String, region: MKCoordinateRegion, limit: Int = 8) async -> [SearchPlaceItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return [] }

        // 1) Detectar país preferido a partir del centro del viewport (usuario)
        let preferredCountry: String? = await detectCountryCode(of: region)

        // 2) Preparar petición con sesgo al viewport
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = region
        if #available(iOS 13.0, *) {
            request.resultTypes = [.address, .pointOfInterest]
        }

        // 3) Ejecutar búsqueda
        let search = MKLocalSearch(request: request)
        let response: MKLocalSearch.Response
        do {
            response = try await search.start()
        } catch {
            return []
        }

        // 4) Ranking: país preferido → tokens → distancia
        let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let tokens = _SearchRank.tokens(from: trimmed)

        let rankedItems: [MKMapItem] = response.mapItems.sorted { a, b in
            let aCC = a.placemark.isoCountryCode
            let bCC = b.placemark.isoCountryCode
            let aCountryScore = (preferredCountry != nil && aCC == preferredCountry) ? 1000 : 0
            let bCountryScore = (preferredCountry != nil && bCC == preferredCountry) ? 1000 : 0

            // Hits por contenido (thoroughfare, locality, name, title)
            let aHits = _SearchRank.tokenHits(tokens, in: a.placemark.thoroughfare)
                    + _SearchRank.tokenHits(tokens, in: a.placemark.subThoroughfare)
                    + _SearchRank.tokenHits(tokens, in: a.placemark.locality)
                    + _SearchRank.tokenHits(tokens, in: a.name)
                    + _SearchRank.tokenHits(tokens, in: a.placemark.title)
            let bHits = _SearchRank.tokenHits(tokens, in: b.placemark.thoroughfare)
                    + _SearchRank.tokenHits(tokens, in: b.placemark.subThoroughfare)
                    + _SearchRank.tokenHits(tokens, in: b.placemark.locality)
                    + _SearchRank.tokenHits(tokens, in: b.name)
                    + _SearchRank.tokenHits(tokens, in: b.placemark.title)

            // Distancia al centro del viewport
            let da = CLLocation(latitude: a.placemark.coordinate.latitude, longitude: a.placemark.coordinate.longitude).distance(from: center)
            let db = CLLocation(latitude: b.placemark.coordinate.latitude, longitude: b.placemark.coordinate.longitude).distance(from: center)

            if aCountryScore != bCountryScore { return aCountryScore > bCountryScore }
            if aHits != bHits { return aHits > bHits }
            return da < db
        }

        // 5) Mapear a nuestros items + subtítulo legible
        var items: [SearchPlaceItem] = rankedItems.map { mi in
            let name = mi.name ?? (mi.placemark.name ?? "Lugar")
            let subtitle: String? = {
                if let addr = mi.placemark.postalAddress {
                    return CNPostalAddressFormatter.string(from: addr, style: .mailingAddress).replacingOccurrences(of: "\\n", with: " • ")
                }
                return mi.placemark.title
            }()

            return SearchPlaceItem(
                name: name,
                subtitle: subtitle,
                coordinate: mi.placemark.coordinate
            )
        }

        // 6) Dedup simple por (name + coord redondeada)
        var seen = Set<String>()
        items = items.filter { item in
            let key = "\\(item.name.lowercased())|\\(round(item.coordinate.latitude*1e5)/1e5)|\\(round(item.coordinate.longitude*1e5)/1e5)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }

        return Array(items.prefix(limit))
    }

    // Detecta ISO country code (ej. "ES") a partir del centro del viewport
    private static func detectCountryCode(of region: MKCoordinateRegion) async -> String? {
        let loc = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        let geocoder = CLGeocoder()
        do {
            if #available(iOS 15.0, *) {
                let placemarks = try await geocoder.reverseGeocodeLocation(loc, preferredLocale: nil)
                return placemarks.first?.isoCountryCode
            } else {
                return try await withCheckedThrowingContinuation { cont in
                    geocoder.reverseGeocodeLocation(loc, preferredLocale: nil) { placemarks, error in
                        if let code = placemarks?.first?.isoCountryCode {
                            cont.resume(returning: code)
                        } else {
                            cont.resume(returning: nil)
                        }
                    }
                }
            }
        } catch {
            return nil
        }
    }
}
