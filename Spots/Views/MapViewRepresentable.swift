//
//  MapViewRepresentable.swift
//  Spots
//
//  Created by Pablo Jimenez on 2/9/25.
//


import SwiftUI
import MapKit

struct MapViewRepresentable: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var polygons: [MKPolygon]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.setRegion(region, animated: false)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        uiView.setRegion(region, animated: true)

        // Limpia overlays antiguos
        uiView.removeOverlays(uiView.overlays)
        uiView.addOverlays(polygons)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable

        init(_ parent: MapViewRepresentable) {
            self.parent = parent
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.strokeColor = .red
                renderer.lineWidth = 1
                renderer.fillColor = UIColor.red.withAlphaComponent(0.2)
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
    }
}
