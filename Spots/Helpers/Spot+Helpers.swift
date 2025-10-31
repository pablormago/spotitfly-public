// MARK: - Spot+Helpers.swift
//  Spots
//
//  Utilidades simples para validación y exportación (sin tocar el modelo base)

import Foundation
import FirebaseFirestore

extension Spot {
    func asFirestoreDict() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "description": description,
            "latitude": latitude,
            "longitude": longitude,
            "rating": rating,
            "category": category.rawValue,
            "createdBy": createdBy,
            "createdAt": Timestamp(date: createdAt),
            "commentCount": commentCount ?? 0,
        ]
        if let imageUrl { dict["imageUrl"] = imageUrl }
        if let locality { dict["localidad"] = locality }
        if let acceso { dict["acceso"] = acceso }
        if let averageRating { dict["averageRating"] = averageRating }
        if let ratingsCount { dict["ratingsCount"] = ratingsCount }
        return dict
    }
}
// MARK: - Spot+Helpers.swift
//  Spots
//
//  Utilidades simples para validación y exportación (sin tocar el modelo base)

import Foundation

extension Spot {
    func firestoreData() -> [String: Any] {
        var dict: [String: Any] = [
            "id": id,
            "name": name,
            "description": description,
            "latitude": latitude,
            "longitude": longitude,
            "rating": rating,
            "category": category.rawValue,
            "createdBy": createdBy,
            "createdAt": Timestamp(date: createdAt),
            "commentCount": commentCount ?? 0,
        ]
        if let imageUrl { dict["imageUrl"] = imageUrl }
        if let locality { dict["localidad"] = locality }
        if let acceso { dict["acceso"] = acceso }
        if let averageRating { dict["averageRating"] = averageRating }
        if let ratingsCount { dict["ratingsCount"] = ratingsCount }
        return dict
    }
}
