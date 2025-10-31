//
//  SpotsViewModel.swift
//  Spots
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import CoreLocation

final class SpotsViewModel: ObservableObject {
    @Published var spots: [Spot] = []
    @Published var hasLoaded: Bool = false
    private var lastFetch: Date? = nil
    private let db = Firestore.firestore()

    // MARK: - Fetch
    func fetchSpots(force: Bool = false) {
        if let last = lastFetch, !force {
            let elapsed = Date().timeIntervalSince(last)
            if hasLoaded && elapsed < 180 { return }
        }

        // Query principal: solo públicos, ordenados por fecha
        let query = db.collection("spots")
            .whereField("visibility", isEqualTo: "public")
            .order(by: "createdAt", descending: true)

        query.getDocuments { [weak self] snap, err in
            guard let self else { return }

            // Fallback: si falla por índice o cualquier otro motivo, traemos todo y filtramos en cliente
            if let err = err {
                print("⚠️ fetchSpots (con filtro) error:", err.localizedDescription)
                self.fetchSpotsFallbackFiltering()
                return
            }

            var loaded: [Spot] = []
            snap?.documents.forEach { doc in
                let data = doc.data()

                func double(_ any: Any?) -> Double? {
                    if let d = any as? Double { return d }
                    if let n = any as? NSNumber { return n.doubleValue }
                    return nil
                }
                func int(_ any: Any?) -> Int? {
                    if let i = any as? Int { return i }
                    if let n = any as? NSNumber { return n.intValue }
                    return nil
                }
                func dateFromCreatedAt(_ any: Any?) -> Date {
                    if let ts = any as? Timestamp { return ts.dateValue() }
                    if let n = any as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue / 1000.0) }
                    if let d = any as? Double { return Date(timeIntervalSince1970: d / 1000.0) }
                    return Date(timeIntervalSince1970: 0)
                }

                // Como la query ya filtra visibility = public, no hace falta re-chequear aquí

                let id = doc.documentID
                let name = (data["name"] as? String) ?? "Sin nombre"
                let description = (data["description"] as? String) ?? ""
                let latitude = double(data["latitude"]) ?? 0
                let longitude = double(data["longitude"]) ?? 0
                let legacyRating = int(data["rating"]) ?? 0
                let bestDate = data["bestDate"] as? String
                let categoryRaw = (data["category"] as? String) ?? SpotCategory.otros.rawValue
                let category = SpotCategory(rawValue: categoryRaw) ?? .otros
                let imageUrl = data["imageUrl"] as? String
                let createdBy = (data["createdBy"] as? String) ?? ""
                let createdAt = dateFromCreatedAt(data["createdAt"])
                let locality = data["localidad"] as? String
                let acceso = data["acceso"] as? String
                let commentCount = data["commentCount"] as? Int
                let lastCommentAt = (data["lastCommentAt"] as? Timestamp)?.dateValue()

                // ratings
                var ratingsDict: [String: Int]? = nil
                if let map = data["ratings"] as? [String: Any] {
                    ratingsDict = map.compactMapValues {
                        if let n = $0 as? NSNumber { return n.intValue }
                        if let i = $0 as? Int { return i }
                        return nil
                    }
                }

                let averageRating = double(data["averageRating"])
                let ratingsCount = int(data["ratingsCount"])

                // Compatibilidad rating efectivo
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
                    ratings: ratingsDict,
                    averageRating: averageRating,
                    ratingsCount: ratingsCount
                )
                loaded.append(spot)
            }

            DispatchQueue.main.async {
                self.spots = loaded
                self.hasLoaded = true
                self.lastFetch = Date()
            }

            let uids = Set(loaded.map { $0.createdBy })
            Task.detached {
                for uid in uids { _ = await UserService.shared.username(for: uid) }
            }
        }
    }

    // Fallback: sin índice → traemos todo y filtramos por visibility en cliente
    private func fetchSpotsFallbackFiltering() {
        db.collection("spots")
            .order(by: "createdAt", descending: true)
            .getDocuments { [weak self] snap, err in
                guard let self else { return }
                if let err {
                    print("⚠️ fetchSpots fallback error:", err.localizedDescription)
                    return
                }

                var loaded: [Spot] = []

                snap?.documents.forEach { doc in
                    let data = doc.data()

                    // Filtrado en cliente:
                    // - Oculta "hidden" y "review"
                    // - Trata visibility nil como público (compat con legacy)
                    let visibility = data["visibility"] as? String ?? "public"
                    guard visibility == "public" else { return }

                    func double(_ any: Any?) -> Double? {
                        if let d = any as? Double { return d }
                        if let n = any as? NSNumber { return n.doubleValue }
                        return nil
                    }
                    func int(_ any: Any?) -> Int? {
                        if let i = any as? Int { return i }
                        if let n = any as? NSNumber { return n.intValue }
                        return nil
                    }
                    func dateFromCreatedAt(_ any: Any?) -> Date {
                        if let ts = any as? Timestamp { return ts.dateValue() }
                        if let n = any as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue / 1000.0) }
                        if let d = any as? Double { return Date(timeIntervalSince1970: d / 1000.0) }
                        return Date(timeIntervalSince1970: 0)
                    }

                    let id = doc.documentID
                    let name = (data["name"] as? String) ?? "Sin nombre"
                    let description = (data["description"] as? String) ?? ""
                    let latitude = double(data["latitude"]) ?? 0
                    let longitude = double(data["longitude"]) ?? 0
                    let legacyRating = int(data["rating"]) ?? 0
                    let bestDate = data["bestDate"] as? String
                    let categoryRaw = (data["category"] as? String) ?? SpotCategory.otros.rawValue
                    let category = SpotCategory(rawValue: categoryRaw) ?? .otros
                    let imageUrl = data["imageUrl"] as? String
                    let createdBy = (data["createdBy"] as? String) ?? ""
                    let createdAt = dateFromCreatedAt(data["createdAt"])
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

                    let averageRating = double(data["averageRating"])
                    let ratingsCount = int(data["ratingsCount"])

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
                        ratings: ratingsDict,
                        averageRating: averageRating,
                        ratingsCount: ratingsCount
                    )
                    loaded.append(spot)
                }

                DispatchQueue.main.async {
                    self.spots = loaded
                    self.hasLoaded = true
                    self.lastFetch = Date()
                }

                let uids = Set(loaded.map { $0.createdBy })
                Task.detached {
                    for uid in uids { _ = await UserService.shared.username(for: uid) }
                }
            }
    }


    func fetchSpotsAsync(force: Bool = false) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.fetchSpots(force: force)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                cont.resume()
            }
        }
    }

    // MARK: - ✅ Favoritos: marcar los spots como favoritos del usuario
    @MainActor
    func syncFavorites(favorites: Set<String>) {
        guard !spots.isEmpty else { return }
        // 👉 Crear NUEVO array para forzar publicación de @Published
        let updated = spots.map { old -> Spot in
            var s = old
            s.isFavorite = favorites.contains(s.id)
            return s
        }
        // Evitar publicación si no hay cambios efectivos (opcional)
        if updated != spots {
            spots = updated
        }
    }
    
    @MainActor
    func applyFavorite(id: String, isFavorite: Bool) {
        guard let idx = spots.firstIndex(where: { $0.id == id }) else { return }
        var sp = spots[idx]
        guard sp.isFavorite != isFavorite else { return }
        sp.isFavorite = isFavorite
        spots[idx] = sp   // <- @Published dispara actualización y el sheet re-pinta el corazón
    }


    // MARK: - Add
    func addSpot(
        name: String,
        description: String,
        latitude: Double,
        longitude: Double,
        rating: Int,
        bestDate: String?,
        category: SpotCategory,
        imageUrl: String?,
        acceso: String? = nil
    ) async throws {
        guard let uid = Auth.auth().currentUser?.uid else {
            throw NSError(domain: "SpotsVM", code: 401, userInfo: [NSLocalizedDescriptionKey: "No hay usuario logado"])
        }

        let id = UUID().uuidString
        let createdAt = Date()
        let locality = await GeocodingService.shared.locality(for: latitude, longitude: longitude)

        let ratingsMap: [String: Int] = [uid: rating]

        // Guardamos todos los campos
        var data: [String: Any] = [
            "id": id,
            "name": name,
            "description": description,
            "latitude": latitude,
            "longitude": longitude,
            "bestDate": bestDate as Any,
            "category": category.rawValue,
            "imageUrl": imageUrl as Any,
            "createdBy": uid,
            "createdAt": Timestamp(date: createdAt),
            "commentCount": 0,
            "ratings": ratingsMap,
            "rating": rating,
            "averageRating": Double(rating),
            "ratingsCount": 1
        ]
        if let locality, !locality.isEmpty { data["localidad"] = locality }
        if let acceso, !acceso.isEmpty { data["acceso"] = acceso }

        try await setDataWithTimeout(
            ref: db.collection("spots").document(id),
            data: data,
            merge: false,
            timeoutSeconds: 4.0
        )

        let newSpot = Spot(
            id: id,
            name: name,
            description: description,
            latitude: latitude,
            longitude: longitude,
            rating: rating,
            bestDate: bestDate,
            category: category,
            imageUrl: imageUrl,
            createdBy: uid,
            createdAt: createdAt,
            locality: locality,
            acceso: acceso,
            commentCount: 0,
            lastCommentAt: nil,
            ratings: ratingsMap,
            averageRating: Double(rating),
            ratingsCount: 1
        )
        await MainActor.run { self.spots.append(newSpot) }
    }

    // MARK: - Update
    func updateSpot(_ updated: Spot) async throws {
        let docRef = db.collection("spots").document(updated.id)

        var localityToSave: String? = updated.locality
        let shouldResolveLocality = (updated.locality?.isEmpty ?? true)
        if shouldResolveLocality {
            localityToSave = await GeocodingService.shared.locality(for: updated.latitude, longitude: updated.longitude)
        }

        var data: [String: Any] = [
            "name": updated.name,
            "description": updated.description,
            "latitude": updated.latitude,
            "longitude": updated.longitude,
            "rating": updated.rating,
            "bestDate": updated.bestDate as Any,
            "category": updated.category.rawValue,
            "imageUrl": updated.imageUrl as Any,
            "createdBy": updated.createdBy,
            "createdAt": Timestamp(date: updated.createdAt),
            "commentCount": updated.commentCount as Any,
            "lastCommentAt": updated.lastCommentAt as Any
        ]
        if let r = updated.ratings { data["ratings"] = r }
        if let avg = updated.averageRating { data["averageRating"] = avg }
        if let count = updated.ratingsCount { data["ratingsCount"] = count }
        if let localityToSave, !localityToSave.isEmpty { data["localidad"] = localityToSave }
        if let acceso = updated.acceso, !acceso.isEmpty { data["acceso"] = acceso }

        try await setDataWithTimeout(ref: docRef, data: data, merge: true, timeoutSeconds: 4.0)

        await MainActor.run {
            if let idx = self.spots.firstIndex(where: { $0.id == updated.id }) {
                var copy = updated
                copy.locality = localityToSave
                self.spots[idx] = copy
            }
        }
    }

    // MARK: - Votar / cambiar rating
    func setMyRating(spotId: String, value: Int) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let ref = db.collection("spots").document(spotId)

        let snap = try await ref.getDocument()
        var ratingsMap: [String: Int] = [:]
        if let map = snap.data()?["ratings"] as? [String: Any] {
            ratingsMap = map.compactMapValues {
                if let n = $0 as? NSNumber { return n.intValue }
                if let i = $0 as? Int { return i }
                return nil
            }
        }
        ratingsMap[uid] = value

        let sum = ratingsMap.values.reduce(0, +)
        let avgDouble = Double(sum) / Double(ratingsMap.count)
        let avgInt = Int(avgDouble.rounded())

        try await setDataWithTimeout(
            ref: ref,
            data: [
                "ratings": ratingsMap,
                "rating": avgInt,
                "averageRating": avgDouble,
                "ratingsCount": ratingsMap.count
            ],
            merge: true,
            timeoutSeconds: 4.0
        )

        await MainActor.run {
            if let i = self.spots.firstIndex(where: { $0.id == spotId }) {
                self.spots[i].ratings = ratingsMap
                self.spots[i].rating = avgInt
                self.spots[i].averageRating = avgDouble
                self.spots[i].ratingsCount = ratingsMap.count
            }
        }
    }

    // MARK: - Delete
    func deleteSpot(id: String) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    self.db.collection("spots").document(id).delete { error in
                        if let error { cont.resume(throwing: error) }
                        else { cont.resume(returning: ()) }
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 3_500_000_000)
                throw NSError(domain: "SpotsVM", code: -2, userInfo: [NSLocalizedDescriptionKey: "Timeout al borrar"])
            }
            _ = try await group.next()
            group.cancelAll()
        }

        await MainActor.run {
            spots.removeAll { $0.id == id }
        }
    }

    // MARK: - Helper setData con timeout
    private func setDataWithTimeout(ref: DocumentReference,
                                    data: [String: Any],
                                    merge: Bool,
                                    timeoutSeconds: Double) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                    ref.setData(data, merge: merge) { error in
                        if let error { cont.resume(throwing: error) }
                        else { cont.resume(returning: ()) }
                    }
                }
            }
            group.addTask {
                let ns = UInt64(timeoutSeconds * 1_000_000_000)
                try await Task.sleep(nanoseconds: ns)
                throw NSError(domain: "SpotsVM", code: -1, userInfo: [NSLocalizedDescriptionKey: "Timeout Firestore setData"])
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }
}
