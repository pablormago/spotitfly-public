//
//  FavoritesListView.swift
//  Spots
//
//  Creado como clon de SpotsListView pero mostrando solo los favoritos.
//

import SwiftUI
import CoreLocation
import UIKit

struct FavoritesListView: View {
    @EnvironmentObject var spotsVM: SpotsViewModel
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var favoritesVM: FavoritesViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var userCoordinate: CLLocationCoordinate2D?
    @State private var selectedForDetail: Spot?

    @State private var searchText: String = ""
    @State private var selectedCategory: SpotCategory? = nil
    
    // 👉 devolverás el último spot (o nil) al cerrar la lista
    let onClose: (Spot?) -> Void

    // 👉 recordamos el último spot cuyo detalle se abrió
    @State private var lastOpenedSpot: Spot? = nil
    init(onClose: @escaping (Spot?) -> Void = { _ in }) {
        self.onClose = onClose
    }

    // 🔗 compartir
    @State private var shareSpotInFavs: Spot? = nil
    @State private var showShareMenuFromFavs = false
    @State private var showChatPickerFromFavs = false

    private func enc(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        return s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private func deepLink(for spot: Spot) -> String {
        let n   = enc(spot.name)
        let img = enc(spot.imageUrl)
        let loc = enc(spot.locality)
        let rm  = String(format: "%.1f", spot.ratingMean)

        var comps = "spots://spot/\(spot.id)?n=\(n)&lat=\(spot.latitude)&lon=\(spot.longitude)&rm=\(rm)"
        if !img.isEmpty { comps += "&img=\(img)" }
        if !loc.isEmpty { comps += "&loc=\(loc)" }
        return comps
    }


    private var listItems: [Spot] { sortedFilteredFavorites }

    var body: some View {
        Group {
            if listItems.isEmpty {
                // Placeholder si no hay favoritos
                VStack(spacing: 20) {
                    Image(systemName: "heart")
                        .font(.system(size: 48))
                        .foregroundColor(.gray.opacity(0.6))
                    Text("Todavía no tienes Spots favoritos")
                        .font(.headline)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
            } else {
                listView
                    .searchable(
                        text: $searchText,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Buscar por nombre, categoría o localidad"
                    )
            }
        }
        .navigationTitle("Mis Spots favoritos")
        .navigationBarTitleDisplayMode(.large)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    onClose(lastOpenedSpot)
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "chevron.backward")
                        Text("Atrás")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    FilterMenu(selectedCategory: $selectedCategory)
                }
            }
        }
        .onAppear {
            userCoordinate = locationManager.location?.coordinate
            spotsVM.syncFavorites(favorites: favoritesVM.favoriteIds)
        }
        .onChange(of: favoritesVM.favoriteIds) { ids in
            spotsVM.syncFavorites(favorites: ids)
        }
        .onChange(of: spotsVM.spots) { _ in
            // Por si recargas spots y pierdes la marca local
            spotsVM.syncFavorites(favorites: favoritesVM.favoriteIds)
        }
        .sheet(item: $selectedForDetail) { (spot: Spot) in
            SpotDetailView(spot: spot)
                .presentationDetents([.large])
                .environmentObject(spotsVM)
                .environmentObject(favoritesVM)
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("SpotDetail.OpenInMap"))) { note in
            guard let sp = note.object as? Spot else { return }
            lastOpenedSpot = sp
            // Ejecuta tras cerrar el sheet del detalle
            DispatchQueue.main.async {
                onClose(sp)   // ⇒ cambia a pestaña Mapa y centra
                dismiss()     // ⇒ cierra Favoritos
            }
        }

        // 🔗 Selector de compartir
        .confirmationDialog("Compartir spot",
                            isPresented: $showShareMenuFromFavs,
                            titleVisibility: .visible) {
            Button("Compartir en chat…") { showChatPickerFromFavs = true }
            Button("Copiar enlace") {
                if let sp = shareSpotInFavs {
                    UIPasteboard.general.string = deepLink(for: sp)
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .sheet(isPresented: $showChatPickerFromFavs) {
            ForwardPickerSheet(currentChatId: "") { targetChatId in
                Task {
                    if let sp = shareSpotInFavs {
                        let vm = ChatViewModel(chatId: targetChatId)
                        await vm.send(text: deepLink(for: sp))
                        shareSpotInFavs = nil
                    }
                }
            }
        }
    }

    // MARK: - Lista
    @ViewBuilder
    private var listView: some View {
        List {
            ForEach(listItems, id: \.id) { (spot: Spot) in
                SpotRow(
                    spot: spot,
                    userCoordinate: userCoordinate,
                    onOpenDirections: { openDirections(for: spot) },
                    onShare: {
                        shareSpotInFavs = spot
                        showShareMenuFromFavs = true
                    },
                    onViewOnMap: {
                        lastOpenedSpot = spot
                        onClose(spot)   // ⇒ pide al mapa centrar en este spot
                        dismiss()       // ⇒ cierra Favoritos
                    }
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    lastOpenedSpot = spot
                    selectedForDetail = spot
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Filtrado y orden
    private var filteredFavorites: [Spot] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return spotsVM.spots.filter { s in
            // Solo favoritos
            guard favoritesVM.favoriteIds.contains(s.id) else { return false }

            if let cat = selectedCategory, s.category != cat { return false }
            guard !text.isEmpty else { return true }
            return s.name.lowercased().contains(text)
                || s.description.lowercased().contains(text)
                || s.category.rawValue.lowercased().contains(text)
                || (s.locality?.lowercased().contains(text) ?? false)
        }
    }

    private var sortedFilteredFavorites: [Spot] {
        guard let userCoordinate else { return filteredFavorites }
        let user = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        return filteredFavorites.sorted { a, b in
            let da = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: user)
            let db = CLLocation(latitude: b.latitude, longitude: b.longitude).distance(from: user)
            return da < db
        }
    }

    // MARK: - Rutas
    private func openDirections(for spot: Spot) {
        let destination = "\(spot.latitude),\(spot.longitude)"
        if let g = URL(string: "comgooglemaps://?daddr=\(destination)&directionsmode=driving") {
            openURL(g) { accepted in
                if !accepted, let a = URL(string: "maps://?daddr=\(destination)&dirflg=d") {
                    openURL(a)
                }
            }
        }
    }
}
