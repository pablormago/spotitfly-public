import SwiftUI
import UIKit
import FirebaseStorage
import FirebaseFirestore

struct RegisterView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var userSession: UserSession

    var onSwitch: (() -> Void)? = nil

    @State private var username: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @FocusState private var focused: Field?

    // Toast
    @State private var showToast = false
    @State private var toastMessage = ""

    // Comprobación de username
    @State private var isCheckingUsername = false
    @State private var isUsernameAvailable: Bool? = nil
    @State private var lastCheckTask: Task<Void, Never>? = nil

    // Imagen de perfil
    @State private var selectedImage: UIImage? = nil
    @State private var showingImagePicker = false
    @State private var showSourceDialog = false
    @State private var pickerSource: ImagePickerController.Source = .library

    // ✅ Normas de la comunidad
    @State private var acceptedGuidelines = false
    @State private var showGuidelines = false
    @State private var showAcceptAlert = false

    enum Field { case username, email, password }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)

            // Marca
            VStack(spacing: 14) {
                if UIImage(named: "Logo") != nil {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 130)
                }
                if UIImage(named: "Texto") != nil {
                    Image("Texto")
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 260)
                }
            }
            .padding(.bottom, 20)

            // Picker de imagen + username/email/pass
            VStack(spacing: 16) {
                // 📸 Avatar
                Button {
                    showSourceDialog = true
                } label: {
                    if let img = selectedImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 100, height: 100)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.blue, lineWidth: 2))
                            .shadow(radius: 4)
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 28))
                                    .foregroundColor(.blue)
                            )
                    }
                }
                .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 4) {
                    filledTextField(
                        placeholder: "Nombre de usuario",
                        text: $username,
                        isSecure: false
                    )
                    .focused($focused, equals: .username)
                    .submitLabel(.next)
                    .onSubmit { focused = .email }
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
                        .padding(.leading, 4)
                    }
                }

                filledTextField(
                    placeholder: "Correo electrónico",
                    text: $email,
                    isSecure: false
                )
                .focused($focused, equals: .email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .submitLabel(.next)
                .onSubmit { focused = .password }

                filledTextField(
                    placeholder: "Contraseña",
                    text: $password,
                    isSecure: true
                )
                .focused($focused, equals: .password)
                .submitLabel(.done)
                .onSubmit {
                    Task { await doRegister() }
                }

                // ✅ Bloque Normas de la comunidad
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $acceptedGuidelines) {
                        Text("He leído y acepto las Normas de la comunidad")
                            .font(.footnote)
                    }
                    .toggleStyle(.switch)

                    Button {
                        showGuidelines = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "book.pages.fill")
                            Text("Ver Normas de la comunidad")
                        }
                        .font(.caption)
                    }
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 10)

            // Botonera inferior
            VStack(spacing: 8) {
                Button {
                    hideKeyboard()
                    Task { await doRegister() }
                } label: {
                    Text("Registrarse")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canRegister || auth.isLoading || isUsernameAvailable == false || !acceptedGuidelines)
                .padding(.horizontal, 24)

                if let onSwitch {
                    Button("Ya tengo cuenta") { onSwitch() }
                        .buttonStyle(.plain)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.blue)
                        .padding(.top, 0)
                        .padding(.bottom, 2)
                }
            }
            .padding(.bottom, 24)
        }
        .contentShape(Rectangle())
        .onTapGesture { hideKeyboard() }
        .toolbar(.hidden, for: .navigationBar)
        .toast(isPresented: $showToast,
               message: toastMessage,
               systemImage: "checkmark.circle.fill",
               duration: 3.0)
        // 🔹 Diálogo de fuente (cámara/carrete)
        .confirmationDialog("Elegir foto de perfil", isPresented: $showSourceDialog, titleVisibility: .visible) {
            Button("Cámara") { pickerSource = .camera; showingImagePicker = true }
            Button("Carrete") { pickerSource = .library; showingImagePicker = true }
            Button("Cancelar", role: .cancel) { }
        }
        // 🔹 Picker real
        .sheet(isPresented: $showingImagePicker) {
            ImagePickerController(source: pickerSource, allowsEditing: true) { image in
                self.selectedImage = image
            }
        }
        // 🔹 Normas en hoja
        .sheet(isPresented: $showGuidelines) {
            NavigationStack { CommunityGuidelinesView() }
        }
        // 🔹 Alerta si intentan registrar sin aceptar (por si entran por teclado)
        .alert("Debes aceptar las Normas", isPresented: $showAcceptAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Para continuar es necesario aceptar las Normas de la comunidad.")
        }
    }

    private var canRegister: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty
    }

    private func doRegister() async {
        // ✅ Gate por si llegan vía teclado con .onSubmit
        guard acceptedGuidelines else {
            await MainActor.run { showAcceptAlert = true }
            return
        }

        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines)
        await auth.register(email: e, password: password, username: u)

        if let error = auth.errorMessage {
            await MainActor.run {
                toastMessage = error
                withAnimation { showToast = true }
            }
        } else {
            // Subir imagen si procede
            if let uid = userSession.uid, let img = selectedImage {
                await uploadProfileImage(uid: uid, image: img)
            }
            // ✅ Persistir aceptación de normas
            if let uid = userSession.uid {
                await persistGuidelinesAcceptance(uid: uid)
            }
            await MainActor.run {
                toastMessage = "Te hemos enviado un email de confirmación. Por favor revisa tu bandeja de entrada"
                withAnimation { showToast = true }
            }

        }
    }

    // Guarda la aceptación en /users/{uid}
    private func persistGuidelinesAcceptance(uid: String) async {
        let db = Firestore.firestore()
        do {
            try await db.collection("users").document(uid).setData([
                "acceptedGuidelines": true,
                "guidelinesAcceptedAt": FieldValue.serverTimestamp()
            ], merge: true)
        } catch {
            print("❌ Error guardando aceptación de normas: \(error.localizedDescription)")
        }
    }

    // MARK: - Username check
    private func scheduleUsernameCheck(_ name: String) {
        lastCheckTask?.cancel()
        isCheckingUsername = true
        isUsernameAvailable = nil

        lastCheckTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000) // 0.6s
            guard !Task.isCancelled else { return }
            let available = await auth.isUsernameAvailable(name.trimmingCharacters(in: .whitespacesAndNewlines))
            await MainActor.run {
                self.isCheckingUsername = false
                self.isUsernameAvailable = available
            }
        }
    }

    // MARK: - Subida de imagen
    private func uploadProfileImage(uid: String, image: UIImage) async {
        guard let data = ImageCompressor.avatarData(from: image) else { return }
        let ref = Storage.storage().reference().child("profileImages/\(uid)/avatar.jpg")
        do {
            _ = try await ref.putDataAsync(data)
            let url = try await ref.downloadURL()
            try await Firestore.firestore().collection("users").document(uid).updateData([
                "profileImageUrl": url.absoluteString
            ])
            await MainActor.run {
                self.userSession.profileImageUrl = url.absoluteString
            }
        } catch {
            print("❌ Error al subir la foto de perfil: \(error)")
        }
    }

    // MARK: - UI helpers
    @ViewBuilder
    private func filledTextField(placeholder: String, text: Binding<String>, isSecure: Bool) -> some View {
        HStack {
            if isSecure {
                SecureField(placeholder, text: text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            } else {
                TextField(placeholder, text: text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .autocorrectionDisabled(true)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
