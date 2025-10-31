//
//  NotificationsSheetView.swift
//  Spots
//
//  Created by Pablo Jimenez on 22/9/25.
//

import SwiftUI
import FirebaseAuth
import CoreLocation

struct NotificationsSheetView: View {
    @EnvironmentObject var notificationsVM: NotificationsViewModel
    @EnvironmentObject var spotsVM: SpotsViewModel
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var favoritesVM: FavoritesViewModel   // ❤️ para sincronizar favoritos

    @State private var selectedSpot: Spot?

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(notificationsVM.unreadSpots, id: \.id) { spot in
                        SpotRow(
                            spot: spot,
                            userCoordinate: locationManager.location?.coordinate,
                            onOpenDirections: { openDirections(for: spot) }
                        )
                        .environmentObject(favoritesVM)
                        .onTapGesture {
                            selectedSpot = spot
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 14)
            }
            .navigationTitle("Nuevos comentarios")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(item: $selectedSpot) { spot in
            SpotDetailView(spot: spot)
                .presentationDetents([.large])
                .environmentObject(spotsVM)
                .environmentObject(favoritesVM)
                .onDisappear {
                    Task {
                        if let uid = Auth.auth().currentUser?.uid {
                            // 🔴 Optimistic update inmediato
                            notificationsVM.optimisticMarkAsSeen(spotId: spot.id)

                            // ✅ Persistir en Firestore
                            await CommentReadService.shared.markSeen(spotId: spot.id, userId: uid)

                            // 🔔 Reforzar con notificación local
                            NotificationCenter.default.post(name: .spotSeen, object: spot.id)
                        }
                    }
                }
        }
    }

    // MARK: - Abrir rutas
    private func openDirections(for spot: Spot) {
        NavigationHelper.openDirections(to: spot)
    }

}
