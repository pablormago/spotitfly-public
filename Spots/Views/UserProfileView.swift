//
//  UserProfileView.swift
//  Spots
//

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import Foundation
import LocalAuthentication   // Face ID / Touch ID
import UserNotifications

struct UserProfileView: View {
    // MARK: - Env
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var userSession: UserSession
    @Environment(\.horizontalSizeClass) private var hSizeClass

    // MARK: - Imagen de perfil
    @State private var showingImagePicker = false
    @State private var showSourceDialog = false
    @State private var showSourceSheet = false   // iPad
    @State private var pickerSource: ImagePickerController.Source = .library
    @State private var profileImage: UIImage? = nil

    // MARK: - Username
    @State private var username: String = ""
    @State private var isCheckingUsername = false
    @State private var isUsernameAvailable: Bool? = nil
    @State private var lastCheckTask: Task<Void, Never>? = nil

    // MARK: - Número de operador (solo local)
    @State private var operatorNumber: String = ""

    // MARK: - Navegación (preferencia local)
    @State private var availableNavApps: [NavigationApp] = []
    @State private var preferredNavApp: NavigationApp = .apple

    // MARK: - Toast / Logout
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var showLogoutConfirm = false

    // MARK: - Admin unlock
    @State private var adminTapCount = 0
    @State private var showAdminUnlock = false
    @State private var adminEmailInput = ""
    @State private var adminPasswordInput = ""
    @State private var adminUnlockInProgress = false
    @State private var adminUnlockError: String? = nil
    @State private var showAdminPanel = false
    @State private var attemptedAdminBiometric = false

    // Cambia aquí tu email admin
    private let ADMIN_EMAIL = "pablormago@gmail.com"

    // MARK: - Notificaciones (mantengo tu lógica existente)
    @State private var notifAll = true
    @State private var notifMessages = true
    @State private var notifComments = true

    // MARK: - Body
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // AVATAR + acciones
                VStack(spacing: 12) {
                    avatarView()
                        .id(userSession.avatarBustToken)
                        .shadow(radius: 4)

                    HStack(spacing: 12) {
                        Button {
                            // iPad → sheet, iPhone → confirmationDialog
                            if hSizeClass == .regular {
                                showSourceSheet = true
                            } else {
                                showSourceDialog = true
                            }
                        } label: {
                            Label("Cambiar foto", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            Task { await removeProfilePhoto() }
                        } label: {
                            Label("Quitar foto", systemImage: "trash.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    }
                    .font(.footnote)
                    .padding(.horizontal)
                }

                // CERRAR SESIÓN (botón ancho y limpio)
                Button {
                    showLogoutConfirm = true
                } label: {
                    Label("Cerrar sesión", systemImage: "rectangle.portrait.and.arrow.right")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .padding(.horizontal)
                .padding(.top, -6)

                // CARD: Username
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nombre de usuario")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Nombre de usuario", text: $username)
                        .textInputAutocapitalization(.never)
                        .disableAutocorrection(true)
                        .padding()
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)
                        .onChange(of: username) { newValue in
                            scheduleUsernameCheck(newValue)
                        }

                    if let available = isUsernameAvailable {
                        HStack(spacing: 6) {
                            Image(systemName: available ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundColor(available ? .green : .red)
                            Text(available ? "Disponible" : "No disponible")
                                .font(.footnote)
                                .foregroundColor(available ? .green : .red)
                        }
                    }
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06)))
                .padding(.horizontal)

                // CARD: Número de operador (solo local)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Número de operador")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    TextField("Ej.: ESP-XXXX-YYYY", text: $operatorNumber)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .padding()
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)

                    Text("Este dato se guarda únicamente en tu dispositivo. No se sube a la nube ni a Firestore.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06)))
                .padding(.horizontal)

                // BOTONES primarios
                VStack(spacing: 12) {
                    Divider().padding(.horizontal)

                    // Guardar cambios
                    Button {
                        Task {
                            var didUpdate = false

                            // Guardar Número de operador (local)
                            let op = operatorNumber.trimmingCharacters(in: .whitespacesAndNewlines)
                            UserDefaults.standard.set(op, forKey: "operatorNumber")
                            didUpdate = true

                            // Foto de perfil
                            if let img = profileImage, let uid = userSession.uid {
                                let (newUrl, newBust) = try await UserService.shared.updateProfileImage(img, for: uid)
                                userSession.profileImageUrl = newUrl
                                userSession.avatarBustToken = newBust
                                // Guardar avatar local
                                UserSession.saveLocalAvatar(image: img)
                                userSession.localAvatar = img
                                didUpdate = true
                            }

                            // Username (con uid seguro)
                            if let uid = userSession.uid {
                                let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !u.isEmpty {
                                    try? await UserService.shared.updateUsername(u, for: uid)
                                    userSession.username = u
                                    didUpdate = true
                                }
                            }

                            if didUpdate {
                                await MainActor.run {
                                    toastMessage = "Cambios guardados"
                                    withAnimation { showToast = true }
                                }
                            } else {
                                await MainActor.run {
                                    toastMessage = "Sin cambios"
                                    withAnimation { showToast = true }
                                }
                            }
                        }
                    } label: {
                        Text("Guardar cambios")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)

                    // Enlaces útiles
                    NavigationLink("Normas de la comunidad") {
                        CommunityGuidelinesView()
                    }

                    NavigationLink {
                        UserSpotsListView()
                    } label: {
                        Text("Mis Spots")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding(.horizontal)
                }

                // CARD: Notificaciones
                VStack(alignment: .leading, spacing: 10) {
                    Text("Notificaciones")
                        .font(.headline)

                    Toggle("Activar notificaciones", isOn: $notifAll)
                        .onChange(of: notifAll) { new in
                            if new { requestPushIfNeeded() }
                            notifMessages = new ? true : notifMessages
                            notifComments = new ? true : notifComments
                            savePrefs()
                        }

                    Divider()

                    Toggle("Mensajes", isOn: $notifMessages)
                        .disabled(!notifAll)
                        .onChange(of: notifMessages) { _ in savePrefs() }

                    Divider()

                    Toggle("Comentarios en mis spots", isOn: $notifComments)
                        .disabled(!notifAll)
                        .onChange(of: notifComments) { _ in savePrefs() }
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06)))
                .padding(.horizontal)

                // CARD: Navegación (Waze / Google / Apple)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Navegación")
                        .font(.headline)

                    if availableNavApps.count > 1 {
                        Picker("App de navegación", selection: $preferredNavApp) {
                            ForEach(availableNavApps) { app in
                                Text(app.displayName).tag(app)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: preferredNavApp) { newValue in
                            NavigationHelper.setPreferred(newValue)
                        }
                    } else if let only = availableNavApps.first {
                        HStack {
                            Text("App de navegación")
                            Spacer()
                            Text(only.displayName).foregroundColor(.secondary)
                        }
                    } else {
                        Text("No se ha detectado ninguna app de navegación.")
                            .foregroundColor(.secondary)
                    }

                    Text("Tu preferencia se guarda solo en este dispositivo.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.black.opacity(0.06)))
                .padding(.horizontal)

                Spacer()
            }
            .padding(.top, 32)
        }
        // Aparición
        .onAppear {
            if let current = userSession.username {
                username = current
            }
            if let savedOp = UserDefaults.standard.string(forKey: "operatorNumber") {
                operatorNumber = savedOp
            }
            // Navegación: cargar apps y preferencia
            let apps = NavigationHelper.installedApps()
            availableNavApps = apps
            preferredNavApp = NavigationHelper.preferred(available: apps)

            // Notificaciones (mantengo tu carga)
            loadPrefs()
        }

        // Diálogo de cámara/carrete (iPhone)
        .confirmationDialog("Elegir foto de perfil", isPresented: $showSourceDialog, titleVisibility: .visible) {
            Button("Cámara") { pickerSource = .camera; showingImagePicker = true }
            Button("Carrete") { pickerSource = .library; showingImagePicker = true }
            Button("Cancelar", role: .cancel) { }
        }

        // Sheet de selección (iPad)
        .sheet(isPresented: $showSourceSheet) {
            NavigationView {
                List {
                    Section {
                        Button {
                            pickerSource = .camera
                            showingImagePicker = true
                            showSourceSheet = false
                        } label: {
                            Label("Cámara", systemImage: "camera")
                        }
                        Button {
                            pickerSource = .library
                            showingImagePicker = true
                            showSourceSheet = false
                        } label: {
                            Label("Carrete", systemImage: "photo.on.rectangle")
                        }
                    }
                    Section {
                        Button("Cancelar", role: .cancel) {
                            showSourceSheet = false
                        }
                    }
                }
                .navigationTitle("Elegir foto")
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium])
        }

        // Picker real
        .sheet(isPresented: $showingImagePicker) {
            ImagePickerController(source: pickerSource, allowsEditing: true) { image in
                self.profileImage = image
            }
        }

        // Gate admin: sheet de login + biometría auto
        .sheet(isPresented: $showAdminUnlock) {
            NavigationView {
                VStack(spacing: 16) {
                    Text("Acceso administrador")
                        .font(.title3.bold())
                        .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.caption).foregroundColor(.secondary)
                        TextField("tu.email@dominio.com", text: $adminEmailInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .padding()
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(10)

                        Text("Contraseña")
                            .font(.caption).foregroundColor(.secondary)
                        SecureField("••••••••", text: $adminPasswordInput)
                            .textContentType(.password)
                            .padding()
                            .background(Color(uiColor: .secondarySystemBackground))
                            .cornerRadius(10)
                    }
                    .padding(.horizontal)

                    if let err = adminUnlockError {
                        Text(err)
                            .font(.footnote)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }

                    Button {
                        Task { await handleAdminUnlock() }
                    } label: {
                        HStack {
                            if adminUnlockInProgress { ProgressView().padding(.trailing, 6) }
                            Text("Entrar")
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(adminUnlockInProgress || adminEmailInput.isEmpty || adminPasswordInput.isEmpty)
                    .padding(.horizontal)

                    Spacer()
                }
                .navigationBarItems(leading: Button("Cancelar") { showAdminUnlock = false })
            }
            .task {
                if !attemptedAdminBiometric {
                    attemptedAdminBiometric = true
                    await unlockAdminWithBiometrics()
                }
            }
        }

        // Panel admin
        .sheet(isPresented: $showAdminPanel) {
            NavigationView {
                AdminHomeView()
                    .navigationBarTitleDisplayMode(.inline)
            }
        }

        .navigationTitle("Perfil")
        .navigationBarTitleDisplayMode(.inline)
        .toast(isPresented: $showToast,
               message: toastMessage,
               systemImage: "checkmark.circle.fill",
               duration: 2.0)
        .alert("¿Seguro que quieres cerrar sesión?",
               isPresented: $showLogoutConfirm) {
            Button("Cerrar sesión", role: .destructive) {
                auth.logout()
            }
            Button("Cancelar", role: .cancel) { }
        }
    }

    // MARK: - Helpers de notificaciones (mantengo tu lógica)
    private func requestPushIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { s in
            guard s.authorizationStatus != .authorized else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                if granted {
                    DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
                }
            }
        }
    }

    private func savePrefs() {
        guard let uid = userSession.uid else { return }
        let ref = Firestore.firestore()
            .collection("users").document(uid)
            .collection("meta").document("notifications")

        let lang = Locale.preferredLanguages.first ?? "es"
        let data: [String:Any] = [
            "enabled": notifAll,
            "messages": notifMessages,
            "comments": notifComments,
            "lang": lang,
            "updatedAt": FieldValue.serverTimestamp()
        ]
        ref.setData(data, merge: true)
    }

    private func loadPrefs() {
        guard let uid = userSession.uid else { return }
        let ref = Firestore.firestore()
            .collection("users").document(uid)
            .collection("meta").document("notifications")

        ref.getDocument { snap, _ in
            guard let d = snap?.data() else { return }
            self.notifAll      = (d["enabled"]  as? Bool) ?? true
            self.notifMessages = (d["messages"] as? Bool) ?? true
            self.notifComments = (d["comments"] as? Bool) ?? true
        }
    }

    // MARK: - Avatar con anillos + 5 taps admin
    private func avatarView() -> some View {
        ZStack {
            Circle()
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.0, green: 0.85, blue: 0.9),
                            Color(red: 0.2, green: 0.5, blue: 1.0)
                        ]),
                        center: .center
                    ),
                    lineWidth: 12
                )
                .frame(width: 136, height: 136)

            Circle()
                .fill(Color.white)
                .frame(width: 128, height: 128)

            if let uiImage = profileImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
            } else if let local = userSession.localAvatar {
                Image(uiImage: local)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
            } else if let url = userSession.profileImageUrl, !url.isEmpty {
                AsyncImageLoader(
                    urlString: url,
                    bustToken: userSession.avatarBustToken
                ) { image in
                    image.resizable()
                        .scaledToFill()
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                } placeholder: {
                    ZStack {
                        Circle()
                            .fill(Color.gray.opacity(0.15))
                            .frame(width: 120, height: 120)
                        ProgressView()
                    }
                }
            } else {
                placeholderAvatar(initials: userSession.username)
                    .frame(width: 120, height: 120)
                    .clipShape(Circle())
            }
        }
        .onTapGesture(count: 5) {
            adminTapCount = 0
            adminEmailInput = ""
            adminPasswordInput = ""
            adminUnlockError = nil
            attemptedAdminBiometric = false
            showAdminUnlock = true
        }
    }

    // MARK: - Username check
    private func scheduleUsernameCheck(_ name: String) {
        lastCheckTask?.cancel()
        isCheckingUsername = true
        isUsernameAvailable = nil

        lastCheckTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000) // 600ms
            guard !Task.isCancelled else { return }

            let newName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            var available = await auth.isUsernameAvailable(newName)

            if newName.lowercased() == userSession.username?.lowercased() {
                available = true
            }

            await MainActor.run {
                self.isCheckingUsername = false
                self.isUsernameAvailable = available
            }
        }
    }

    // MARK: - Quitar foto
    private func removeProfilePhoto() async {
        guard let uid = userSession.uid else { return }
        do {
            try await UserService.shared.deleteProfileImage(for: uid)
            await MainActor.run {
                userSession.profileImageUrl = nil
                userSession.avatarBustToken = UUID().uuidString
                profileImage = nil
                UserSession.deleteLocalAvatar()
                userSession.localAvatar = nil
                toastMessage = "Foto eliminada"
                withAnimation { showToast = true }
            }
        } catch {
            print("❌ Error al eliminar foto de perfil:", error)
        }
    }

    // MARK: - Placeholder
    private func placeholderAvatar(initials: String?) -> some View {
        let letters = String((initials ?? "U").prefix(2)).uppercased()
        return ZStack {
            Circle().fill(Color.blue.opacity(0.2))
            Text(letters)
                .font(.largeTitle.bold())
                .foregroundColor(.blue)
        }
    }

    // MARK: - Admin unlock (email + password)
    private func handleAdminUnlock() async {
        guard let user = Auth.auth().currentUser else {
            await MainActor.run { self.adminUnlockError = "No hay usuario autenticado." }
            return
        }
        let inputMail = self.adminEmailInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard inputMail == self.ADMIN_EMAIL.lowercased() else {
            await MainActor.run { self.adminUnlockError = "Email no permitido." }
            return
        }
        await MainActor.run { self.adminUnlockInProgress = true; self.adminUnlockError = nil }
        defer { Task { @MainActor in self.adminUnlockInProgress = false } }
        do {
            guard user.email?.lowercased() == inputMail else {
                await MainActor.run { self.adminUnlockError = "La sesión activa no coincide con ese email." }
                return
            }
            let cred = EmailAuthProvider.credential(withEmail: inputMail, password: self.adminPasswordInput)
            try await user.reauthenticate(with: cred)
            UserDefaults.standard.set(true, forKey: "adminModeEnabled")
            await MainActor.run { self.showAdminUnlock = false; self.showAdminPanel = true }
        } catch {
            await MainActor.run { self.adminUnlockError = "Error: \(error.localizedDescription)" }
        }
    }

    // MARK: - Admin biometric unlock
    private func unlockAdminWithBiometrics() async {
        let context = LAContext()
        var err: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            await MainActor.run { self.adminUnlockError = "Face ID / Touch ID no disponible en este dispositivo." }
            return
        }
        do {
            let ok = try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                      localizedReason: "Entrar como administrador")
            if ok {
                let currentMail = Auth.auth().currentUser?.email?.lowercased()
                if currentMail == self.ADMIN_EMAIL.lowercased() {
                    await MainActor.run { self.showAdminUnlock = false; self.showAdminPanel = true }
                } else {
                    await MainActor.run { self.adminUnlockError = "La sesión actual no coincide con el email admin." }
                }
            }
        } catch {
            await MainActor.run { self.adminUnlockError = "No se pudo verificar con Face ID / Touch ID." }
        }
    }
}
