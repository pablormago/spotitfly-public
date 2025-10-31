//
//  WeatherService.swift
//  Spots
//

import Foundation

// MARK: - Modelo público
public struct WeatherDayData: Identifiable {
    public let id = UUID()
    public let day: String        // "LUN"
    public let date: String       // "30 SEP"
    public let temperature: String // "14° / 22°" (min / max)
    public let wind: String        // "↗︎ 18 km/h"
    public let icon: String        // nombre de SF Symbol o asset
    public let isoDate: String     // "YYYY-MM-DD" para recuperar horas del día
}

public struct HourlyWeatherPoint: Identifiable {
    public let id = UUID()
    public let hour: String        // "13:00"
    public let temperature: String // "22°"
    public let precipProb: String  // "40%"
    public let precipAmount: String// "1.2 mm"
    public let wind: String        // "↗︎ 18 km/h"
    public let icon: String        // símbolo/asset
}

enum WeatherServiceError: Error {
    case invalidURL
    case badResponse
    case decoding
}

final class WeatherService {
    static let shared = WeatherService()
    private init() {}

    // MARK: - 15 días (diario)
    func fetch15DayForecast(lat: Double, lon: Double) async throws -> [WeatherDayData] {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: String(lat)),
            .init(name: "longitude", value: String(lon)),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,wind_speed_10m_max,wind_direction_10m_dominant"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "15"),
            .init(name: "windspeed_unit", value: "kmh")
        ]
        guard let url = comps.url else { throw WeatherServiceError.invalidURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WeatherServiceError.badResponse }

        let dto = try JSONDecoder().decode(OpenMeteoDaily.self, from: data)
        return mapToWeatherDayData(dto)
    }

    // MARK: - Horario para un día concreto
    func fetchHourly(lat: Double, lon: Double, isoDate: String) async throws -> [HourlyWeatherPoint] {
        var comps = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        comps.queryItems = [
            .init(name: "latitude", value: String(lat)),
            .init(name: "longitude", value: String(lon)),
            .init(name: "hourly", value: "weather_code,temperature_2m,precipitation_probability,precipitation,wind_speed_10m,wind_direction_10m"),
            .init(name: "timezone", value: "auto"),
            .init(name: "windspeed_unit", value: "kmh"),
            .init(name: "start_date", value: isoDate),
            .init(name: "end_date", value: isoDate)
        ]
        guard let url = comps.url else { throw WeatherServiceError.invalidURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw WeatherServiceError.badResponse }

        let dto = try JSONDecoder().decode(OpenMeteoHourly.self, from: data)
        return mapToHourlyData(dto)
    }

    // MARK: - Mapeos
    private func mapToWeatherDayData(_ input: OpenMeteoDaily) -> [WeatherDayData] {
        let locale = Locale(identifier: "es_ES")
        let dfIn = ISO8601DateFormatter()
        dfIn.formatOptions = [.withFullDate, .withDashSeparatorInDate]

        var out: [WeatherDayData] = []
        let d = input.daily
        let count = min(d.time.count,
                        d.temperature_2m_min.count,
                        d.temperature_2m_max.count,
                        d.wind_speed_10m_max.count,
                        d.wind_direction_10m_dominant.count,
                        d.weather_code.count)

        for i in 0..<count {
            let iso = d.time[i] // "YYYY-MM-DD"
            let date = dfIn.date(from: iso) ?? Date()

            let weekday = Self.weekdayShortUpper(from: date, locale: locale) // LUN
            let dayMonth = Self.dayMonthUpper(from: date, locale: locale)    // 30 SEP

            let tmin = Int(round(d.temperature_2m_min[i]))
            let tmax = Int(round(d.temperature_2m_max[i]))
            let temp = "\(tmin)° / \(tmax)°"

            let speed = Int(round(d.wind_speed_10m_max[i]))
            let deg = d.wind_direction_10m_dominant[i]
            let arrow = Self.arrow(forDegrees: deg)
            let wind = "\(arrow) \(speed) km/h"

            let wcode = d.weather_code[i]
            let symbol = Self.symbol(for: wcode)

            out.append(.init(day: weekday, date: dayMonth, temperature: temp, wind: wind, icon: symbol, isoDate: iso))
        }
        return out
    }

    private func mapToHourlyData(_ h: OpenMeteoHourly) -> [HourlyWeatherPoint] {
        var out: [HourlyWeatherPoint] = []
        let count = min(h.hourly.time.count,
                        h.hourly.temperature_2m.count,
                        h.hourly.precipitation_probability.count,
                        h.hourly.precipitation.count,
                        h.hourly.wind_speed_10m.count,
                        h.hourly.wind_direction_10m.count,
                        h.hourly.weather_code.count)

        // Parser robusto para "YYYY-MM-DD'T'HH:mm" (Open-Meteo con timezone=auto)
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyy-MM-dd'T'HH:mm"

        let outFmt = DateFormatter()
        outFmt.locale = Locale(identifier: "es_ES")
        outFmt.timeZone = .current
        outFmt.dateFormat = "HH:mm"

        for i in 0..<count {
            let iso = h.hourly.time[i]                    // "2025-09-30T00:00"
            let date = parser.date(from: iso) ?? Date()   // si falla, ahora no debería
            let hhmm = outFmt.string(from: date)

            let t = Int(round(h.hourly.temperature_2m[i]))
            let pprob = max(0, min(100, Int(round(h.hourly.precipitation_probability[i]))))
            let pmm = max(0.0, h.hourly.precipitation[i])
            let ws = Int(round(h.hourly.wind_speed_10m[i]))
            let wdir = h.hourly.wind_direction_10m[i]
            let warrow = Self.arrow(forDegrees: wdir)

            let code = h.hourly.weather_code[i]
            let icon = Self.symbol(for: code)

            out.append(.init(
                hour: hhmm,
                temperature: "\(t)°",
                precipProb: "\(pprob)%",
                precipAmount: String(format: "%.1f mm", pmm),
                wind: "\(warrow) \(ws) km/h",
                icon: icon
            ))
        }
        return out
    }

    // MARK: - Helpers
    private static func weekdayShortUpper(from date: Date, locale: Locale) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("EEE")
        return f.string(from: date).prefix(3).uppercased(with: locale)
    }

    private static func dayMonthUpper(from date: Date, locale: Locale) -> String {
        let f = DateFormatter()
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("d MMM")
        return f.string(from: date).uppercased(with: locale)
    }

    private static func arrow(forDegrees deg: Double) -> String {
        let arrows = ["↑","↗︎","→","↘︎","↓","↙︎","←","↖︎",
                      "↑","↗︎","→","↘︎","↓","↙︎","←","↖︎"]
        let idx = Int((deg + 11.25) / 22.5) % 16
        return arrows[idx]
    }

    private static func symbol(for code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1,2,3: return "cloud.sun.fill"
        case 45,48: return "cloud.fog.fill"
        case 51,53,55,56,57: return "cloud.drizzle.fill"
        case 61,63,65,66,67: return "cloud.rain.fill"
        case 71,73,75,77: return "snow"
        case 80,81,82: return "cloud.heavyrain.fill"
        case 85,86: return "cloud.snow.fill"
        case 95: return "cloud.bolt.fill"
        case 96,99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }
}

// MARK: - DTOs Open-Meteo
private struct OpenMeteoDaily: Decodable {
    let daily: Daily
    struct Daily: Decodable {
        let time: [String]
        let weather_code: [Int]
        let temperature_2m_max: [Double]
        let temperature_2m_min: [Double]
        let wind_speed_10m_max: [Double]
        let wind_direction_10m_dominant: [Double]
    }
}

private struct OpenMeteoHourly: Decodable {
    let hourly: Hourly
    struct Hourly: Decodable {
        let time: [String]
        let weather_code: [Int]
        let temperature_2m: [Double]
        let precipitation_probability: [Double]
        let precipitation: [Double]
        let wind_speed_10m: [Double]
        let wind_direction_10m: [Double]
    }
}
