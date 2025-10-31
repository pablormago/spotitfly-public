//
//  UserSpotsListView.swift
//  Spots
//
//  Created by Pablo Jimenez on 13/10/25.
//


//
//  UserSpotsListView.swift
//  Spots
//
//  Lista de spots creados por el usuario actual.
//  - UI de cada fila idéntica a las cards de deep‑links (ChatDetailView → SpotsLinkCard).
//  - Tap: abre SpotDetailView usando el MISMO flujo del chat (in‑memory si existe, si no hidrata desde Firestore).
//  - Se presenta desde UserProfileView con un NavigationLink.
//
import SwiftUI
import FirebaseAuth
import FirebaseFirestore

struct UserSpotsListView: View {
    @EnvironmentObject var spotsVM: SpotsViewModel
    @EnvironmentObject var favoritesVM: FavoritesViewModel
    @EnvironmentObject var userSession: UserSession

    @StateObject private var vm = UserSpotsListVM()

    // sheet como en ChatDetailView
    @State private var sheetSpot: Spot? = nil
    private let db = Firestore.firestore()

    var body: some View {
        List {
            ForEach(vm.spots) { sp in
                Button {
                    openSpot(sp.id)
                } label: {
                    SpotMiniCard(spot: sp)
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("Mis Spots")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.startListening() }
        .onDisappear { vm.stopListening() }
        .sheet(item: $sheetSpot) { spot in
            SpotDetailView(spot: spot)
                .environmentObject(userSession)
                .environmentObject(spotsVM)
                .environmentObject(favoritesVM)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .ignoresSafeArea()
                .environment(\.fromChat, true)   // 👈
        }
    }

    // == Apertura igual que ChatDetailView ==
    private func openSpot(_ id: String) {
        // 1) Intenta abrir desde memoria (SpotsViewModel ya poblado)
        if let sp = spotsVM.spots.first(where: { $0.id == id }) {
            spotsVM.syncFavorites(favorites: favoritesVM.favoriteIds)
            sheetSpot = spotsVM.spots.first(where: { $0.id == id }) ?? sp
            return
        }
        // 2) Hidrata desde Firestore y abre el sheet al terminar
        db.collection("spots").document(id).getDocument { snap, err in
            if let err = err {
                print("❌ Firestore error cargando spot \(id): \(err.localizedDescription)")
                return
            }
            do {
                guard let snap, snap.exists else { return }
                let sp: Spot = try snap.data(as: Spot.self)
                var sp2 = sp
                sp2.isFavorite = favoritesVM.favoriteIds.contains(sp.id)
                DispatchQueue.main.async {
                    spotsVM.syncFavorites(favorites: favoritesVM.favoriteIds)
                    sheetSpot = spotsVM.spots.first(where: { $0.id == id }) ?? sp2
                }
            } catch {
                print("❌ Decoding Spot falló para \(id): \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - VM (suscripción a spots del usuario)
final class UserSpotsListVM: ObservableObject {
    @Published var spots: [Spot] = []
    private var listener: ListenerRegistration? = nil
    private let db = Firestore.firestore()

    func startListening() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        stopListening()
        listener = db.collection("spots")
            .whereField("createdBy", isEqualTo: uid)
            .order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }
                if let err { print("⚠️ listen my spots:", err.localizedDescription); return }
                let docs = snap?.documents ?? []
                do {
                    self.spots = try docs.compactMap { try $0.data(as: Spot.self) }
                } catch {
                    print("❌ decode my spots:", error.localizedDescription)
                }
            }
    }

    func stopListening() {
        listener?.remove()
        listener = nil
    }
}

// MARK: - UI: mini-card idéntica a deep‑links
fileprivate struct SpotMiniCard: View {
    let spot: Spot
    var body: some View {
        HStack(spacing: 10) {
            CachedImageView(urlString: spot.imageUrl, height: 56, cornerRadius: 8)
                .frame(width: 56, height: 56)
                .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(spot.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let loc = spot.locality, !loc.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle")
                        Text(loc)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if spot.ratingMean > 0 {
                    HStack(spacing: 6) {
                        TinyStarRating(value: spot.ratingMean)
                        Text(String(format: "%.1f", spot.ratingMean))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.gray.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// Copiamos la versión tiny usada en ChatDetailView para que quede igual
fileprivate struct TinyStarRating: View {
    let value: Double
    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<5, id: \.self) { i in
                let filled = Double(i+1) <= round(value)
                Image(systemName: filled ? "star.fill" : "star")
                    .font(.caption2)
            }
        }
        .foregroundStyle(.yellow)
    }
}
