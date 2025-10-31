import SwiftUI
import Firebase
import FirebaseFirestore
import FirebaseAuth

extension Notification.Name {
    static let openSpotsDeepLink = Notification.Name("OpenSpotsDeepLink")
}

@main
struct SpotsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate   // 👈 añade esta línea
    @StateObject private var userSession: UserSession
    @StateObject private var auth: AuthViewModel
    @Environment(\.scenePhase) private var scenePhase   // 🆕
    
    // 🔹 VMs globales
    @StateObject private var spotsVM = SpotsViewModel()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var restriccionesVM = RestriccionesViewModel()
    @StateObject private var notamVM = NOTAMViewModel()
    @StateObject private var favoritesVM = FavoritesViewModel()
    @StateObject private var appConfig = AppConfig.shared
    
    // 🆕 App Lock (Face ID / Touch ID)
    @StateObject private var appLock = AppLockManager()   // 👈👈
    
    init() {
        FirebaseApp.configure()
        Auth.auth().useAppLanguage()
        let settings = Firestore.firestore().settings
        settings.isPersistenceEnabled = true
        Firestore.firestore().settings = settings
        
        let session = UserSession()
        _userSession = StateObject(wrappedValue: session)
        _auth = StateObject(wrappedValue: AuthViewModel(userSession: session))
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(userSession)
                .environmentObject(spotsVM)
                .environmentObject(locationManager)
                .environmentObject(restriccionesVM)
                .environmentObject(notamVM)
                .environmentObject(favoritesVM)
                .environmentObject(appConfig)
                .onAppear { appLock.lockIfNeeded() }      // 👈
            // ... dentro de WindowGroup { RootView() ... }
                .onOpenURL { url in
                    // Acepta solo nuestro esquema interno
                    guard url.scheme?.lowercased() == "spots" else { return }
                    NotificationCenter.default.post(name: .openSpotsDeepLink, object: url)
                }
            
                .overlay {                                 // 👈
                    if appLock.locked {
                        AppLockView(lock: appLock)
                            .background(Color(.systemBackground).ignoresSafeArea())
                    }
                }
        }
        .onChange(of: scenePhase) { phase in
#if DEBUG
            if FeatureFlags.oracleEnabled {
                switch phase {
                case .active:   AirspaceOracle.shared.scenePhaseChanged("active")
                case .inactive: AirspaceOracle.shared.scenePhaseChanged("inactive")
                case .background: AirspaceOracle.shared.scenePhaseChanged("background")
                @unknown default: break
                }
            }
#endif
        }
    }
}
