import SwiftUI
import MapKit

struct MapOverlay: UIViewRepresentable {
    let overlays: [MKOverlay]
    @Binding var region: MKCoordinateRegion

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.setRegion(region, animated: false)
        return map
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        if !regionsEqual(uiView.region, region) {
            uiView.setRegion(region, animated: true)
        }
        // Refresca overlays
        uiView.removeOverlays(uiView.overlays)
        uiView.addOverlays(overlays)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let r = MKPolygonRenderer(polygon: polygon)
                r.strokeColor = UIColor.systemRed
                r.fillColor = UIColor.systemRed.withAlphaComponent(0.25)
                r.lineWidth = 2
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }

    private func regionsEqual(_ a: MKCoordinateRegion, _ b: MKCoordinateRegion) -> Bool {
        abs(a.center.latitude - b.center.latitude) < 1e-6 &&
        abs(a.center.longitude - b.center.longitude) < 1e-6 &&
        abs(a.span.latitudeDelta - b.span.latitudeDelta) < 1e-6 &&
        abs(a.span.longitudeDelta - b.span.longitudeDelta) < 1e-6
    }
}
