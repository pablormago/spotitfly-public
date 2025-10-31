//
//  SpotWeatherCompact.swift
//  Spots
//

import SwiftUI
import Foundation

struct SpotWeatherCompact: View {
    let lat: Double
    let lon: Double

    @State private var today: WeatherDayData? = nil
    @State private var isLoading = false

    private var hasData: Bool { today != nil }

    // Solo mostrar la temperatura máxima (formato "min° / max°")
    private var maxTempOnly: String {
        guard let t = today?.temperature else { return "" }
        let comps = t.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }
        return comps.last ?? t
    }

    var body: some View {
        // Usamos contenedor real (no Group) para garantizar onAppear en listas
        HStack(spacing: 6) {
            if hasData, let d = today {
                Image(systemName: d.icon)
                    .font(.system(size: 14))
                    .foregroundColor(.yellow)          // fijo amarillo
                Text("\(d.day) \(d.date) • \(maxTempOnly) • \(d.wind)")
                    .font(.caption)
                    .foregroundColor(.black)           // fijo negro
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            } else {
                // placeholder invisible para mantener altura/espacio
                Text(" ")
                    .font(.caption)
                    .opacity(0.0)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(height: 26)
        .background(Color(white: 0.9))                 // gris claro fijo
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
        )
        .cornerRadius(8)

        // 🔎 Carga forzada al aparecer (además del cambio de coords)
        .onAppear {
            print("🌤️ [Compact] onAppear lat:\(lat) lon:\(lon)")
            Task { await loadIfNeeded(reason: "onAppear") }
        }
        .onChange(of: lat) { _ in
            print("🌤️ [Compact] onChange lat -> \(lat)")
            Task { await loadIfNeeded(reason: "latChanged") }
        }
        .onChange(of: lon) { _ in
            print("🌤️ [Compact] onChange lon -> \(lon)")
            Task { await loadIfNeeded(reason: "lonChanged") }
        }
    }

    private func loadIfNeeded(reason: String) async {
        if hasData {
            print("🌤️ [Compact] \(reason) → ya hay datos, no recargo")
            return
        }
        if isLoading {
            print("🌤️ [Compact] \(reason) → ya cargando, skip")
            return
        }
        guard lat != 0, lon != 0 else {
            print("🌤️ [Compact] \(reason) → coords 0,0 → skip")
            return
        }

        isLoading = true
        defer { isLoading = false }

        print("🌤️ [Compact] \(reason) → fetching 15d for \(lat),\(lon)")
        do {
            let result = try await WeatherService.shared.fetch15DayForecast(lat: lat, lon: lon)
            print("🌤️ [Compact] recibido \(result.count) días")
            if let first = result.first {
                await MainActor.run { self.today = first }
                print("🌤️ [Compact] hoy: \(first.day) \(first.date) • \(first.temperature) • \(first.wind)")
            } else {
                print("🌤️ [Compact] vacío (sin días)")
            }
        } catch {
            print("🌤️ [Compact] ❌ error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Helpers
private extension Double {
    func rounded(to decimals: Int) -> Double {
        let p = pow(10.0, Double(decimals))
        return (self * p).rounded() / p
    }
}
