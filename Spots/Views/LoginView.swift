import SwiftUI
import UIKit
import FirebaseAuth
import FirebaseFirestore

struct LoginView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var userSession: UserSession
    
    var onSwitch: (() -> Void)? = nil
    
    @State private var email: String = ""
    @State private var password: String = ""
    @FocusState private var focused: Field?
    
    // Reset password
    @State private var showPasswordReset: Bool = false
    @State private var resetEmail: String = ""
    @State private var resetMessage: String?
    
    // Toast
    @State private var showToast = false
    @State private var toastMessage = ""
    
    enum Field { case email, password }
    
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
            .padding(.bottom, 15)
            
            // Campos
            VStack(spacing: 16) {
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
                .onSubmit { Task { await doLogin() } }
                
                // ¿Has olvidado tu contraseña?
                Button("¿Has olvidado tu contraseña?") {
                    resetEmail = email
                    showPasswordReset = true
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.blue)
                .frame(maxWidth: .infinity, alignment: .center)
                
                Button("Reenviar email de verificación") {
                    Task { await resendVerification() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.blue)
                
            }
            .padding(.horizontal, 24)
            
            Spacer(minLength: 10)
            
            // Botonera inferior — más fina
            VStack(spacing: 8) {
                Button {
                    hideKeyboard()
                    Task { await doLogin() }
                } label: {
                    Text("Iniciar sesión")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!canLogin || auth.isLoading)
                .padding(.horizontal, 24)
                
                if onSwitch != nil {
                    Button("Crear cuenta") { onSwitch?() }
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
        .alert("Restablecer contraseña", isPresented: $showPasswordReset) {
            TextField("Introduce tu email", text: $resetEmail)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            
            Button("Cancelar", role: .cancel) {}
            Button("Enviar") { resetPassword() }
        } message: {
            if let resetMessage {
                Text(resetMessage)
            } else {
                Text("Recibirás un email para restablecer tu contraseña.")
            }
        }
        .toast(isPresented: $showToast, message: toastMessage, duration: 3.0)
    }
    
    private var canLogin: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.isEmpty
    }
    
    private func doLogin() async {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        await auth.login(email: e, password: password)
        
        if let err = auth.errorMessage {
            await MainActor.run {
                toastMessage = err   // ← usamos el mensaje del ViewModel (incluye “email no verificado”)
                withAnimation { showToast = true }
                print("❌ Login error: \(err)")
            }
        } else {
            // ✅ si login correcto, refrescamos profileImageUrl en sesión
            if let uid = userSession.uid {
                Task {
                    do {
                        let doc = try await Firestore.firestore().collection("users").document(uid).getDocument()
                        if let url = doc.data()?["profileImageUrl"] as? String {
                            await MainActor.run { self.userSession.profileImageUrl = url }
                        }
                    } catch {
                        print("❌ Error al cargar avatar tras login:", error)
                    }
                }
            }
        }
    }
    
    // MARK: - Reset password
    // MARK: - Reset password
    private func resetPassword() {
        let e = resetEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty else {
            resetMessage = "Introduce un correo válido."
            return
        }
        
        // Opción A: seguir el idioma del dispositivo
        Auth.auth().useAppLanguage()
        
        // Opción B (alternativa): forzar SIEMPRE español
        // Auth.auth().languageCode = "es"
        
        Auth.auth().sendPasswordReset(withEmail: e) { error in
            if let error {
                resetMessage = "Error: \(error.localizedDescription)"
            } else {
                resetMessage = "Correo de restablecimiento enviado."
            }
        }
    }
    
    private func resendVerification() async {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Si hay usuario logueado y NO verificado: reenvía directamente
        if let current = Auth.auth().currentUser, current.isEmailVerified == false {
            Auth.auth().useAppLanguage()
            current.sendEmailVerification { _ in }
            await MainActor.run {
                toastMessage = "Te hemos enviado un email de verificación."
                withAnimation { showToast = true }
            }
            return
        }
        
        // Si no hay sesión: usar email/contraseña del formulario para firmar, re-enviar y cerrar sesión
        guard !e.isEmpty else {
            await MainActor.run {
                toastMessage = "Introduce tu email."
                withAnimation { showToast = true }
            }
            return
        }
        
        // Si no hay contraseña, no podemos firmar para enviar verificación
        guard !password.isEmpty else {
            await MainActor.run {
                toastMessage = "Introduce también tu contraseña o inicia sesión para reenviar la verificación."
                withAnimation { showToast = true }
            }
            return
        }
        
        do {
            let result = try await Auth.auth().signIn(withEmail: e, password: password)
            if result.user.isEmailVerified {
                try? Auth.auth().signOut()
                await MainActor.run {
                    toastMessage = "Tu email ya estaba verificado."
                    withAnimation { showToast = true }
                }
            } else {
                Auth.auth().useAppLanguage()
                result.user.sendEmailVerification { _ in }
                try? Auth.auth().signOut()
                await MainActor.run {
                    toastMessage = "Te hemos enviado un email de verificación."
                    withAnimation { showToast = true }
                }
            }
        } catch {
            await MainActor.run {
                toastMessage = "No se pudo reenviar la verificación. Prueba a restablecer tu contraseña."
                withAnimation { showToast = true }
            }
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
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}
