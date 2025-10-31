import SwiftUI
import FirebaseFirestore   // 👈 lo necesitamos para hidratar el spot si no está en memoria
import FirebaseFunctions   // 👈 para joinByInvite

struct RootView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var userSession: UserSession
    @EnvironmentObject var restriccionesVM: RestriccionesViewModel
    @EnvironmentObject var notamVM: NOTAMViewModel
    @EnvironmentObject var favoritesVM: FavoritesViewModel   // 🆕
    @EnvironmentObject var spotsVM: SpotsViewModel          // ya disponible desde SpotsApp

    @State private var deepLinkSpot: Spot? = nil

    var body: some View {
        Group {
            if auth.isRestoring {
                // Pantalla neutra mientras restauramos sesión
                VStack {
                    Spacer()
                    if let _ = UIImage(named: "Logo") {
                        Image("Logo").resizable().scaledToFit().frame(maxWidth: 120)
                    }
                    ProgressView().padding(.top, 12)
                    Spacer()
                }
            } else if userSession.uid != nil {
                SpotsMapView()
                    .environmentObject(auth)
                    .environmentObject(userSession)
                    .environmentObject(restriccionesVM)
                    .environmentObject(notamVM)
                    .environmentObject(favoritesVM)   // 🆕
            } else {
                AuthView()
                    .environmentObject(auth)
                    .environmentObject(userSession)
            }
        }
        .animation(.easeInOut, value: auth.isRestoring)
        .animation(.easeInOut, value: userSession.uid != nil)
        // 🆕 Arrancar listener de favoritos al iniciar sesión
        .onChange(of: userSession.uid) { uid in
            print("🧭 RootView.onChange(uid) -> \(uid ?? "nil")")

            if let uid {
                favoritesVM.listenFavorites(userId: uid)
            } else {
                favoritesVM.favoriteIds = [] // limpiar al cerrar sesión
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSpotsDeepLink)) { note in
            // Acepta URL en object o en userInfo["url"]
            let urlFromObject = note.object as? URL
            let urlFromUserInfo: URL? = {
                if let raw = note.userInfo?["url"] as? String { return URL(string: raw) }
                return nil
            }()
            guard let url = urlFromObject ?? urlFromUserInfo else { return }
            handleDeepLinkURL(url)
        }

        .sheet(item: $deepLinkSpot) { sp in
            SpotDetailView(spot: sp)
                .environmentObject(userSession)
                .environmentObject(spotsVM)
                .environmentObject(favoritesVM)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .ignoresSafeArea()
                .environment(\.fromChat, true) // ya lo usas para pequeños ajustes de UI en detalle
        }
    }
    // Deep links "spots://...": spot, invite, coord
    private func handleDeepLinkURL(_ url: URL) {
        guard url.scheme?.lowercased() == "spots" else { return }

        let host = url.host?.lowercased()
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = path.split(separator: "/").map(String.init)

        // spots://spot/<id>
        if host == "spot", let id = parts.first, !id.isEmpty {
            openSpotFromDeepLink(id: id)
            return
        }

        // spots://invite/<CODE>
        if host == "invite", let code = parts.first, !code.isEmpty {
            Task { await joinByInviteAndHandoff(code: code.uppercased()) }
            return
        }

        // spots://coord/<lat>/<lon>  (si tienes handler, llámalo aquí)
        if host == "coord", parts.count >= 2 {
            // TODO: implementar si procede
            return
        }
    }


    @MainActor
    private func openSpotFromDeepLink(id: String) {
        // 1) Intenta desde memoria (SpotsViewModel)
        if let sp = spotsVM.spots.first(where: { $0.id == id }) {
            spotsVM.syncFavorites(favorites: favoritesVM.favoriteIds)
            deepLinkSpot = spotsVM.spots.first(where: { $0.id == id }) ?? sp
            return
        }

        // 2) Hidrata desde Firestore si no estaba en memoria
        let db = Firestore.firestore()
        db.collection("spots").document(id).getDocument { snap, err in
            if let err { print("❌ DeepLink load spot:", err.localizedDescription); return }
            do {
                guard let snap, snap.exists else { return }
                let sp: Spot = try snap.data(as: Spot.self)
                var sp2 = sp
                sp2.isFavorite = favoritesVM.favoriteIds.contains(sp.id)
                DispatchQueue.main.async {
                    spotsVM.syncFavorites(favorites: favoritesVM.favoriteIds)
                    deepLinkSpot = spotsVM.spots.first(where: { $0.id == id }) ?? sp2
                }
            } catch {
                print("❌ decode DeepLink Spot:", error.localizedDescription)
            }
        }
    }
    
    @MainActor
    private func joinByInviteAndHandoff(code: String) async {
        do {
            let fn = Functions.functions(region: "europe-west1").httpsCallable("joinByInvite")
            let result = try await fn.call(["code": code])
            var chatId: String? = nil
            if let dict = result.data as? [String: Any] {
                chatId = (dict["chatId"] as? String) ?? (dict["id"] as? String)
            }
            if let chatId {
                // Notifica a quien tenga que abrir el chat (p. ej. ChatsHomeView)
                NotificationCenter.default.post(name: .init("OpenChatById"), object: chatId)
                print("✅ Unido por invite. chatId=\(chatId)")
            } else {
                print("⚠️ joinByInvite sin chatId en la respuesta")
            }
        } catch {
            print("❌ joinByInvite:", error.localizedDescription)
        }
    }


}
