//
//  SpotWeatherSection.swift
//  Spots
//

import SwiftUI

struct SpotWeatherSection: View {
    let lat: Double
    let lon: Double
    var onSelectDay: ((WeatherDayData) -> Void)? = nil   // 🆕 callback de selección
    
    @State private var showFullForecast = false
    @State private var days: [WeatherDayData] = []
    @State private var isLoading = false
    @State private var loadError = false

    private var hasData: Bool { !isLoading && !days.isEmpty }
    private var today: WeatherDayData? { days.first }
    
    private var maxTempOnly: String {
        guard let t = today?.temperature else { return "" }
        let comps = t.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        return comps.last ?? t
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasData, let today {
                HStack(spacing: 10) {
                    Image(systemName: today.icon)
                        .font(.system(size: 24))
                        .foregroundColor(.yellow)
                    Text("\(today.day) \(today.date) • \(maxTempOnly) • \(today.wind)")
                        .font(.system(size: 14))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                    HStack(spacing: 6) {
                        Text(showFullForecast ? "Ocultar" : "15 días")
                            .font(.caption.bold())
                        Image(systemName: showFullForecast ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(.blue)
                    .allowsHitTesting(false)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(10)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut) { showFullForecast.toggle() }
                }
            }
            
            if hasData, showFullForecast {
                WeatherForecastView(days: days) { d in
                    onSelectDay?(d)   // 🆕 propagamos selección
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task(id: cacheKey) { await loadIfNeeded() }
    }

    private var cacheKey: String { "\(lat.rounded(to: 4)),\(lon.rounded(to: 4))" }

    private func loadIfNeeded() async {
        guard days.isEmpty else { return }
        await load()
    }

    private func load() async {
        guard lat != 0, lon != 0 else { return }
        isLoading = true
        loadError = false
        defer { isLoading = false }
        do {
            let result = try await WeatherService.shared.fetch15DayForecast(lat: lat, lon: lon)
            await MainActor.run { self.days = result }
        } catch {
            await MainActor.run { self.loadError = true }
        }
    }
}

private extension Double {
    func rounded(to decimals: Int) -> Double {
        let p = pow(10.0, Double(decimals))
        return (self * p).rounded() / p
    }
}
