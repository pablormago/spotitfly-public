import Foundation
import FirebaseFirestore
import Combine
import SwiftUI
import FirebaseAuth
import UIKit


@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published var unreadSpots: [Spot] = []
    @Published var badgeCount: Int = 0

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var badgeListener: ListenerRegistration?

    private var cancellables: Set<AnyCancellable> = []
    private var ownedSpots: [Spot] = []

    deinit {
        listener?.remove()
        badgeListener?.remove()        // 👈 nuevo
        cancellables.forEach { $0.cancel() }
    }

    func startListening(userId: String, spotsVM: SpotsViewModel) {
        listener?.remove()

        listener = db.collection("spots")
            .whereField("createdBy", isEqualTo: userId)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }
                if let err {
                    print("⚠️ Notifications listener error:", err)
                    return
                }
                guard let docs = snap?.documents else { return }

                var updated: [Spot] = []
                for doc in docs {
                    let data = doc.data()
                    let id = doc.documentID

                    let name = (data["name"] as? String) ?? "Sin nombre"
                    let description = (data["description"] as? String) ?? ""
                    let latitude = (data["latitude"] as? Double) ?? 0
                    let longitude = (data["longitude"] as? Double) ?? 0
                    let legacyRating = (data["rating"] as? Int) ?? 0
                    let bestDate = data["bestDate"] as? String
                    let categoryRaw = (data["category"] as? String) ?? SpotCategory.otros.rawValue
                    let category = SpotCategory(rawValue: categoryRaw) ?? .otros
                    let imageUrl = data["imageUrl"] as? String
                    let createdBy = (data["createdBy"] as? String) ?? ""
                    let createdAt: Date = (data["createdAt"] as? Timestamp)?.dateValue() ?? Date()
                    let locality = data["localidad"] as? String
                    let acceso = data["acceso"] as? String
                    let commentCount = data["commentCount"] as? Int
                    let lastCommentAt = (data["lastCommentAt"] as? Timestamp)?.dateValue()

                    var ratingsDict: [String: Int]? = nil
                    if let map = data["ratings"] as? [String: Any] {
                        ratingsDict = map.compactMapValues {
                            if let n = $0 as? NSNumber { return n.intValue }
                            if let i = $0 as? Int { return i }
                            return nil
                        }
                    }

                    let effectiveRating: Int
                    if let r = ratingsDict, !r.isEmpty {
                        let sum = r.values.reduce(0, +)
                        effectiveRating = Int((Double(sum) / Double(r.count)).rounded())
                    } else {
                        effectiveRating = legacyRating
                    }

                    let spot = Spot(
                        id: id,
                        name: name,
                        description: description,
                        latitude: latitude,
                        longitude: longitude,
                        rating: effectiveRating,
                        bestDate: bestDate,
                        category: category,
                        imageUrl: imageUrl,
                        createdBy: createdBy,
                        createdAt: createdAt,
                        locality: locality,
                        acceso: acceso,
                        commentCount: commentCount,
                        lastCommentAt: lastCommentAt,
                        ratings: ratingsDict
                    )
                    updated.append(spot)
                }

                self.ownedSpots = updated
                Task { await self.refresh(for: userId, ownedSpots: updated) }
            }

        NotificationCenter.default.publisher(for: .spotSeen)
            .sink { [weak self] notif in
                guard let self else { return }
                if let spotId = notif.object as? String {
                    self.optimisticMarkAsSeen(spotId: spotId)
                }
                Task { await self.refresh(for: userId, ownedSpots: self.ownedSpots) }
            }
            .store(in: &cancellables)
        // 👇 NUEVO: escucha el doc de contadores y aplica badge
        startBadgeListener(userId: userId)
    }

    private func refresh(for uid: String, ownedSpots: [Spot]) async {
        let unreadIds = await CommentReadService.shared.fetchUnreadSpotIds(for: uid, ownedSpots: ownedSpots)
        let unread = ownedSpots.filter { unreadIds.contains($0.id) }
        await MainActor.run {
            withAnimation {
                self.unreadSpots = unread
                self.badgeCount = unread.count
            }
        }
    }

    func optimisticMarkAsSeen(spotId: String) {
        withAnimation {
            unreadSpots.removeAll { $0.id == spotId }
            badgeCount = unreadSpots.count
        }
    }
    private func startBadgeListener(userId: String) {
        badgeListener?.remove()
        let ref = db.collection("users").document(userId)
            .collection("meta").document("counters")

        badgeListener = ref.addSnapshotListener { [weak self] snap, _ in
            guard self != nil else { return }
            let badge = (snap?.data()?["badge"] as? Int) ?? 0
            // 👇 Solo el icono del SpringBoard. NO tocar badgeCount interno ni unreadSpots aquí.
            UIApplication.shared.applicationIconBadgeNumber = badge
        }
    }


}
