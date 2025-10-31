import Foundation
import CoreLocation
import MapKit

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    // Región visible del mapa
    @Published var region: MKCoordinateRegion
    // Última localización conocida
    @Published var location: CLLocation?
    // 🆕 Estado de permisos publicado (para UI: banners, etc.)
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let mgr = CLLocationManager()
    private var didCenterOnUser = false

    override init() {
        // Región neutra inicial
        self.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )
        super.init()

        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyBest

        // 🆕 Capturamos el estado actual antes de pedir permiso
        authorizationStatus = mgr.authorizationStatus

        // Solicita permiso e inicia actualizaciones si procede
        mgr.requestWhenInUseAuthorization()
        mgr.startUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }

        DispatchQueue.main.async {
            self.location = loc
            // Centrado automático solo la primera vez
            if !self.didCenterOnUser {
                self.region = MKCoordinateRegion(
                    center: loc.coordinate,
                    latitudinalMeters: 500,
                    longitudinalMeters: 500
                )
                self.didCenterOnUser = true
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // 🆕 Publicamos cambios de autorización para que la UI reaccione (banner, etc.)
        DispatchQueue.main.async {
            self.authorizationStatus = manager.authorizationStatus
        }

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            mgr.startUpdatingLocation()
        case .denied, .restricted:
            // Opcional: podrías parar updates si quieres
            mgr.stopUpdatingLocation()
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Acciones

    /// Centra manualmente el mapa sobre la última localización conocida (si existe)
    func centerOnUser() {
        guard let loc = location else { return }
        DispatchQueue.main.async {
            self.region = MKCoordinateRegion(
                center: loc.coordinate,
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
        }
    }
}
