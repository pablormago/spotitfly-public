//
//  WeatherDayView.swift
//  Spots
//

import SwiftUI

struct WeatherDayView: View {
    let day: WeatherDayData

    var body: some View {
        HStack(spacing: 10) {
            // Columna izquierda: icono grande ocupando 4 filas
            Image(systemName: day.icon)
                .font(.system(size: 48))              // más grande
                .frame(width: 60)
                .foregroundColor(colorForIcon(day.icon))
                .frame(maxHeight: .infinity, alignment: .center)

            // Columna derecha: 4 filas
            VStack(alignment: .leading, spacing: 4) {
                // 1) Fecha (día y mes) arriba
                Text(day.date)
                    .font(.subheadline.bold())
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                // 2) Día de la semana
                Text(day.day.uppercased()) // 👈 mayúsculas
                    .font(.subheadline.bold()) // mismo tamaño que la fecha
                    .foregroundColor(.primary)

                // 3) Temperatura
                Text(day.temperature)
                    .font(.subheadline)
                    .foregroundColor(.primary)

                // 4) Viento
                Text(day.wind)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 190, height: 128)               // algo más alto para 4 filas
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    private func colorForIcon(_ name: String) -> Color {
        switch name {
        case "sun.max.fill": return .yellow
        case "cloud.sun.fill": return .orange
        case "cloud.fill": return .gray
        case "cloud.rain.fill": return .blue
        case "cloud.bolt.fill": return .purple
        case "cloud.drizzle.fill": return .teal
        default: return .primary
        }
    }
}

