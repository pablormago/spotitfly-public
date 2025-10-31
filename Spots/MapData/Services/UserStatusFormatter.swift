//
//  UserStatusFormatter.swift
//  Spots
//

import Foundation
import FirebaseFirestore

enum UserStatusFormatter {
    static func format(from data: [String: Any]) -> String {
        let online = (data["isOnline"] as? Bool) ?? false
        if online {
            return "en línea"
        }

        // Siempre intentamos mostrar "últ. vez ..." aunque sea muy reciente
        var lastSeen: Date?
        if let ts = data["lastSeen"] as? Timestamp {
            lastSeen = ts.dateValue()
        } else if let ms = data["lastSeen"] as? Double {
            lastSeen = Date(timeIntervalSince1970: ms / 1000.0)
        } else if let secs = data["lastSeen"] as? Int {
            lastSeen = Date(timeIntervalSince1970: Double(secs))
        }

        guard let lastSeen else { return "desconocido" }

        let diff = Date().timeIntervalSince(lastSeen)
        if diff < 60 {
            return "últ. vez hace 1 min"
        } else if diff < 3600 {
            let mins = Int(diff / 60)
            return "últ. vez hace \(mins) min"
        } else if diff < 48 * 3600 {
            let hours = Int(diff / 3600)
            return "últ. vez hace \(hours) h"
        } else {
            let df = DateFormatter()
            df.dateStyle = .medium
            df.timeStyle = .short
            return "últ. vez \(df.string(from: lastSeen))"
        }
    }
}
