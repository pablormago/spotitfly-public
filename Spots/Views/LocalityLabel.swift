import SwiftUI

struct LocalityLabel: View {
    let latitude: Double
    let longitude: Double

    @State private var text: String?
    @State private var didFail = false

    private var key: String { "\(latitude),\(longitude)" }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "mappin.circle")
            if let text {
                Text(text)
            } else if didFail {
                Text("—") // fallback discreto si no hay datos
            } else {
                Text("Localizando…")
            }
        }
        .font(.caption)
        .foregroundColor(.secondary)
        .lineLimit(1)
        // si cambian lat/lon, vuelve a resolver
        .task(id: key) {
            didFail = false
            text = await GeocodingService.shared.locality(for: latitude, longitude: longitude)
            if text == nil { didFail = true }
        }
    }
}
