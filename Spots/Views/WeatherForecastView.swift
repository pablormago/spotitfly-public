//
//  WeatherForecastView.swift
//  Spots
//

import SwiftUI

struct WeatherForecastView: View {
    let days: [WeatherDayData]              // ← viene desde fuera
    var onSelect: (WeatherDayData) -> Void = { _ in }  // ← callback al tocar una card

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("El Tiempo (15 días)")
                .font(.headline)
                .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {                // sin espacio extra entre cards
                    ForEach(days) { day in
                        WeatherDayView(day: day)         // tu card existente
                            .padding(.leading, 3)        // solo izquierda (compacto)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(day) }
                    }
                }
                .padding(.leading, 6)                    // margen global solo a la izquierda
            }
        }
    }
}
