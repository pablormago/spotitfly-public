//
//  NavigationApp.swift
//  Spots
//
//  Created by Pablo Jimenez on 29/10/25.
//


import UIKit
import CoreLocation

enum NavigationApp: String, CaseIterable, Identifiable, Equatable {
    case apple, google, waze
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apple:  return "Apple Maps"
        case .google: return "Google Maps"
        case .waze:   return "Waze"
        }
    }
}

enum NavigationHelper {
    private static let preferredKey = "preferredNavApp"

    // Detecta apps instaladas (Apple va siempre)
    static func installedApps() -> [NavigationApp] {
        var result: [NavigationApp] = [.apple]
        let app = UIApplication.shared
        if let u = URL(string: "comgooglemaps://"), app.canOpenURL(u) { result.append(.google) }
        if let u = URL(string: "waze://"),          app.canOpenURL(u) { result.append(.waze) }
        return result
    }

    static func setPreferred(_ app: NavigationApp) {
        UserDefaults.standard.set(app.rawValue, forKey: preferredKey)
    }

    static func preferred(available: [NavigationApp]? = nil) -> NavigationApp {
        let avail = available ?? installedApps()
        if let raw = UserDefaults.standard.string(forKey: preferredKey),
           let app = NavigationApp(rawValue: raw),
           avail.contains(app) {
            return app
        }
        return avail.first ?? .apple
    }

    // Conveniencias
    static func openDirections(to spot: Spot) {
        openDirections(latitude: spot.latitude, longitude: spot.longitude)
    }

    static func openDirections(latitude: Double, longitude: Double) {
        let app = preferred(available: installedApps())
        openDirections(latitude: latitude, longitude: longitude, via: app)
    }

    static func openDirections(latitude: Double, longitude: Double, via app: NavigationApp) {
        // formateo estable con separador '.'
        let lat = String(format: "%.6f", latitude)
        let lon = String(format: "%.6f", longitude)

        let application = UIApplication.shared

        switch app {
        case .google:
            if let u = URL(string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=driving"),
               application.canOpenURL(u) {
                application.open(u); return
            }
            // fallback
            fallthrough

        case .waze:
            if app == .waze,
               let u = URL(string: "waze://?ll=\(lat),\(lon)&navigate=yes"),
               application.canOpenURL(u) {
                application.open(u); return
            }
            // fallback
            fallthrough

        case .apple:
            if let u = URL(string: "maps://?daddr=\(lat),\(lon)&dirflg=d") {
                application.open(u); return
            }
        }
    }
}
