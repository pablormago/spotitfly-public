import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseMessaging


@MainActor
final class AuthViewModel: ObservableObject {
    // UI state
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    /// Mientras Firebase restaura la sesión (arranque de la app) mostramos splash.
    @Published var isRestoring: Bool = true
    
    // Session
    let userSession: UserSession
    
    // Firebase
    private let auth = Auth.auth()
    private let db = Firestore.firestore()
    private var authHandle: AuthStateDidChangeListenerHandle?
    
    init(userSession: UserSession) {
        self.userSession = userSession
        
        // Listener de cambios de autenticación (restaura sesión al arrancar)
        authHandle = auth.addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            
            if let user {
                // Actualiza sesión mínima
                self.userSession.uid = user.uid
                self.userSession.email = user.email
                
                // 🔹 Inicia presencia global
                PresenceService.shared.start()
                
                // 🔔 Sincroniza el badge del icono en tiempo real
                BadgeSync.shared.start()
                
                // BEGIN PATCH (añadir esta línea)
                Task { await self.registerFCMDeviceToken(uid: user.uid) }
                // END PATCH
                
                // Cargar perfil completo desde Firestore
                Task { await self.refreshProfile(uid: user.uid) }
            } else {
                // 🔹 Detiene presencia global
                PresenceService.shared.stop()
                
                // 🔔 Detiene sincronización de badge
                BadgeSync.shared.stop()
                
                // Limpia sesión
                self.userSession.clear()
                
                // 🧹 Limpieza de cachés al cerrar sesión
                Task {
                    await ImageCache.shared.clear()
                }
            }
            
            // Importante: desactivar la pantalla de restauración
            if self.isRestoring { self.isRestoring = false }
        }
    }
    
    deinit {
        if let h = authHandle {
            auth.removeStateDidChangeListener(h)
        }
    }
    
    // MARK: - Actions
    
    func login(email: String, password: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        
        do {
            let result = try await auth.signIn(withEmail: email, password: password)
            // 🚫 Bloquea si no está verificado
            if !result.user.isEmailVerified {
                // Reenvía verificación en español
                Auth.auth().useAppLanguage()
                result.user.sendEmailVerification { err in
                    if let err = err {
                        print("❌ Error reenviando verificación:", err)
                    } else {
                        print("✅ Verificación reenviada")
                    }
                }
                // Cierra sesión para no entrar a la app
                try? auth.signOut()
                // Mensaje para UI (LoginView mostrará toast)
                errorMessage = "Tu email no está verificado. Te hemos enviado un correo de confirmación."
                return
            }
            // El listener actualizará userSession y PresenceService si verificado
        } catch {
            print("AuthViewModel.login error:", error)
            errorMessage = "No se pudo iniciar sesión. Revisa tus credenciales."
        }
    }

    
    func register(email: String, password: String, username: String) async {
        errorMessage = nil
        isLoading = true
        defer { isLoading = false }
        
        // ✅ 1) Pre-check: no intentes crear si el email ya está en uso
        if await emailAlreadyRegistered(email) {
            self.errorMessage = "Ese email ya está en uso. Prueba con otro."
            return
        }
        
        // ✅ 2) Crear usuario
        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            let uid = result.user.uid

            // Crea/actualiza documento en /users
            let data: [String: Any] = [
                "uid": uid,
                "email": email,
                "username": username,
                "usernameLower": username.lowercased(),
                "profileImageUrl": "",   // inicial vacío
                "createdAt": FieldValue.serverTimestamp()
            ]
            try await db.collection("users").document(uid).setData(data, merge: true)

            // 📧 Enviar email de verificación (en el idioma del dispositivo)
            Auth.auth().useAppLanguage()
            result.user.sendEmailVerification { err in
                if let err = err {
                    print("❌ Error al enviar verificación:", err)
                } else {
                    print("✅ Email de verificación enviado")
                }
            }
            
            // Refleja en sesión inmediatamente
            userSession.uid = uid
            userSession.email = email
            userSession.username = username
            userSession.profileImageUrl = nil
            
            // 🔹 Arranca presencia
            PresenceService.shared.start()
            
        } catch {
            // Robustez extra: si fallara por cualquier motivo, mapea bien el error de FirebaseAuth
            if let err = error as NSError?,
               let code = AuthErrorCode(_bridgedNSError: err) {
                switch code.code {
                case .emailAlreadyInUse:
                    self.errorMessage = "Ese email ya está en uso. Prueba con otro."
                case .weakPassword:
                    self.errorMessage = "La contraseña es demasiado débil."
                case .invalidEmail:
                    self.errorMessage = "El correo no es válido."
                default:
                    print("AuthViewModel.register error:", error)
                    self.errorMessage = "No se pudo crear la cuenta. Inténtalo de nuevo."
                }
            } else {
                print("AuthViewModel.register error:", error)
                self.errorMessage = "No se pudo crear la cuenta. Inténtalo de nuevo."
            }
        }
    }
    
    func logout() {
        do {
            // 🔹 Para presencia antes de salir
            PresenceService.shared.stop()
            try auth.signOut()
            
            // Limpieza de sesión local
            userSession.clear()
            
            // 🧹 Limpieza de cachés al cerrar sesión
            Task {
                await ImageCache.shared.clear()
            }
        } catch {
            print("AuthViewModel.logout error:", error)
        }
    }
    
    // MARK: - Username availability
    func isUsernameAvailable(_ username: String) async -> Bool {
        let uname = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !uname.isEmpty else { return false }
        
        do {
            let snap = try await db.collection("users")
                .whereField("usernameLower", isEqualTo: uname)
                .limit(to: 1)
                .getDocuments()
            return snap.documents.isEmpty
        } catch {
            print("❌ Error comprobando username:", error.localizedDescription)
            return false
        }
    }
    
    // MARK: - Profile
    func refreshProfile(uid: String) async {
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            if doc.exists, let data = doc.data() {
                applyProfileData(data)
                return
            }
            
            // Fallback búsqueda por uid
            let snap = try await db.collection("users")
                .whereField("uid", isEqualTo: uid)
                .limit(to: 1)
                .getDocuments()
            
            if let first = snap.documents.first {
                applyProfileData(first.data())
                return
            }
            
            // No hay datos
            userSession.username = nil
            userSession.profileImageUrl = nil
        } catch {
            print("AuthViewModel.refreshProfile error:", error)
        }
    }
    
    private func applyProfileData(_ data: [String: Any]) {
        if let name = (data["username"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            userSession.username = name
        }
        
        if let url = data["profileImageUrl"] as? String,
           !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            userSession.profileImageUrl = url
            
            Task {
                // 🔹 Descarga (si no está) y guarda en disco
                if let img = await ImageCache.shared.image(for: url) {
                    await MainActor.run {
                        self.userSession.localAvatar = img
                        UserSession.saveLocalAvatar(image: img)
                    }
                }
            }
        } else {
            userSession.profileImageUrl = nil
            userSession.localAvatar = nil
            UserSession.deleteLocalAvatar()
        }
    }
    
    // MARK: - Helpers
    /// Devuelve true si hay algún método de login registrado para ese email (email ya usado)
    private func emailAlreadyRegistered(_ email: String) async -> Bool {
        await withCheckedContinuation { cont in
            auth.fetchSignInMethods(forEmail: email) { methods, error in
                if let error {
                    // En caso de error de red u otro, no bloqueamos el registro por defecto
                    print("⚠️ fetchSignInMethods error:", error)
                    cont.resume(returning: false)
                    return
                }
                cont.resume(returning: !(methods ?? []).isEmpty)
            }
        }
    }
    // MARK: - Push token registration (post-login)
    // MARK: - Push token registration (post-login) esperando APNs
    private func registerFCMDeviceToken(uid: String) async {
        // Espera a que Messaging tenga apnsToken (máx ~5s con reintentos cortos)
        let apnsReady = await waitForAPNsToken(timeoutSeconds: 5)
        if !apnsReady {
            print("⏳ APNs token not ready after wait; skipping rescue now.")
            return
        }
        
        do {
            // Con APNs listo, pide el FCM token
            let token = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                Messaging.messaging().token { token, error in
                    if let token { cont.resume(returning: token) }
                    else { cont.resume(throwing: error ?? NSError(domain: "FCM", code: -1, userInfo: nil)) }
                }
            }
            
            // Guarda/actualiza en Firestore: users/{uid}/devices/{token}
            let ref = Firestore.firestore()
                .collection("users").document(uid)
                .collection("devices").document(token)
            
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                ref.setData([
                    "platform": "ios",
                    "updatedAt": FieldValue.serverTimestamp(),
                    "language": Locale.preferredLanguages.first ?? "es-ES"
                ], merge: true) { error in
                    if let error { cont.resume(throwing: error) } else { cont.resume() }
                }
            }
            
            print("✅ Saved FCM token to Firestore (post-login):", token)
        } catch {
            print("⚠️ Could not fetch/save FCM token (post-login):", error.localizedDescription)
        }
    }
    
    // Espera activa suave a que Firebase Messaging tenga apnsToken
    private func waitForAPNsToken(timeoutSeconds: Int) async -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutSeconds))
        while Messaging.messaging().apnsToken == nil && Date() < deadline {
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
        }
        return Messaging.messaging().apnsToken != nil
    }
    
    
}
