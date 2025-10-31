//
//  SpotsListView.swift
//  Spots
//

import SwiftUI
import CoreLocation
import UIKit

struct SpotsListView: View {
    @EnvironmentObject var spotsVM: SpotsViewModel
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var favoritesVM: FavoritesViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var userCoordinate: CLLocationCoordinate2D?
    @State private var selectedForDetail: Spot?

    @State private var searchText: String = ""
    @State private var selectedCategory: SpotCategory? = nil

    @State private var showingForm = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastIcon: String? = nil
    
    // 🔗 compartir
    @State private var shareSpotInList: Spot? = nil
    @State private var showShareMenuFromList = false
    @State private var showChatPickerFromList = false

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


    // ✅ callback que recibe el último Spot (o nil) al cerrar la lista
    let onClose: (Spot?) -> Void

    // ✅ memoria local del último spot cuyo detalle se abrió
    @State private var lastOpenedSpot: Spot? = nil
    
    init(onClose: @escaping (Spot?) -> Void = { _ in }) {
        self.onClose = onClose
    }

    private var listItems: [Spot] { sortedFilteredSpots }

    var body: some View {
        content
    }

    // MARK: - Partes separadas
    @ViewBuilder
    private var content: some View {
        listView
            .navigationTitle("Spots cercanos")
            .navigationBarTitleDisplayMode(.large)
            .navigationBarBackButtonHidden(true)
            .toolbar {
                leadingToolbar
                trailingToolbar
            }
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Buscar por nombre, categoría o localidad"
            )
            .refreshable {
                await spotsVM.fetchSpotsAsync(force: true)
                resyncFavorites()
            }
            .onAppear {
                userCoordinate = locationManager.location?.coordinate
                if !spotsVM.hasLoaded { spotsVM.fetchSpots() }
                resyncFavorites()
            }
            .onChange(of: favoritesVM.favoriteIds) { _ in
                resyncFavorites()
            }
            .sheet(item: $selectedForDetail) { (spot: Spot) in
                SpotDetailView(spot: spot)
                    .presentationDetents([.large])
                    .environmentObject(spotsVM)
                    .environmentObject(favoritesVM)
            }
            .onReceive(NotificationCenter.default.publisher(for: .init("SpotDetail.OpenInMap"))) { notif in
                guard let s = notif.object as? Spot else { return }
                // Asegura que el sheet de detalle quede cerrado
                selectedForDetail = nil
                // Pequeño delay para evitar que el "tail" del tap reabra el detalle
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    onClose(s)   // ⇒ pedir al mapa que centre en el spot
                    dismiss()    // ⇒ cerrar esta lista
                }
            }

            .sheet(isPresented: $showingForm) {
                SpotFormView { _ in
                    toastMessage = "Spot creado"
                    toastIcon = "checkmark.circle.fill"
                    withAnimation { showToast = true }
                }
                .environmentObject(locationManager)
                .environmentObject(spotsVM)
            }
            // 🔗 Selector de compartir
            .confirmationDialog("Compartir spot",
                                isPresented: $showShareMenuFromList,
                                titleVisibility: .visible) {
                Button("Compartir en chat…") { showChatPickerFromList = true }
                Button("Copiar enlace") {
                    if let sp = shareSpotInList {
                        UIPasteboard.general.string = deepLink(for: sp)
                        toastMessage = "Enlace copiado"
                        toastIcon = "link"
                        withAnimation { showToast = true }
                    }
                }
                Button("Cancelar", role: .cancel) {}
            }
            .sheet(isPresented: $showChatPickerFromList) {
                ForwardPickerSheet(currentChatId: "") { targetChatId in
                    Task {
                        if let sp = shareSpotInList {
                            let vm = ChatViewModel(chatId: targetChatId)
                            await vm.send(text: deepLink(for: sp))
                            toastMessage = "Enlace enviado al chat"
                            toastIcon = "paperplane.fill"
                            withAnimation { showToast = true }
                            shareSpotInList = nil
                        }
                    }
                }
            }
            .toast(isPresented: $showToast, message: toastMessage, systemImage: toastIcon, duration: 3.0)
            .keyboardDismissToolbar()
    }

    @ViewBuilder
    private var listView: some View {
        List {
            ForEach(listItems, id: \.id) { (spot: Spot) in
                SpotRow(
                    spot: spot,
                    userCoordinate: userCoordinate,
                    onOpenDirections: { openDirections(for: spot) },
                    onShare: {
                        shareSpotInList = spot
                        showShareMenuFromList = true
                    },
                    onViewOnMap: {
                        onClose(spot)
                        dismiss()
                    }
                )
                
                .contentShape(Rectangle())
                .gesture(
                    TapGesture().onEnded {
                        lastOpenedSpot = spot
                        selectedForDetail = spot
                    }
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    private var leadingToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button {
                onClose(nil)   // ✅ pasas el spot (o nil) al cerrar
                dismiss()
            } label: {
                HStack { Image(systemName: "chevron.backward") }
            }
        }
    }

    private var trailingToolbar: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 16) {
                Button { showingForm = true } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                FilterMenu(selectedCategory: $selectedCategory)
            }
        }
    }

    // MARK: - Filtrado y orden
    private var filteredSpots: [Spot] {
        let text = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return spotsVM.spots.filter { s in
            if let cat = selectedCategory, s.category != cat { return false }
            guard !text.isEmpty else { return true }
            return s.name.lowercased().contains(text)
                || s.description.lowercased().contains(text)
                || s.category.rawValue.lowercased().contains(text)
                || (s.locality?.lowercased().contains(text) ?? false)
        }
    }

    private var sortedFilteredSpots: [Spot] {
        guard let userCoordinate else { return filteredSpots }
        let user = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        return filteredSpots.sorted { a, b in
            let da = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: user)
            let db = CLLocation(latitude: b.latitude, longitude: b.longitude).distance(from: user)
            return da < db
        }
    }

    // MARK: - Rutas
    private func openDirections(for spot: Spot) {
        NavigationHelper.openDirections(to: spot)
    }

    // MARK: - Favoritos → sincroniza estado local con IDs del VM
    private func resyncFavorites() {
        let ids = favoritesVM.favoriteIds
        // Aseguramos que corra en el hilo principal (modifica @Published)
        if Thread.isMainThread {
            spotsVM.syncFavorites(favorites: ids)
        } else {
            DispatchQueue.main.async {
                spotsVM.syncFavorites(favorites: ids)
            }
        }
    }
}

// MARK: - Menú filtro
struct FilterMenu: View {
    @Binding var selectedCategory: SpotCategory?

    var body: some View {
        Menu {
            Button { selectedCategory = nil } label: {
                HStack {
                    if selectedCategory == nil { Image(systemName: "checkmark") }
                    Text("Todos")
                }
            }
            Divider()
            ForEach(SpotCategory.allCases, id: \.self) { cat in
                Button { selectedCategory = cat } label: {
                    HStack {
                        if selectedCategory == cat { Image(systemName: "checkmark") }
                        Text(cat.rawValue)
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }
}
