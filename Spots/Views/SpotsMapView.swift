//
//  SpotsMapView.swift
//  Spots
//

import SwiftUI
import MapKit
import CoreLocation
import FirebaseFirestore   // 👈 necesario para el listener del badge

// Selección propia del estilo para no comparar MapStyle directamente
private enum MapKind: String, CaseIterable {
    case standard
    case imagery   // (satélite)
    case hybrid
}

struct SpotsMapView: View {
    @StateObject private var spotVM = SpotsViewModel()
    @EnvironmentObject var spotsVM: SpotsViewModel
    @StateObject private var locationManager = LocationManager()
    @StateObject private var notificationsVM = NotificationsViewModel()
    @State private var forceReloadTick: Int = 0
    
    @AppStorage("didShowPermissionsExplainer") private var didShowPermissionsExplainer = false
    @State private var showPermsExplainer = false
    
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var userSession: UserSession
    @EnvironmentObject var favoritesVM: FavoritesViewModel   // 🆕
    
    
    @AppStorage("mapKind") private var mapKindRaw: String = MapKind.standard.rawValue
    private var mapKind: MapKind {
        get { MapKind(rawValue: mapKindRaw) ?? .standard }
        set { mapKindRaw = newValue.rawValue }
    }
    
    @State private var centerOnUserTick = 0
    // Objetivo explícito para centrado de resultados
    @State private var centerTarget: CLLocationCoordinate2D? = nil
    
    @State private var showAdminImport = false
    
    // 🔹 Binding para usar en la vista
    private var mapKindBinding: Binding<MapKind> {
        Binding(
            get: { mapKind },
            set: { newValue in
                mapKindRaw = newValue.rawValue   // ✅ escribimos en el backing storage
            }
        )
    }
    
    @State private var showingForm = false
    @State private var selectedSpot: Spot? = nil
    
    // Acciones rápidas & sheet de contexto
    @State private var showQuickActions = false
    @State private var showPointContext = false
    
    // BEGIN INSERT — toggle rápido overlays
    @State private var overlaysQuickEnabled: Bool = true
    // END INSERT
    
    
    
    // 🔎 Búsqueda con debounce
    @State private var searchText: String = ""
    @State private var debouncedQuery: String = ""
    @FocusState private var searchFocused: Bool
    
    @State private var debounceWorkItem: DispatchWorkItem?
    // Debug: sheet para probar relleno con MKPolygonRenderer
    @State private var showFilledDebug = false
    
    // 🆕 Debounce para cargas de overlays
    @State private var overlaysDebounceTask: Task<Void, Never>? = nil
    @State private var lastTileKey: String? = nil  // tile guard para evitar cargas repetidas por micro-movimientos
    
    // 🟩 GATE de arranque
    @State private var mapFullyRendered = false
    @State private var regionStable = false
    @State private var gateFirstLoadDone = false
    @State private var regionStableTask: Task<Void, Never>? = nil
    @State private var accuracyTimeoutReached = false
    
    @StateObject private var overlayStore = AirspaceOverlayStore()
    
    @AppStorage("overlay_airspace_on") private var overlayAirspaceOn: Bool = true
    
    private var topSafeArea: CGFloat {
        (UIApplication.shared.connectedScenes.first as? UIWindowScene)?
            .windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top ?? 0
    }
    
    // MARK: - Overlays (configuración y helpers)
    @AppStorage("overlay_restricciones_enabled") private var overlayRestriccionesEnabled = true
    @AppStorage("overlay_urbano_enabled") private var overlayUrbanoEnabled = false
    @AppStorage("overlay_infra_enabled") private var overlayInfraEnabled = true
    @AppStorage("overlay_medio_enabled") private var overlayMedioEnabled = true
    
    // Qué capas están activas según los toggles
    private var visibleSources: Set<AirspaceSource> {
        var s = Set<AirspaceSource>()
        if overlayRestriccionesEnabled { s.insert(.restricciones) }
        if overlayUrbanoEnabled        { s.insert(.urbano) }
        if overlayMedioEnabled         { s.insert(.medioambiente) }
        if overlayInfraEnabled         { s.insert(.infraestructura) }
        return s
    }
    
    /// ⚠️ DEBUG: muéstralo siempre para comprobar. Luego vuelve a:
    ///   locationManager.region.span.latitudeDelta < 0.25
    private var shouldShowOverlays: Bool {
        // Muestra a nivel “ciudad”: cuanto menor delta, más zoom.
        locationManager.region.span.latitudeDelta < 0.35
    }
    
    /// Polígono de prueba sobre Madrid
    private var madridSquare: [CLLocationCoordinate2D] {
        let a = CLLocationCoordinate2D(latitude: 40.500, longitude: -3.900)
        let b = CLLocationCoordinate2D(latitude: 40.500, longitude: -3.400)
        let c = CLLocationCoordinate2D(latitude: 40.950, longitude: -3.400)
        let d = CLLocationCoordinate2D(latitude: 40.950, longitude: -3.900)
        return [a, b, c, d, a]
    }
    
    private var trimmedQuery: String { debouncedQuery.trimmingCharacters(in: .whitespacesAndNewlines) }
    
    // Sheets / toasts
    @State private var showNotificationsSheet = false
    @State private var showFavoritesSheet = false
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastIcon: String? = nil
    
    // 🔔💬 Badge de CHATS (solo estado local + listener)
    @State private var chatBadgeCount: Int = 0
    @State private var chatSupportBadgeCount: Int = 0
    private let SUPPORT_BOT_ID = "26CSxWS7R7eZlrvXUV1qJFyL7Oc2"
    @State private var chatsListener: ListenerRegistration?
    private let db = Firestore.firestore()
    
    // 🔄 Estados de carga secuencial
    @State private var userReady = false
    @State private var notificationsReady = false
    
    // 🌍 Resultados geocoder (localidades)
    @State private var geoResults: [CLPlacemark] = []
    private let geocoder = CLGeocoder()
    
    // Resultados de MKLocalSearch
    @State private var placeResults: [SearchPlaceItem] = []
    
    // 🔴 Banner ubicación
    @State private var hideLocBanner = false
    
    // 📍 Spots cercanos
    @State private var showNearbySheet = false
    @State private var nearbyRadiusMeters: Double = 5_000 // 5 km
    
    // 🔁 Cámara (builder API)
    @State private var cameraPosition: MapCameraPosition = .automatic
    
    var body: some View {
        NavigationView {
            ZStack {
                // MAPA (solo cuando todo está listo)
                if userReady && notificationsReady {
                    AirspaceMapUIKitView(
                        region: $locationManager.region,
                        mapType: mapKind.mkMapType,
                        features: overlayStore.features,
                        visibleSources: visibleSources,
                        overlaysEnabled: (overlayAirspaceOn && overlaysQuickEnabled),
                        spots: mapSpotsForUIKit,
                        onSelectSpot: { spotId in
                            if let sp = spotVM.spots.first(where: { $0.id == spotId }) {
                                centerOn(sp)
                                selectedSpot = sp
                            }
                        },
                        
                        onRegionDidChange: { reg in
                            ASDBG.log("MAP", "onRegionDidChange -> \(reg.shortDesc)")

                            #if DEBUG
                            if FeatureFlags.oracleEnabled {
                                let tag = "map#regionDidChange#\(Int(Date().timeIntervalSince1970))"
                                AirspaceOracle.shared.regionChanged(tag: tag, region: reg)
                            }
                            #endif

                            // 1) Evitar recargas si el mapa sigue en “mundo” (arranque inicial de MKMapView)
                            let isWorld = reg.span.latitudeDelta > 10 || reg.span.longitudeDelta > 10
                            if isWorld {
                                ASDBG.log("MAP", "skip reload (world region)")
                                return
                            }

                            // 2) Evitar recargas si los overlays están apagados (brocha off o toggle rápido off)
                            let overlaysEnabledNow = (overlayAirspaceOn && overlaysQuickEnabled)
                            guard overlaysEnabledNow else {
                                ASDBG.log("MAP", "skip reload (overlays off)")
                                return
                            }

                            // 3) Respeta tu flag general de visibilidad
                            guard shouldShowOverlays else {
                                ASDBG.log("MAP", "skip reload (shouldShowOverlays = false)")
                                return
                            }

                            // 4) Gate de primera carga + debounce más corto (350 ms en vez de 700 ms)
                            if gateFirstLoadDone {
                                scheduleOverlayReload(region: reg, reason: "regionDidChange")
                            } else {
                                regionStable = false
                                regionStableTask?.cancel()
                                regionStableTask = Task { @MainActor in
                                    try? await Task.sleep(nanoseconds: 350_000_000)
                                    regionStable = true
                                    maybeTriggerFirstLoad(using: reg)
                                }
                            }
                        },
                        onMapFullyRendered: {                      // ⬅️ nuevo callback
                            mapFullyRendered = true
                            maybeTriggerFirstLoad(using: locationManager.region)
                        },
                        centerOnUserTick: centerOnUserTick,
                        fallbackUser: locationManager.location?.coordinate,
                        centerTarget: centerTarget,
                        forceFullReloadTick: forceReloadTick
                    )
                    
                    /*.onLongPressGesture(minimumDuration: 0.45) {
                     Haptics.selection()
                     withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                     showQuickActions = true
                     }
                     }*/
                    .ignoresSafeArea()
                    .safeAreaInset(edge: .top, spacing: 0) {
                        VStack(spacing: 8) {
                            topBar
                                .padding(.leading, 2)
                                .padding(.trailing, 9)
                                .padding(.vertical, 6)
                                .background(Color.white)
                                .cornerRadius(16)
                                .shadow(radius: 4)
                            
                            searchBar
                                .overlay(
                                    HStack {
                                        MapStyleMenu(selected: mapKindBinding)
                                            .offset(y: 60)
                                            .padding(.leading, 0)
                                        Spacer()
                                        NavigationLink {
                                            FavoritesListView(onClose: { returnedSpot in
                                                guard let s = returnedSpot else { return }  // si no abriste detalle, no tocar el mapa
                                                centerOn(s)                                  // reutiliza tu helper que ya recentra y hace refresh
                                            })
                                            .environmentObject(spotVM)
                                            .environmentObject(locationManager)
                                            .environmentObject(favoritesVM)
                                        } label: {
                                            Image(systemName: "heart.fill")
                                                .font(.system(size: 22, weight: .bold))
                                                .foregroundColor(.red)
                                                .padding()
                                                .background(Color.white)
                                                .clipShape(Circle())
                                                .shadow(radius: 4)
                                        }
                                        .simultaneousGesture(TapGesture().onEnded {
                                            // Asegura dismissal si venías escribiendo
                                            searchFocused = false
                                            UIApplication.shared.endEditing(true)
                                        })
                                        .offset(y: 60)
                                        Spacer()
                                        NavigationLink {
                                            SpotsListView(onClose: { returnedSpot in
                                                guard let s = returnedSpot else { return }   // si no se abrió ningún detalle, no tocar el mapa
                                                centerOn(s)                                   // reusa tu helper existente
                                            })
                                            .environmentObject(spotVM)
                                            .environmentObject(locationManager)
                                        } label: {
                                            Image(systemName: "list.and.film")
                                                .font(.system(size: 22, weight: .bold))
                                                .foregroundColor(.blue)
                                                .padding()
                                                .background(Color.white)
                                                .clipShape(Circle())
                                                .shadow(radius: 4)
                                        }
                                        .simultaneousGesture(TapGesture().onEnded {
                                            // Asegura dismissal si venías escribiendo
                                            searchFocused = false
                                            UIApplication.shared.endEditing(true)
                                        })
                                        .offset(y: 60)
                                        .padding(.trailing, 0)
                                    }
                                )
                            
                            if !trimmedQuery.isEmpty {
                                resultsPanel
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 2)
                        .background(.clear)
                    }
                }
                
                // CRUZ DEL CENTRO
                Image(systemName: "plus")
                    .font(.system(size: 32))
                    .foregroundColor(.red.opacity(0.5))
                    .offset(y: -16)
                    .scaleEffect(showQuickActions ? 1.05 : 1.0)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: showQuickActions)
                    .allowsHitTesting(false)
                //.zIndex(-1) // ⬅️ baja la cruz por detrás visualmente
                
                // FAB INFERIORES
                bottomFabs
                    .frame(maxHeight: .infinity, alignment: .bottom)
                
                // Marca de la app
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Image("Texto")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 85)
                            .padding(.bottom, -9)
                        Spacer()
                    }
                }
                .ignoresSafeArea()
                
                // Área pequeña de long-press
                // Área pequeña de long-press (desactivada: el gesto vive en AirspaceMapUIKitView)
                Circle()
                    .fill(Color.clear)
                    .frame(width: 56, height: 56)
                    .contentShape(Circle())
                    .allowsHitTesting(false) // ⬅️ no intercepta toques
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .offset(y: -16)
                    .zIndex(-2) // ⬅️ la mandamos al fondo por si acaso
#if DEBUG
                /*if FeatureFlags.oracleEnabled {
                 AirspaceOracleHUD()
                 .padding(.top, 10)
                 .padding(.leading, 12)
                 .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                 }*/
#endif
                
            }
            
            .task {
                // 1️⃣ Username
                if let local = userSession.username, !local.isEmpty {
                    await MainActor.run { userReady = true }
                    if let uid = userSession.uid {
                        Task.detached {
                            if let remote = await UserService.shared.getUsername(for: uid), remote != local {
                                await MainActor.run { userSession.username = remote }
                            }
                        }
                    }
                } else if let uid = userSession.uid {
                    let name = await UserService.shared.getUsername(for: uid)
                    await MainActor.run { userSession.username = name }
                    await MainActor.run { userReady = true }
                } else {
                    await MainActor.run { userReady = true }
                }
                
                // 2️⃣ Notificaciones y chats
                if let uid = userSession.uid {
                    notificationsVM.startListening(userId: uid, spotsVM: spotVM)
                    startChatsBadgeListener(for: uid)
                }
                await MainActor.run { notificationsReady = true }
                
                // 3️⃣ Spots
                spotVM.fetchSpots()
                
                // ⬇️ Centrado inicial si ya tenemos localización
                // ⬇️ Centrado y carga inicial de overlays (con o sin localización) — SIEMPRE 2000 m
                let targetCenter = locationManager.location?.coordinate
                ?? CLLocationCoordinate2D(latitude: 40.4168, longitude: -3.7038) // Madrid (fallback)
                
                let reg = MKCoordinateRegion(
                    center: targetCenter,
                    latitudinalMeters: 2000,
                    longitudinalMeters: 2000
                )
                
                locationManager.region = reg
                cameraPosition = .region(reg)
                print("🚀 Arranque -> setRegion center=(\(reg.center.latitude), \(reg.center.longitude)) span=(\(reg.span.latitudeDelta), \(reg.span.longitudeDelta))")
                
                
                
                // ⏳ Pequeño colchón para que el mapa termine de asentarse
                do {
                    try await Task.sleep(nanoseconds: 200_000_000)
                } catch {
                    // ignoramos la cancelación del sleep
                }
                
                // 👉 Arranque preciso: espera hasta 4 s a una ubicación buena; si no llega, usa fallback
                regionStable = false
                accuracyTimeoutReached = false
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 s
                    if !gateFirstLoadDone {
                        accuracyTimeoutReached = true
                        maybeTriggerFirstLoad(using: reg)
                    }
                }
                
                
                
            }
            
            .onChange(of: userSession.profileImageUrl) { _ in
                userSession.avatarBustToken = UUID().uuidString
            }
            .onChange(of: searchText) { newValue in
                // Cancela cualquier trabajo previo
                debounceWorkItem?.cancel()
                
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                
                // Limpia si vacío
                guard !trimmed.isEmpty else {
                    self.debouncedQuery = ""
                    self.placeResults = []
                    return
                }
                
                // Si son coordenadas → NO lanzar búsqueda de texto (mostramos solo "Ir a coordenadas")
                if let _ = parseCoordinates(trimmed) {
                    self.debouncedQuery = trimmed
                    self.placeResults = []
                    return
                }
                
                // 🔎 Búsqueda por texto con fallbacks de región (todo en SearchPlaceItem)
                let task = DispatchWorkItem {
                    self.debouncedQuery = trimmed
                    
                    Task {
                        let here = locationManager.region
                        
                        // 1) Región actual (~2 km)
                        var items = await SearchService.searchPlaces(
                            query: trimmed,
                            region: here,
                            limit: 20
                        )
                        
                        // 2) Si pocos, ampliar a ciudad (~20 km)
                        if items.count < 6 {
                            let city = regionAround(here.center, km: 20)
                            let more = await SearchService.searchPlaces(
                                query: trimmed,
                                region: city,
                                limit: 20
                            )
                            items = Array(Set(items + more)) // dedup por Hashable
                        }
                        
                        // 3) Si aún pocos, ampliar más (~200 km)
                        if items.count < 6 {
                            let metro = regionAround(here.center, km: 200)
                            let more2 = await SearchService.searchPlaces(
                                query: trimmed,
                                region: metro,
                                limit: 20
                            )
                            items = Array(Set(items + more2))
                        }
                        
                        await MainActor.run {
                            self.placeResults = Array(items.prefix(20))
                        }
                    }
                }
                
                debounceWorkItem = task
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
            }
            
            
            
            
            .onAppear {
                print("👀 SpotsMapView.onAppear")
                ASDBG.log("MAP", "forceFullReloadTick = \(forceReloadTick)")
                if !didShowPermissionsExplainer {
                    showPermsExplainer = true
                }
                // ✅ sincroniza favoritos al entrar (cubre arranque en frío)
                spotVM.syncFavorites(favorites: favoritesVM.favoriteIds)   // ← AÑADE ESTA LÍNEA
                // Inicializar cámara con la región actual (si no hay loc aún, el onChange de autorización la fijará)
                cameraPosition = .region(locationManager.region)
                
                // 👉 Si venimos de un link desde Chat y el mapa reaparece, centra y pinta overlays (sin abrir detalle)
                
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                if locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted {
                    hideLocBanner = false
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openSpotsDeepLink)) { note in
                print("🔗 DeepLink IN (onReceive)")
                
                guard let userInfo = note.userInfo as? [String: Any] else { return }
                
                // ⛔️ Si la señal viene del chat, NO recentramos el mapa
                if let source = userInfo["source"] as? String, source == "chat" {
                    // Si quieres, registra algo para debug:
                    print("🟡 openSpotsDeepLink ignorado (origen chat)")
                    return
                }
                
                // ✅ comportamiento normal (mapa se centra) para el resto de orígenes
                if let urlString = userInfo["url"] as? String {
                    handleDeepLinkString(urlString)
                }
            }
            
            /*.onReceive(
             NotificationCenter.default
             .publisher(for: Notification.Name("ShowToast"))
             .receive(on: RunLoop.main) // asegura main thread
             ) { note in
             guard let msg = note.userInfo?["message"] as? String else { return }
             let icon = note.userInfo?["systemImage"] as? String
             print("📬 ShowToast recibido → \(msg)")
             toastMessage = msg
             toastIcon = icon
             withAnimation { showToast = true }
             }*/
            .onDisappear {
                print("👋 SpotsMapView.onDisappear")
                
                stopChatsBadgeListener()
            }
            
            // 🔴 Banner de ubicación denegada/restringida
            .overlay(alignment: .top) {
                let denied = (locationManager.authorizationStatus == .denied ||
                              locationManager.authorizationStatus == .restricted)
                
                if denied && !hideLocBanner {
                    HStack(spacing: 10) {
                        Image(systemName: "location.slash")
                            .foregroundColor(.white)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Activa la ubicación para ver spots cercanos")
                                .font(.footnote.bold())
                                .foregroundColor(.white)
                            Text("Ajustes > Privacidad > Localización")
                                .font(.caption2)
                                .foregroundColor(.white.opacity(0.95))
                        }
                        
                        Spacer(minLength: 8)
                        
                        Button("Ajustes") { openAppSettings() }
                            .font(.caption.bold())
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.white)
                            .foregroundColor(.red)
                            .cornerRadius(8)
                        
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) { hideLocBanner = true }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.bold())
                                .foregroundColor(.white.opacity(0.9))
                                .padding(6)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        Capsule().fill(Color.red.opacity(0.96))
                    )
                    .padding(.top, 10)
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(999)
                }
            }
            
            // Re-centrar cuando se concede autorización y ya hay ubicación
            .onChange(of: locationManager.authorizationStatus) { status in
                guard status == .authorizedWhenInUse || status == .authorizedAlways,
                      let loc = locationManager.location else { return }
                let reg = MKCoordinateRegion(
                    center: loc.coordinate,
                    latitudinalMeters: 2000,
                    longitudinalMeters: 2000
                )
                locationManager.region = reg
                cameraPosition = .region(reg)
            }
            
            // Sheets
            .sheet(isPresented: $showingForm) {
                SpotFormView { newSpot in
                    withAnimation {
                        let reg = MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: newSpot.latitude, longitude: newSpot.longitude),
                            latitudinalMeters: 1000,
                            longitudinalMeters: 1000
                        )
                        locationManager.region = reg
                        cameraPosition = .region(reg)
                    }
                }
                .environmentObject(locationManager)
                .environmentObject(spotVM)
            }
            .sheet(isPresented: $showAdminImport) {
                AdminImportGMapsView()
                    .environmentObject(spotsVM)
                // (Opcional) controles de presentación:
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .sheet(item: $selectedSpot) { spot in
                SpotDetailView(spot: spot)
                    .presentationDetents([.large])
                    .environmentObject(spotVM)
                    .environment(\.fromChat, true)   // 👈 activa el “parche visual” del corazón también desde el mapa
            }
            .sheet(isPresented: $showPointContext) {
                PointContextSheet(center: locationManager.region.center)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showNotificationsSheet) {
                NotificationsSheetView()
                    .environmentObject(notificationsVM)
                    .environmentObject(spotVM)
                    .environmentObject(locationManager)
            }
            .sheet(isPresented: $showFavoritesSheet) {
                FavoritesListView()
                    .environmentObject(spotVM)
                    .environmentObject(locationManager)
                    .environmentObject(favoritesVM)
            }
            .fullScreenCover(isPresented: $showPermsExplainer, onDismiss: {
                didShowPermissionsExplainer = true
            }) {
                PermissionsExplainerView()
                    .ignoresSafeArea()      // que sea full-bleed
            }
            .sheet(isPresented: $showNearbySheet) {
                if let base = locationManager.location {
                    NearbySpotsSheet(
                        spots: nearbySpots,
                        base: base,
                        selectedSpot: $selectedSpot
                    )
                    .presentationDetents([.medium, .large])
                } else {
                    NearbySpotsSheet(
                        spots: nearbySpots,
                        base: CLLocation(latitude: locationManager.region.center.latitude,
                                         longitude: locationManager.region.center.longitude),
                        selectedSpot: $selectedSpot
                    )
                    .presentationDetents([.medium, .large])
                }
            }
            // Debug: vista de relleno con MKPolygonRenderer
            .sheet(isPresented: $showFilledDebug) {
                AirspaceFilledDebugView(
                    region: locationManager.region,
                    features: overlayStore.features,
                    visibleSources: visibleSources,
                    enabled: overlayAirspaceOn,
                    spots: spotVM.spots.map {
                        SpotPin(
                            title: $0.name,
                            coordinate: CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                        )
                    }
                )
            }
            
        }
        .navigationViewStyle(StackNavigationViewStyle())   // 👈 FIX iPad
        .toolbar(.hidden, for: .navigationBar)              // 👉 oculta la nav bar (pantalla completa)
        .toolbarBackground(.hidden, for: .navigationBar)
        .keyboardDismissToolbar()
        .toast(isPresented: $showToast, message: toastMessage, systemImage: toastIcon, duration: 2.0)
    }
    
    // MARK: - Top bar
    private var topBar: some View {
        HStack(spacing: 8) {
            NavigationLink {
                UserProfileView()
            } label: {
                ZStack {
                    Circle()
                        .stroke(
                            AngularGradient(
                                gradient: Gradient(colors: [
                                    Color(red: 0.0, green: 0.85, blue: 0.9),
                                    Color(red: 0.2, green: 0.5, blue: 1.0)
                                ]),
                                center: .center
                            ),
                            lineWidth: 7
                        )
                        .frame(width: 48, height: 48)
                    
                    Circle()
                        .fill(Color.white)
                        .frame(width: 52, height: 52)
                    
                    if let local = userSession.localAvatar {
                        Image(uiImage: local)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                    } else if let url = bustedURL(userSession.profileImageUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable()
                                    .scaledToFill()
                                    .frame(width: 48, height: 48)
                                    .clipShape(Circle())
                            default:
                                placeholderCircle
                            }
                        }
                        .id(userSession.avatarBustToken)
                    } else {
                        placeholderCircle
                    }
                }.navigationBarTitleDisplayMode(.inline)
                    .navigationBarHidden(true)
            }
            .simultaneousGesture(TapGesture().onEnded {
                // Asegura dismissal si venías escribiendo
                searchFocused = false
                UIApplication.shared.endEditing(true)
            })
            .padding(.leading, 6)
            
            Spacer()
            
            if let username = userSession.username {
                NavigationLink {
                    UserProfileView()
                } label: {
                    Text(username)
                        .font(.headline).bold()
                        .foregroundColor(.black)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                }
                .simultaneousGesture(TapGesture().onEnded {
                    // Asegura dismissal si venías escribiendo
                    searchFocused = false
                    UIApplication.shared.endEditing(true)
                })
            }
            
            Spacer()
            
            HStack(spacing: 6) {
                Button {
                    Haptics.selection()
                    if notificationsVM.badgeCount > 0 {
                        showNotificationsSheet = true
                    } else {
                        toastMessage = "No hay comentarios nuevos en tus spots"
                        toastIcon = "text.bubble"
                        withAnimation { showToast = true }
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bubble.left")
                            .font(.title2)
                            .padding(3)
                        if notificationsVM.badgeCount > 0 {
                            Text("\(notificationsVM.badgeCount)")
                                .font(.caption2).bold()
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.red)
                                .clipShape(Circle())
                                .offset(x: 8, y: -8)
                        }
                    }
                }
                
                NavigationLink {
                    ChatsHomeView()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.title2)
                            .padding(3)
                        
                        if chatBadgeCount > 0 {
                            Text("\(chatBadgeCount)")
                                .font(.caption2).bold()
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.red)
                                .clipShape(Circle())
                                .offset(x: 8, y: -8)
                        }
                        
                        if chatSupportBadgeCount > 0 {
                            Text("\(chatSupportBadgeCount)")
                                .font(.caption2).bold()
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.blue)
                                .clipShape(Circle())
                                .offset(x: 8, y: 10)
                        }
                    }
                }
                .simultaneousGesture(TapGesture().onEnded {
                    // Asegura dismissal si venías escribiendo
                    searchFocused = false
                    UIApplication.shared.endEditing(true)
                })
                .accessibilityIdentifier("openChatsButton")
            }
        }
    }
    
    // MARK: - Utils avatar
    private func bustedURL(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        let sep = raw.contains("?") ? "&" : "?"
        return URL(string: "\(raw)\(sep)b=\(userSession.avatarBustToken)")
    }
    
    private var placeholderCircle: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 36, height: 36)
            .overlay(
                Text(String((userSession.username ?? "U").prefix(2)).uppercased())
                    .font(.subheadline.bold())
                    .foregroundColor(.blue)
            )
    }
    
    // MARK: - SearchBar
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField(
                "",
                text: $searchText,
                prompt: Text("Buscar spots, categorías, descripción o localidad")
                    .foregroundColor(.gray)
            )
            .foregroundColor(.black)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .submitLabel(.search)
            .focused($searchFocused)
            
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 2)
        .textSelection(.enabled)
        .contextMenu { EmptyView() }
    }
    
    // MARK: - Resultados búsqueda
    private var resultsPanel: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Spots
                    ForEach(searchResults, id: \.id) { spot in
                        Button {
                            Haptics.selection()
                            centerOn(spot)
                            searchText = ""
                            UIApplication.shared.endEditing(true)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15))
                                    if let s = spot.imageUrl, !s.isEmpty, let url = URL(string: s) {
                                        AsyncImage(url: url) { phase in
                                            switch phase {
                                            case .success(let img): img.resizable().scaledToFill()
                                            default:
                                                Image("dronePlaceholder")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .padding(6)
                                                    .opacity(0.8)
                                            }
                                        }
                                    } else {
                                        Image("dronePlaceholder")
                                            .resizable()
                                            .scaledToFit()
                                            .padding(6)
                                            .opacity(0.8)
                                    }
                                }
                                .frame(width: 48, height: 48)
                                .clipped()
                                .cornerRadius(8)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(spot.name)
                                        .font(.subheadline).bold()
                                        .foregroundColor(.black)
                                        .lineLimit(1)
                                    
                                    Text(spot.category.rawValue)
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                        .lineLimit(1)
                                    
                                    if let loc = spot.locality {
                                        Text(loc)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                            .lineLimit(1)
                                    }
                                }
                                
                                Spacer()
                                
                                Text(distanceText(to: spot))
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.12))
                                    .cornerRadius(8)
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                        }
                        
                        
                        
                        Divider().padding(.leading, 68)
                    }
                    
                    // Lugares (MKLocalSearch)
                    if !placeResults.isEmpty {
                        Divider().padding(.leading, 68)
                        
                        ForEach(placeResults) { item in
                            Button {
                                Haptics.selection()
                                centerOnCoordinate(item.coordinate)
                                searchText = ""
                                UIApplication.shared.endEditing(true)
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundColor(.red)
                                        .frame(width: 48, height: 48)
                                        .background(Color.gray.opacity(0.15))
                                        .cornerRadius(8)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.name)
                                            .font(.subheadline).bold()
                                            .foregroundColor(.black)
                                            .lineLimit(1)
                                        if let sub = item.subtitle, !sub.isEmpty {
                                            Text(sub)
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                                .lineLimit(1)
                                        }
                                    }
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.12))
                                .cornerRadius(8)
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 10)
                            
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                
                // Botón "Ir a coordenadas" directo
                if let coord = parseCoordinates(trimmedQuery) {
                    Button {
                        Haptics.selection()
                        centerOnCoordinate(coord)   // ⇦ dispara centerTarget + centerOnUserTick
                        searchText = ""
                        UIApplication.shared.endEditing(true)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "location.north.line.fill")
                                .foregroundColor(.blue)
                                .frame(width: 48, height: 48)
                                .background(Color.gray.opacity(0.15))
                                .cornerRadius(8)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Ir a coordenadas")
                                    .font(.subheadline).bold()
                                    .foregroundColor(.black)
                                
                                Text("\(coord.latitude), \(coord.longitude)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                    }
                    Divider().padding(.leading, 68)
                }
            }
            .frame(maxHeight: 240)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 2)
    }
    
    private var searchResults: [Spot] {
        let q = trimmedQuery.lowercased()
        guard !q.isEmpty else { return [] }
        
        let filtered = spotVM.spots.filter { s in
            s.name.lowercased().contains(q) ||
            s.description.lowercased().contains(q) ||
            s.category.rawValue.lowercased().contains(q) ||
            (s.locality?.lowercased().contains(q) ?? false)
        }
        
        let center = CLLocation(latitude: locationManager.region.center.latitude,
                                longitude: locationManager.region.center.longitude)
        return filtered.sorted {
            let d0 = CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: center)
            let d1 = CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: center)
            return d0 < d1
        }
    }
    
    // Coordenadas desde query "lat,lon"
    private var coordinateFromQuery: CLLocationCoordinate2D? {
        let q = trimmedQuery.replacingOccurrences(of: " ", with: "")
        let parts = q.split(separator: ",")
        guard parts.count == 2,
              let lat = Double(parts[0]),
              let lon = Double(parts[1]),
              lat >= -90, lat <= 90,
              lon >= -180, lon <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    
    // 📍 Cálculo de spots cercanos al usuario
    private var nearbySpots: [Spot] {
        guard let coord = locationManager.location?.coordinate else { return [] }
        let me = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        
        return spotVM.spots
            .map { spot in
                let d = CLLocation(latitude: spot.latitude, longitude: spot.longitude).distance(from: me)
                return (spot, d)
            }
            .filter { $0.1 <= nearbyRadiusMeters }
            .sorted { $0.1 < $1.1 }
            .map { $0.0 }
    }
    
    // MARK: - FABs
    private var bottomFabs: some View {
        HStack {
            Button {
                Haptics.selection()
                centerTarget = nil              // ⬅️ invalida objetivo de búsqueda previo
                centerOnUserTick += 1
                if let loc = locationManager.location {
                    let reg = MKCoordinateRegion(
                        center: loc.coordinate,
                        latitudinalMeters: 2000,
                        longitudinalMeters: 2000
                    )
                    
                    // 1) sube el tick para forzar reset de overlays en el UIKit map
                    forceReloadTick &+= 1
                    ASDBG.log("MAP", "forceFullReloadTick (user) = \(forceReloadTick)")
                    
                    // 2) mueve la cámara
                    withAnimation {
                        cameraPosition = .region(reg)
                    }
                    
                    // 3) carga con tag correlado (para ver el ciclo IN/OUT → reload)
                    let tag = "map#recenter#user#\(Int(Date().timeIntervalSince1970))"
                    ASDBG.log("MAP", "request load \(tag)")
                    scheduleOverlayReload(region: reg, reason: "recenter#user")
                    
                }else {
                    // 🔁 Sin ubicación aún: refresca con la región actual para pintar ya
                    do {
                        let tag = "map#recenter#user-noLoc#\(Int(Date().timeIntervalSince1970))"
                        ASDBG.log("MAP", "request load \(tag)")
                        scheduleOverlayReload(region: locationManager.region, reason: "recenter#user-noLoc")
                    }
                }
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.green)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            
            .padding()
            
            Spacer()
            
            Button {
                Haptics.selection()
                showPointContext = true
            } label: {
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.purple)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            // Debug: abrir mapa de prueba con relleno real
            Button {
                Haptics.selection()
                showingForm = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color.blue)
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
#if DEBUG
            // Botón circular rojo (tipo Google Maps) que abre el sheet
            Button {
                Haptics.selection()
                showAdminImport = true
            } label: {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding()
                    .background(Color(red: 219/255, green: 68/255, blue: 55/255)) // Rojo Google
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
#endif
            Spacer()
            
            Button {
                Haptics.selection()
                overlaysQuickEnabled.toggle()
                print("🎚️ overlaysQuickEnabled -> \(overlaysQuickEnabled)")
                
                if overlaysQuickEnabled {
                    // Al reactivar: forzamos fetch con la región actual para que pinte YA.
                    let current = locationManager.region
                    print("📦 OverlayStore.load(for:) (toggle ON) -> center=(\(current.center.latitude), \(current.center.longitude)) span=(\(current.span.latitudeDelta), \(current.span.longitudeDelta))")
                    
                    do {
                        let tag = "map#toggleOn#\(Int(Date().timeIntervalSince1970))"
                        ASDBG.log("MAP", "request load \(tag)")
                        scheduleOverlayReload(region: current, reason: "toggleOn")
                    }
                } else {
                    // AirspaceMapUIKitView limpiará los overlays al desactivar
                }
            } label: {
                Image(systemName: overlaysQuickEnabled ? "paintbrush.fill" : "paintbrush")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .padding()
                    .background(overlaysQuickEnabled ? Color.orange : Color.gray.opacity(0.6))
                    .clipShape(Circle())
                    .shadow(radius: 4)
            }
            
            
            
            
            .padding()
        }
    }
    
    // MARK: - Utils
    
    // MARK: - Overlays: debounce + guard anti-mundo
    // MARK: - Overlays: schedule + debounce + filtro por tile
    private func scheduleOverlayReload(region: MKCoordinateRegion, reason: String) {
        // 1) Fast-path: si es un recenter programático, disparamos YA sin debounce
        let isRecenter = reason.hasPrefix("recenter")
        if isRecenter {
            // Guard anti-viewport enorme
            let span = region.span
            if span.latitudeDelta > 30 || span.longitudeDelta > 60 {
                ASDBG.log("MAP", "skip load (viewport too wide) Δ=(\(span.latitudeDelta),\(span.longitudeDelta))")
                return
            }
            // Filtro por tileKey local a la vista
            let key = tileKey(for: region)
            if let last = lastTileKey, last == key {
                ASDBG.log("MAP", "skip reload (same tile) reason=\(reason) tile=\(key)")
                return
            }
            lastTileKey = key
            
            let tag = "map#\(reason)#\(Int(Date().timeIntervalSince1970))"
            ASDBG.log("MAP", "request load \(tag)")
            // ⬇️ clave: no esperamos ni encadenamos la descarga a esta Task
            overlayStore.requestLoad(for: region, tag: tag)
            return
        }
        
        // 2) Caso normal: mantenemos debounce, pero lanzamos requestLoad (no await)
        overlaysDebounceTask?.cancel()
        overlaysDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000) // 250 ms
            
            let span = region.span
            if span.latitudeDelta > 30 || span.longitudeDelta > 60 {
                ASDBG.log("MAP", "skip load (viewport too wide) Δ=(\(span.latitudeDelta),\(span.longitudeDelta))")
                return
            }
            
            let key = tileKey(for: region)
            if let last = lastTileKey, last == key {
                ASDBG.log("MAP", "skip reload (same tile) reason=\(reason) tile=\(key)")
                return
            }
            lastTileKey = key
            
            let tag = "map#\(reason)#\(Int(Date().timeIntervalSince1970))"
            ASDBG.log("MAP", "request load \(tag)")
            overlayStore.requestLoad(for: region, tag: tag) // ⬅️ sin await
        }
    }
    
    
    /// Clave de tile estable (réplica de la del Store para filtrar micro movimientos desde la vista)
    private func tileKey(for region: MKCoordinateRegion) -> String {
        let span = region.span
        let center = region.center
        let latStep = max(0.06, span.latitudeDelta * 0.85)
        let lonStep = max(0.06, span.longitudeDelta * 0.85)
        let lat = (center.latitude / latStep).rounded(.toNearestOrAwayFromZero) * latStep
        let lon = (center.longitude / lonStep).rounded(.toNearestOrAwayFromZero) * lonStep
        return String(format: "%.5f_%.5f_%.5f_%.5f", lat, lon, latStep, lonStep)
    }
    
    
    
    private func centerOn(_ spot: Spot) {
        let target = CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude)
        // Región base a 2000 m (misma escala)
        let baseReg = MKCoordinateRegion(center: target, latitudinalMeters: 2000, longitudinalMeters: 2000)

        // Desplazamos la vista hacia abajo para que el spot quede un poco más alto
        let verticalBias = 0.22  // ajustable 0.18–0.25
        let offsetLat = baseReg.span.latitudeDelta * verticalBias
        let adjustedCenter = CLLocationCoordinate2D(
            latitude: target.latitude + offsetLat,
            longitude: target.longitude
        )

        // MUY IMPORTANTE: el AirspaceMapUIKitView se guía por 'centerTarget'.
        // Si aquí ponemos el target original, a veces nos pisa el bias.
        // Por eso fijamos 'centerTarget' al centro AJUSTADO.
        centerTarget = adjustedCenter
        centerOnUserTick += 1

        withAnimation {
            let reg = MKCoordinateRegion(center: adjustedCenter, span: baseReg.span)
            locationManager.region = reg
            print("📍 Recenter programático (spot biased) -> center=\(reg.center) span=(\(reg.span.latitudeDelta), \(reg.span.longitudeDelta))")
            cameraPosition = .region(reg)
            scheduleOverlayReload(region: reg, reason: "recenter#spot")
        }

    }
    
    
    
    
    private func centerOnCoordinate(_ coord: CLLocationCoordinate2D) {
        centerTarget = coord
        centerOnUserTick += 1
        withAnimation {
            let reg = MKCoordinateRegion(center: coord, latitudinalMeters: 2000, longitudinalMeters: 2000)
            locationManager.region = reg
            print("📍 Recenter programático (coord) -> center=(\(reg.center.latitude), \(reg.center.longitude)) span=(\(reg.span.latitudeDelta), \(reg.span.longitudeDelta))")
            
            //forceReloadTick &+= 1
            //ASDBG.log("MAP", "forceFullReloadTick (coord) = \(forceReloadTick)")
            
            cameraPosition = .region(reg)
            let tag = "map#recenter#coord#\(Int(Date().timeIntervalSince1970))"
            ASDBG.log("MAP", "request load \(tag)")
            scheduleOverlayReload(region: reg, reason: "recenter#coord")
            
            
        }
    }
    
    // MARK: - Manejo de enlaces internos "spots://..."
    private func handleDeepLinkString(_ raw: String) {
        print("🔗 DeepLink URL -> \(raw)")
        
        guard let url = URL(string: raw) else { return }
        handleDeepLinkURL(url)
    }
    
    private func handleDeepLinkURL(_ url: URL) {
        guard url.scheme == "spots" else { return }
        
        switch url.host?.lowercased() {
        case "spot":
            if let id = url.pathComponents.dropFirst().first {
                // 👇 sincroniza antes de leer del VM
                spotVM.syncFavorites(favorites: favoritesVM.favoriteIds)
                if let sp = spotVM.spots.first(where: { $0.id == id }) {
                    centerOn(sp)                  // usa tu zoom actual
                    selectedSpot = sp             // abre el detalle si así lo tienes
                } else {
                    // Fallback con query ?lat=&lon= si viene en el enlace
                    if let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
                       let latStr = comps.queryItems?.first(where: { $0.name == "lat" })?.value,
                       let lonStr = comps.queryItems?.first(where: { $0.name == "lon" })?.value,
                       let lat = Double(latStr), let lon = Double(lonStr) {
                        centerOnCoordinate(CLLocationCoordinate2D(latitude: lat, longitude: lon))
                    }
                }
            }
            
        case "coord":
            // formato: spots://coord/40.123,-3.456
            let tail = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let parts = tail.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
            if parts.count == 2, let lat = parts[0], let lon = parts[1] {
                centerOnCoordinate(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            }
            
        default:
            break
        }
    }
    
    
    private func regionAround(_ center: CLLocationCoordinate2D, km: Double) -> MKCoordinateRegion {
        // 1 grado lat ≈ 111 km
        let latDelta = km / 111.0
        // Ajuste lon por latitud
        let lonDelta = km / (111.0 * max(cos(center.latitude * .pi / 180.0), 0.0001))
        return MKCoordinateRegion(center: center,
                                  span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta))
    }
    
    
    
    
    
    
    private func distanceText(to spot: Spot) -> String {
        let baseCoord = locationManager.location?.coordinate ?? locationManager.region.center
        let base = CLLocation(latitude: baseCoord.latitude, longitude: baseCoord.longitude)
        let target = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        let d = target.distance(from: base)
        if d >= 1000 { return String(format: "%.1f km", d / 1000.0) }
        else { return "\(Int(d)) m" }
    }
    
    private func scaleForZoom(region: MKCoordinateRegion) -> CGFloat {
        let meters = region.span.latitudeDelta * 111_000
        if meters < 500 { return 1.3 }
        else if meters < 2000 { return 1.1 }
        else if meters < 10_000 { return 0.7 }
        else if meters < 50_000 { return 0.5 }
        else { return 0.3 }
    }
    
    private var allAnnotations: [MapAnnotationItem] {
        var annotations: [MapAnnotationItem] = spotVM.spots.map { .spot($0) }
        if let userLoc = locationManager.location {
            annotations.append(.user(userLoc.coordinate))
        }
        return annotations
    }
    private var mapSpotsForUIKit: [AirspaceMapUIKitView.Spot] {
        var arr: [AirspaceMapUIKitView.Spot] = []
        arr.reserveCapacity(spotVM.spots.count)
        for s in spotVM.spots {
            let coord = CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude)
            arr.append(
                AirspaceMapUIKitView.Spot(
                    id: s.id,
                    name: s.name,
                    coordinate: coord,ratingMean: s.ratingMean,
                    ratingCount: s.ratingCount
                    
                )
            )
        }
        return arr
    }
    
    private func isViewportOK(_ region: MKCoordinateRegion) -> Bool {
        let span = region.span
        // Umbral anti-mundo; puedes estrechar si lo deseas
        return !(span.latitudeDelta > 30 || span.longitudeDelta > 60)
    }
    
    private func isAccurateLocation() -> Bool {
        guard let loc = locationManager.location else { return false }
        let recent = Date().timeIntervalSince(loc.timestamp) <= 10.0
        return loc.horizontalAccuracy <= 30 && recent
    }
    
    @MainActor
    private func maybeTriggerFirstLoad(using region: MKCoordinateRegion) {
        guard !gateFirstLoadDone else { return }
        guard mapFullyRendered else { return }
        guard regionStable else { return }
        guard isViewportOK(region) else { return }
        guard isAccurateLocation() || accuracyTimeoutReached else { return }
        
        gateFirstLoadDone = true
        scheduleOverlayReload(region: region, reason: "firstGate")
    }
    
}

// 🔁 SOLO una extensión mkMapType (evita redeclaraciones)
private extension MapKind {
    var mkMapType: MKMapType {
        switch self {
        case .standard: return .standard
        case .imagery:  return .satellite
        case .hybrid:   return .hybrid
        }
    }
}


// MARK: - Anotaciones helper
enum MapAnnotationItem: Identifiable {
    case spot(Spot)
    case user(CLLocationCoordinate2D)
    
    var id: String {
        switch self {
        case .spot(let s): return s.id
        case .user: return "user-location"
        }
    }
    
    var coordinate: CLLocationCoordinate2D {
        switch self {
        case .spot(let s): return CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude)
        case .user(let c): return c
        }
    }
}

// MARK: - Listener badge de chats
extension SpotsMapView {
    private func startChatsBadgeListener(for uid: String) {
        chatsListener?.remove()
        chatsListener = db.collection("chats")
            .whereField("participants", arrayContains: uid)
            .addSnapshotListener { snap, _ in
                guard let docs = snap?.documents else {
                    DispatchQueue.main.async {
                        self.chatBadgeCount = 0
                        self.chatSupportBadgeCount = 0
                    }
                    return
                }
                
                var personalUnread = 0
                var supportUnread  = 0
                
                for doc in docs {
                    let data = doc.data()
                    let participants = data["participants"] as? [String] ?? []
                    let isSupportFlag = (data["isSupport"] as? Bool) ?? false
                    let isSupportChat = isSupportFlag || participants.contains(self.SUPPORT_BOT_ID)
                    
                    let lastSenderId = data["lastSenderId"] as? String
                    guard let ts = data["updatedAt"] as? Timestamp else { continue }
                    let updatedAt = ts.dateValue()
                    
                    if lastSenderId == uid { continue }
                    
                    var lastReadDate: Date?
                    if let lr = data["lastRead"] as? [String: Any],
                       let me = lr[uid] as? Timestamp {
                        lastReadDate = me.dateValue()
                    }
                    
                    let hasUnread = (lastReadDate == nil) || (lastReadDate! < updatedAt)
                    if hasUnread {
                        if isSupportChat {
                            supportUnread += 1
                        } else {
                            personalUnread += 1
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.chatBadgeCount = personalUnread
                    self.chatSupportBadgeCount = supportUnread
                }
            }
    }
    
    private func stopChatsBadgeListener() {
        chatsListener?.remove()
        chatsListener = nil
        chatBadgeCount = 0
        chatSupportBadgeCount = 0
    }
}

// MARK: - Parseador de coordenadas
private func parseCoordinates(_ input: String) -> CLLocationCoordinate2D? {
    let comps = input
        .replacingOccurrences(of: ",", with: " ")
        .split(separator: " ")
        .map { Double($0.trimmingCharacters(in: .whitespaces)) }
    
    if comps.count == 2, let lat = comps[0], let lon = comps[1] {
        if abs(lat) <= 90, abs(lon) <= 180 {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
    }
    return nil
}

// MARK: - ViewModifier para aplicar el estilo de mapa seleccionado (iOS 17)
private struct MapStyleModifier: ViewModifier {
    let kind: MapKind
    func body(content: Content) -> some View {
        switch kind {
        case .standard:
            content.mapStyle(.standard)
        case .imagery:     // “satélite”
            content.mapStyle(.imagery)
        case .hybrid:
            content.mapStyle(.hybrid)
        }
    }
}

// MARK: - Menú de estilo de mapa (botón circular como el de la lista)
private struct MapStyleMenu: View {
    @Binding var selected: MapKind
    var body: some View {
        Menu {
            Picker("Estilo de mapa", selection: $selected) {
                Label("Estándar", systemImage: "map").tag(MapKind.standard)
                Label("Satélite", systemImage: "globe.europe.africa.fill").tag(MapKind.imagery)
                Label("Híbrido", systemImage: "map.fill").tag(MapKind.hybrid)
            }
        } label: {
            Image(systemName: "square.3.layers.3d")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.blue)
                .padding()
                .background(Color.white)
                .clipShape(Circle())
                .shadow(radius: 4)
        }
    }
}

private extension Array where Element == MKMapItem {
    func uniquedMapItems() -> [MKMapItem] {
        var seen = Set<String>()
        var out: [MKMapItem] = []
        for item in self {
            let key = "\(item.name ?? "")_\(item.placemark.coordinate.latitude.rounded(to: 5))_\(item.placemark.coordinate.longitude.rounded(to: 5))"
            if !seen.contains(key) {
                seen.insert(key)
                out.append(item)
            }
        }
        return out
    }
}

private extension Double {
    func rounded(to places: Int) -> Double {
        let p = pow(10.0, Double(places))
        return (self * p).rounded() / p
    }
}


// MARK: - Hoja de “Spots cerca de mí”
private struct NearbySpotsSheet: View {
    let spots: [Spot]
    let base: CLLocation
    @Binding var selectedSpot: Spot?
    
    var body: some View {
        NavigationView {
            List(spots, id: \.id) { s in
                Button {
                    selectedSpot = s
                } label: {
                    HStack(spacing: 12) {
                        thumb(urlString: s.imageUrl)
                            .frame(width: 46, height: 46)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(s.name).font(.subheadline.bold())
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            
                            HStack(spacing: 6) {
                                Text(s.category.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                
                                if let loc = s.locality {
                                    Text("· \(loc)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        let d = CLLocation(latitude: s.latitude, longitude: s.longitude)
                            .distance(from: base)
                        Text(distanceString(d))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.gray.opacity(0.12))
                            .cornerRadius(8)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Cerca de mí")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func thumb(urlString: String?) -> some View {
        Group {
            if let s = urlString, !s.isEmpty, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default:
                        Image("dronePlaceholder").resizable().scaledToFit().padding(6).opacity(0.8)
                    }
                }
            } else {
                Image("dronePlaceholder").resizable().scaledToFit().padding(6).opacity(0.8)
            }
        }
        .background(Color.gray.opacity(0.15))
    }
    
    private func distanceString(_ d: CLLocationDistance) -> String {
        if d >= 1000 { return String(format: "%.1f km", d / 1000.0) }
        else { return "\(Int(d)) m" }
    }
}

// MARK: - Ajustes app
private func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
}

