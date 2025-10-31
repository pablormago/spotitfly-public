//
//  AirspaceFilledDebugView.swift
//  Spots
//
//  Vista de DEBUG con MKMapView para probar rellenos reales (MKPolygonRenderer)
//  sin interferir con el mapa principal. NOMBRES RENOMBRADOS para evitar colisiones.
//

import SwiftUI
import MapKit
import CoreLocation

// Pins básicos para debug (coincide con lo que pasas desde SpotsMapView)
struct SpotPin {
    let title: String?
    let coordinate: CLLocationCoordinate2D
}

// Anotación SOLO para esta vista de debug (no colisiona con SpotMKAnnotation del mapa principal)
final class DebugSpotAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    init(title: String?, coordinate: CLLocationCoordinate2D) {
        self.title = title
        self.coordinate = coordinate
        super.init()
    }
}

// MARK: - View principal de la sheet de debug
struct AirspaceFilledDebugView: View {
    let region: MKCoordinateRegion
    let features: [AirspaceFeature]
    let visibleSources: Set<AirspaceSource>
    let enabled: Bool
    let spots: [SpotPin]

    var body: some View {
        DebugFilledOverlaysMapView(
            region: region,
            features: features,
            visibleSources: visibleSources,
            overlaysEnabled: enabled,
            spots: spots
        )
        .ignoresSafeArea()
    }
}

// MARK: - UIViewRepresentable renombrado (NO usar AirspaceMapUIKitView aquí)
struct DebugFilledOverlaysMapView: UIViewRepresentable {
    let region: MKCoordinateRegion
    let features: [AirspaceFeature]
    let visibleSources: Set<AirspaceSource>
    let overlaysEnabled: Bool
    let spots: [SpotPin]

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false

        map.showsUserLocation = true
        // Fuerza arranque del user-dot y luego vuelve a .none en el siguiente runloop
        map.setUserTrackingMode(.follow, animated: false)
        DispatchQueue.main.async { map.setUserTrackingMode(.none, animated: false) }

        map.mapType = .standard
        map.setRegion(region, animated: false)

        // Primera pintura
        context.coordinator.reload(
            map: map,
            region: region,
            features: features,
            visibleSources: visibleSources,
            overlaysEnabled: overlaysEnabled,
            spots: spots
        )
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        // Re-render por si cambian datos/toggles
        context.coordinator.reload(
            map: map,
            region: region,
            features: features,
            visibleSources: visibleSources,
            overlaysEnabled: overlaysEnabled,
            spots: spots
        )

        // --- Re-disparo del user-dot si no llegó aún la localización ---
        let status = CLLocationManager.authorizationStatus()
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            if !map.showsUserLocation {
                print("🧷 [DEBUG] showsUserLocation was OFF → ON")
                map.showsUserLocation = true
            } else if map.userLocation.location == nil {
                print("🧷 [DEBUG] userLocation is nil → retrigger showsUserLocation")
                map.showsUserLocation = false
                DispatchQueue.main.async { map.showsUserLocation = true }
            }
        } else {
            print("⚠️ [DEBUG] Location auth not granted:", status.rawValue)
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        private let parent: DebugFilledOverlaysMapView

        // ✅ flags y gestor de localización de DEBUG
        private var bootstrappedUserLocation = false
        private let dbgLM = CLLocationManager()
        private weak var mapRef: MKMapView?

        init(_ parent: DebugFilledOverlaysMapView) {
            self.parent = parent
        }

        // Arranque de CoreLocation de debug (para forzar posiciones y diagnosticar permisos)
        private func startDebugLocationIfNeeded(for map: MKMapView) {
            if mapRef !== map { mapRef = map }
            dbgLM.delegate = self
            switch dbgLM.authorizationStatus {
            case .notDetermined:
                print("🧭 [DEBUG] requesting WhenInUse authorization")
                dbgLM.requestWhenInUseAuthorization()
            case .authorizedWhenInUse, .authorizedAlways:
                if CLLocationManager.locationServicesEnabled() {
                    if dbgLM.delegate == nil { dbgLM.delegate = self }
                    print("🧭 [DEBUG] starting location updates")
                    dbgLM.startUpdatingLocation()
                } else {
                    print("⚠️ [DEBUG] Location Services are disabled at OS level")
                }
            case .denied, .restricted:
                print("⛔️ [DEBUG] authorization:", dbgLM.authorizationStatus.rawValue)
            @unknown default:
                print("❓ [DEBUG] unknown authorization")
            }
        }

        // Recarga overlays y anotaciones (sin borrar MKUserLocation)
        func reload(map: MKMapView,
                    region: MKCoordinateRegion,
                    features: [AirspaceFeature],
                    visibleSources: Set<AirspaceSource>,
                    overlaysEnabled: Bool,
                    spots: [SpotPin]) {

            // Debug location bootstrap
            startDebugLocationIfNeeded(for: map)

            // Región (no animada en debug)
            if map.region.center.latitude != region.center.latitude ||
                map.region.center.longitude != region.center.longitude ||
                abs(map.region.span.latitudeDelta - region.span.latitudeDelta) > .ulpOfOne ||
                abs(map.region.span.longitudeDelta - region.span.longitudeDelta) > .ulpOfOne {
                map.setRegion(region, animated: false)
            }

            // Overlays
            map.removeOverlays(map.overlays)
            if overlaysEnabled {
                let items = features.filter { visibleSources.contains($0.source) }
                for f in items {
                    switch f.geometry {
                    case .polygon(var coords):
                        // Asegura anillo cerrado
                        if let first = coords.first, let last = coords.last,
                           (first.latitude != last.latitude || first.longitude != last.longitude) {
                            coords.append(first)
                        }
                        let poly = MKPolygon(coordinates: coords, count: coords.count)
                        poly.title = "fill|\(f.source.rawValue)|\(f.kind.rawValue)"
                        map.addOverlay(poly, level: .aboveRoads)

                        // Doble contorno
                        let halo = MKPolyline(coordinates: coords, count: coords.count)
                        halo.title = "halo|\(f.source.rawValue)|\(f.kind.rawValue)"
                        map.addOverlay(halo, level: .aboveRoads)

                        let stroke = MKPolyline(coordinates: coords, count: coords.count)
                        stroke.title = "stroke|\(f.source.rawValue)|\(f.kind.rawValue)"
                        map.addOverlay(stroke, level: .aboveRoads)

                    case .polyline(let coords):
                        let halo = MKPolyline(coordinates: coords, count: coords.count)
                        halo.title = "halo|\(f.source.rawValue)|\(f.kind.rawValue)"
                        map.addOverlay(halo, level: .aboveRoads)

                        let stroke = MKPolyline(coordinates: coords, count: coords.count)
                        stroke.title = "stroke|\(f.source.rawValue)|\(f.kind.rawValue)"
                        map.addOverlay(stroke, level: .aboveRoads)
                    }
                }
            }

            // Anotaciones (sin borrar el “puntito azul” del sistema)
            let toRemove = map.annotations.filter { !($0 is MKUserLocation) }
            map.removeAnnotations(toRemove)
            for p in spots {
                let ann = DebugSpotAnnotation(title: p.title, coordinate: p.coordinate)
                map.addAnnotation(ann)
            }
        }

        // Colores por FUENTE (no por kind) para este debug
        private func styleFor(sourceRaw: String, kindRaw: String) -> (stroke: UIColor, halo: UIColor, line: CGFloat, fill: UIColor) {
            let halo = UIColor.white.withAlphaComponent(0.9)
            switch AirspaceSource(rawValue: sourceRaw) {
            case .some(.restricciones):
                return (UIColor.systemRed, halo, 2.2, UIColor.systemRed.withAlphaComponent(0.28))
            case .some(.urbano):
                return (UIColor.systemPurple, halo, 2.0, UIColor.systemPurple.withAlphaComponent(0.24))
            case .some(.medioambiente):
                return (UIColor.systemGreen, halo, 2.0, UIColor.systemGreen.withAlphaComponent(0.26))
            case .some(.infraestructura):
                return (UIColor.systemGray, halo, 1.8, UIColor.systemGray.withAlphaComponent(0.16))
            case .none:
                return (UIColor.gray, halo, 1.8, UIColor.gray.withAlphaComponent(0.18))
            }
        }

        // MARK: - MKMapViewDelegate (DEBUG user dot)

        // ¿se añade la vista del MKUserLocation?
        func mapView(_ mapView: MKMapView, didAdd views: [MKAnnotationView]) {
            for v in views {
                if v.annotation is MKUserLocation {
                    print("🟦 [DEBUG] MKUserLocation view ADDED")
                    v.displayPriority = .required
                    v.zPriority = .max
                }
            }
        }

        // ¿llega posición nativa al MKMapView?
        func mapView(_ mapView: MKMapView, didUpdate userLocation: MKUserLocation) {
            let c = userLocation.location?.coordinate
            print("📍 [DEBUG] MKUserLocation UPDATED:", c as Any)
            if !bootstrappedUserLocation {
                bootstrappedUserLocation = true
                mapView.setUserTrackingMode(.none, animated: false)   // dejamos de seguir
            }
        }

        // ¿ocurre algún problema con la anotación de usuario?
        func mapView(_ mapView: MKMapView, didFailToLocateUserWithError error: Error) {
            print("❌ [DEBUG] didFailToLocateUserWithError:", error.localizedDescription)
        }

        // Pins de debug: marker simple
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation { return nil }
            guard annotation is DebugSpotAnnotation else { return nil }

            let id = "debug-pin"
            var view = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView
            if view == nil {
                view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
                view?.canShowCallout = false
                view?.displayPriority = .defaultHigh
                view?.zPriority = .max
                view?.markerTintColor = .systemBlue
                view?.glyphImage = UIImage(systemName: "info.circle.fill")
            } else {
                view?.annotation = annotation
            }
            return view
        }
    }
}

// MARK: - CLLocationManagerDelegate (debug)
extension DebugFilledOverlaysMapView.Coordinator: CLLocationManagerDelegate {
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        print("🧭 [DEBUG] auth changed →", manager.authorizationStatus.rawValue)
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let c = locations.last?.coordinate
        print("📡 [DEBUG] didUpdateLocations:", c as Any)

        // Si el MKMapView no ha arrancado su user-dot, le damos un empujón
        DispatchQueue.main.async { [weak self] in
            guard let map = self?.mapRef else { return }
            if map.userLocation.location == nil {
                print("🪫 [DEBUG] MKMapView userLocation still nil → retrigger showsUserLocation")
                map.showsUserLocation = false
                map.showsUserLocation = true
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ [DEBUG] CoreLocation failed:", error.localizedDescription)
    }
}
