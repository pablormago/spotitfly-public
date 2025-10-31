//
//  Spot.swift
//  Spots
//

import Foundation

struct Spot: Identifiable, Decodable, Encodable, Hashable, Equatable {
    var id: String
    var name: String
    var description: String
    var latitude: Double
    var longitude: Double

    /// ⚠️ Seguimos manteniendo 'rating' por compatibilidad con vistas existentes
    var rating: Int

    var bestDate: String?
    var category: SpotCategory
    var imageUrl: String?
    var createdBy: String
    var createdAt: Date
    var locality: String?
    var acceso: String?
    var commentCount: Int?
    var lastCommentAt: Date?

    /// 🆕 Votos por usuario (uid -> 0..5). Default nil para compatibilidad.
    var ratings: [String: Int]? = nil

    /// 🆕 Media calculada y nº de votos guardados en Firestore
    var averageRating: Double? = nil
    var ratingsCount: Int? = nil

    /// 🆕 Estado SOLO LOCAL: si el spot es favorito del usuario actual.
    /// No se codifica/decodifica con Firestore.
    var isFavorite: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, description, latitude, longitude, rating, bestDate, category, imageUrl, createdBy, createdAt
        case locality = "localidad"
        case acceso
        case commentCount
        case lastCommentAt
        case ratings
        case averageRating
        case ratingsCount
        // ❌ 'isFavorite' NO va en CodingKeys → se mantiene solo en memoria
    }
}

// Helpers no intrusivos
extension Spot {
    /// Media (double) basada en 'ratings' si existe; si no, usa 'rating' legado;
    /// si Firestore ya trae 'averageRating', se prioriza esa.
    var ratingMean: Double {
        if let avg = averageRating { return avg }
        guard let ratings, !ratings.isEmpty else { return Double(rating) }
        let sum = ratings.values.reduce(0, +)
        return Double(sum) / Double(ratings.count)
    }

    /// Nº de votos. Prioriza ratingsCount de Firestore si existe.
    var ratingCount: Int {
        if let count = ratingsCount { return count }
        return ratings?.count ?? 0
    }
}

enum SpotCategory: String, CaseIterable, Codable {
    case freestyleCampoAbierto = "Freestyle campo abierto"
    case freestyleBando = "Freestyle Bando"
    case cinematico = "Cinemático"
    case racing = "Racing"
    case otros = "Otros"
}
