//
//  WeatherHourlySheet.swift
//  Spots
//

import SwiftUI

struct WeatherHourlySheet: View {
    let lat: Double
    let lon: Double
    let isoDate: String
    let title: String

    @Environment(\.dismiss) private var dismiss

    @State private var points: [HourlyWeatherPoint] = []
    @State private var loading = true
    @State private var errorText: String? = nil

    var body: some View {
        NavigationView {
            Group {
                if loading {
                    VStack { Spacer(); ProgressView(); Spacer() }
                        .navigationTitle(title)
                } else if let errorText {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(errorText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button {
                            Task { await reload() }
                        } label: {
                            Label("Reintentar", systemImage: "arrow.clockwise")
                                .font(.subheadline.bold())
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .navigationTitle(title)
                } else {
                    List(points) { p in
                        HStack(spacing: 10) {
                            Text(p.hour)
                                .font(.subheadline.monospacedDigit())
                                .frame(width: 46, alignment: .leading)
                            Image(systemName: p.icon)
                                .font(.system(size: 20))
                                .foregroundColor(.yellow)
                                .frame(width: 28, alignment: .center)
                                .padding(.horizontal, 6)
                            Text(p.temperature)
                                .font(.subheadline)
                                .frame(width: 38, alignment: .leading)
                                .padding(.leading, 4)
                                .monospacedDigit()
                            HStack(spacing: 6) {
                                Image(systemName: "drop.fill")
                                    .foregroundColor(.blue)
                                Text("\(p.precipProb) • \(p.precipAmount)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .frame(minWidth: 90, maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 6) {
                                Image(systemName: "wind")
                                    .foregroundColor(.secondary)
                                Text(p.wind)
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                            }
                            .frame(minWidth: 90, maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .listStyle(.plain)
                    .refreshable { await reload() }
                    .navigationTitle(title)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .onAppear {
            Task { await reload() }
        }
    }

    private func reload() async {
        await MainActor.run {
            loading = true
            errorText = nil
        }
        do {
            let res = try await WeatherService.shared.fetchHourly(lat: lat, lon: lon, isoDate: isoDate)
            await MainActor.run {
                self.points = res
                self.loading = false
            }
        } catch {
            await MainActor.run {
                self.points = []
                self.loading = false
                self.errorText = "No se pudo cargar la previsión por horas."
            }
        }
    }
}
