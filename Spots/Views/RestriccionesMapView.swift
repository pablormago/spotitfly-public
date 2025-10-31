import SwiftUI
import MapKit

struct RestriccionesMapView: View {
    let coordinates: [CLLocationCoordinate2D]

    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038), // Madrid
        span: MKCoordinateSpan(latitudeDelta: 2.0, longitudeDelta: 2.0)
    )

    private struct MapPoint: Identifiable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
    }

    private var points: [MapPoint] {
        coordinates.map { MapPoint(coordinate: $0) }
    }

    var body: some View {
        Map(coordinateRegion: $region, annotationItems: points) { point in
            MapMarker(coordinate: point.coordinate, tint: .red)
        }
        .ignoresSafeArea()
        // 🔹 Header superpuesto por encima del mapa
        .overlay(
            VStack(spacing: 0) {
                HeaderView()
                    .padding(.top, 8)
                    .padding(.horizontal)
                Spacer()
            },
            alignment: .top
        )
        // 🔹 Ocultamos la nav bar para que no tape el header
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            fitRegionToCoordinates()
        }
    }

    private func fitRegionToCoordinates() {
        guard !coordinates.isEmpty else { return }
        // bbox simple con padding
        let lats = coordinates.map { $0.latitude }
        let lons = coordinates.map { $0.longitude }
        let minLat = lats.min() ?? 0
        let maxLat = lats.max() ?? 0
        let minLon = lons.min() ?? 0
        let maxLon = lons.max() ?? 0

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2.0,
            longitude: (minLon + maxLon) / 2.0
        )

        // padding para que no queden pegados a los bordes
        let latDelta = max((maxLat - minLat) * 1.3, 0.02)
        let lonDelta = max((maxLon - minLon) * 1.3, 0.02)

        region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        )
    }
}
