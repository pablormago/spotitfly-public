//
//  CommentsViewModel.swift
//  Spots
//
//  Created by Pablo Jimenez on 16/9/25.
//

import Foundation
import FirebaseFirestore

@MainActor
final class CommentsViewModel: ObservableObject {
    @Published var comments: [SpotComment] = []
    @Published var isSending: Bool = false

    let spotId: String
    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?

    init(spotId: String) {
        self.spotId = spotId
    }

    func start() {
        guard listener == nil else { return }

        // Traemos en orden cronológico, como ya hacías
        let ref = db.collection("spots").document(spotId).collection("comments")
            .order(by: "createdAt", descending: false)

        listener = ref.addSnapshotListener { [weak self] snap, _ in
            guard let self else { return }
            var out: [SpotComment] = []
            snap?.documents.forEach { doc in
                let data = doc.data()
                let text = data["text"] as? String ?? ""
                let authorId = data["authorId"] as? String ?? ""
                let authorName = data["authorName"] as? String
                let ts = data["createdAt"] as? Timestamp
                let date = ts?.dateValue() ?? Date()
                let status = data["status"] as? String // 🆕 puede no existir

                // 🔎 Filtrado en cliente:
                // - Oculta "hidden" y "review"
                // - Trata status nil como visible (compat)
                if let s = status?.lowercased(), (s == "hidden" || s == "review") {
                    return
                }

                out.append(
                    SpotComment(
                        id: doc.documentID,
                        text: text,
                        authorId: authorId,
                        authorName: authorName,
                        createdAt: date,
                        status: status
                    )
                )
            }
            self.comments = out
        }
    }


    func stop() {
        listener?.remove()
        listener = nil
    }

    func send(text: String, authorId: String, authorName: String?) async throws {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true
        defer { isSending = false }

        let ref = db.collection("spots").document(spotId).collection("comments").document()
        let data: [String: Any] = [
            "text": trimmed,
            "authorId": authorId,
            "authorName": authorName as Any,
            "createdAt": FieldValue.serverTimestamp()
        ]

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ref.setData(data) { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            }
        }

        // 🔼 Mantener contador en el doc del spot
        try await db.collection("spots").document(spotId)
            .updateData([
                "commentCount": FieldValue.increment(Int64(1)),
                "lastCommentAt": FieldValue.serverTimestamp() // ⬅️ NUEVO
            ])

        // 🔔 Notificar a vistas que usan el contador
        NotificationCenter.default.post(name: .commentsDidChange, object: spotId)
    }

    func edit(commentId: String, newText: String) async throws {
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let ref = db.collection("spots").document(spotId).collection("comments").document(commentId)
        try await ref.updateData([
            "text": trimmed,
            "editedAt": FieldValue.serverTimestamp()
        ])
    }

    func delete(commentId: String) async throws {
        let ref = db.collection("spots").document(spotId).collection("comments").document(commentId)
        try await ref.delete()

        // 🔽 Mantener contador en el doc del spot
        try await db.collection("spots").document(spotId)
            .updateData(["commentCount": FieldValue.increment(Int64(-1))])

        // 🔔 Notificar a vistas que usan el contador
        NotificationCenter.default.post(name: .commentsDidChange, object: spotId)
    }
}
