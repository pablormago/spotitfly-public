//
//  SpotComment.swift
//  Spots
//

import Foundation

struct SpotComment: Identifiable, Equatable {
    let id: String
    let text: String
    let authorId: String
    let authorName: String?
    let createdAt: Date

    /// 🆕 estado opcional en Firestore: "hidden", "review", "visible"…
    /// Si no existe, lo consideramos visible para compatibilidad.
    let status: String?

    init(
        id: String,
        text: String,
        authorId: String,
        authorName: String?,
        createdAt: Date,
        status: String? = nil
    ) {
        self.id = id
        self.text = text
        self.authorId = authorId
        self.authorName = authorName
        self.createdAt = createdAt
        self.status = status
    }

    /// visible por defecto si no hay status
    var isVisible: Bool {
        guard let s = status?.lowercased() else { return true }
        return s == "visible" || s == "public"
    }

    /// si quieres tratar "review" como NO visible, deja return false para "review"
    var isHiddenOrReview: Bool {
        guard let s = status?.lowercased() else { return false }
        return s == "hidden" || s == "review"
    }
}
