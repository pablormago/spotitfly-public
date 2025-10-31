

import SwiftUI
import FirebaseAuth
import FirebaseFirestore
import Foundation
import UIKit
import LinkPresentation
import FirebaseFunctions
import UniformTypeIdentifiers

// MARK: - Notificación tipada (ya existía en tu proyecto)
extension Notification.Name {
    static let userReportedFromProfile = Notification.Name("UserReportedFromProfile")
}

struct ChatDetailView: View {
    
    @Environment(\.scenePhase) private var scenePhase
    // 🔗 Necesitamos acceso a los VMs porque SpotDetailView depende de ellos
    @EnvironmentObject var spotsVM: SpotsViewModel
    @EnvironmentObject var favoritesVM: FavoritesViewModel
    @EnvironmentObject var userSession: UserSession
    @Environment(\.colorScheme) private var colorScheme
    
    
    
    let chat: Chat
    var backLabel: String = "Chats"
    var supportMode: Bool = false
    
    private let SUPPORT_BOT_ID = "26CSxWS7R7eZlrvXUV1qJFyL7Oc2"
    
    @StateObject private var vm: ChatViewModel
    @State private var input: String = ""
    @State private var isReady = false
    @State private var userStatus: String = "conectando…"
    @State private var showProfileSheet = false
    
    // Grupo (UI)
    @State private var showGroupSheet = false
    @State private var isGroupMuted = false
    
    // Miembros resueltos (nombres/avatares reales, sin UID en UI)
    @State private var groupMembers: [MemberRow] = []
    
    
    
    // 🔎 Búsqueda
    @State private var searchText: String = ""
    @State private var isSearching: Bool = false
    @State private var searchResults: [String] = []
    @State private var currentResultIndex: Int = 0
    
    @State private var mentionQuery: String = ""
    @State private var showMentionList: Bool = false
    
    @State private var suggestionsBoxHeight: CGFloat = 0
    
    
    // 🗺️ Sheet local para detalle de spot
    @State private var sheetSpot: Spot? = nil
    
    private var db = Firestore.firestore()
    @State private var statusListener: ListenerRegistration?
    
    @Environment(\.dismiss) private var dismiss
    
    // 🆕 Toast (moderación / avisos)
    @State private var showToast = false
    @State private var toastMessage: String = ""
    @State private var toastIcon: String? = nil
    
    init(chat: Chat, backLabel: String = "Chats", supportMode: Bool = false) {
        self.chat = chat
        self.backLabel = backLabel
        self.supportMode = supportMode
        _vm = StateObject(wrappedValue: ChatViewModel(chatId: chat.id))
    }
    
    var body: some View {
        let myUid = Auth.auth().currentUser?.uid ?? ""
        let actorId = supportMode ? SUPPORT_BOT_ID : myUid
        
        VStack(spacing: 0) {
            if !isReady {
                Spacer()
                ProgressView("Cargando mensajes…").padding()
                Spacer()
            } else {
                VStack(spacing: 0) {
                    if isSearching {
                        VStack(spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.gray)
                                
                                TextField("Buscar en este chat", text: $searchText)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled(true)
                                    .onChange(of: searchText) { _ in
                                        recalcSearchResults()
                                    }
                                
                                if !searchText.isEmpty {
                                    Button {
                                        searchText = ""
                                        searchResults = []
                                        currentResultIndex = 0
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.gray)
                                    }
                                }
                                
                                Button("Cancelar") {
                                    searchText = ""
                                    searchResults = []
                                    currentResultIndex = 0
                                    isSearching = false
                                }
                                .foregroundColor(.blue)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            
                            if !searchResults.isEmpty {
                                HStack {
                                    Text("\(currentResultIndex + 1) de \(searchResults.count)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button {
                                        guard !searchResults.isEmpty else { return }
                                        currentResultIndex = (currentResultIndex - 1 + searchResults.count) % searchResults.count
                                    } label: { Image(systemName: "chevron.up") }
                                        .disabled(searchResults.isEmpty)
                                    
                                    Button {
                                        guard !searchResults.isEmpty else { return }
                                        currentResultIndex = (currentResultIndex + 1) % searchResults.count
                                    } label: { Image(systemName: "chevron.down") }
                                        .disabled(searchResults.isEmpty)
                                }
                                .padding(.horizontal)
                                .padding(.bottom, 4)
                            }
                        }
                    }
                    
                    // Lista de mensajes ➜ IMPORTANT: pasamos onOpenSpot
                    MessagesList(
                        vm: vm,
                        chat: chat,
                        actorId: actorId,
                        searchText: searchText,
                        searchResults: $searchResults,
                        currentResultIndex: $currentResultIndex,
                        onOpenSpot: { id in
                            // 1) Intenta abrir desde memoria (SpotsViewModel ya poblado)
                            if let sp = spotsVM.spots.first(where: { $0.id == id }) {
                                print("✅ onOpenSpot -> en memoria \(id) → abrir sheet")
                                spotsVM.syncFavorites(favorites: favoritesVM.favoriteIds)
                                print("🔁 syncFavorites (in-memory open)")
                                sheetSpot = spotsVM.spots.first(where: { $0.id == id }) ?? sp
                                return
                            }
                            print("🟠 onOpenSpot -> \(id) no está en memoria; hidratando…")
                            
                            // 2) Hidrata desde Firestore y abre el sheet al terminar
                            db.collection("spots").document(id).getDocument { snap, err in
                                if let err = err {
                                    print("❌ Firestore error cargando spot \(id): \(err.localizedDescription)")
                                    return
                                }
                                guard let snap = snap, snap.exists else {
                                    print("❌ No existe el doc del spot \(id)")
                                    return
                                }
                                do {
                                    guard snap.exists else {
                                        print("❌ El documento \(id) no existe")
                                        return
                                    }
                                    
                                    let sp: Spot = try snap.data(as: Spot.self)   // ← Spot no opcional
                                    var sp2 = sp
                                    sp2.isFavorite = favoritesVM.favoriteIds.contains(sp.id)
                                    print("❤️ patched favorite for \(sp.id) =", sp2.isFavorite)
                                    
                                    DispatchQueue.main.async {
                                        print("✅ Spot \(id) hidratado → abrir sheet")
                                        // 🔁 SINCRONIZA favoritos en el VM antes de mostrar el detalle
                                        spotsVM.syncFavorites(favorites: favoritesVM.favoriteIds)
                                        print("🔁 syncFavorites (hydrated)")
                                        
                                        // Usa la instancia “viva” del VM si ya está; si no, usa el hidratado parcheado
                                        sheetSpot = spotsVM.spots.first(where: { $0.id == id }) ?? sp2
                                    }
                                } catch {
                                    print("❌ Decoding Spot falló para \(id): \(error.localizedDescription)")
                                }
                            }
                        }
                    )
                    .padding(.top, 6)
                    .environmentObject(vm)
                }
            }
            
            
        }
        // BEGIN REPLACE — fondo con imagen + tinte sutil (SOLO light)
        .background(
            ZStack {
                // Imagen existente como base (igual que antes)
                Rectangle()
                    .fill(ImagePaint(image: Image("ChatBackground"), scale: 0.24)) // ajusta 0.8–1.2
                    .opacity(colorScheme == .dark ? 0.40 : 0.70)
                
                // Tinte encima de la imagen — SOLO en modo claro
                if colorScheme == .light {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color.accentColor.opacity(0.20), // puedes bajar a 0.06
                                    Color.accentColor.opacity(0.00)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .blendMode(.multiply) // sutil, mantiene textura de la imagen
                }
            }
        )
        //.ignoresSafeArea() // opcional si quieres cubrir hasta los bordes
        // END REPLACE — fondo con imagen + tinte sutil (SOLO light)
        
        //.ignoresSafeArea()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    markReadLocallyAndDismiss()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.backward")
                        Text(backLabel)
                    }
                }
                .tint(.blue)
            }
            
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(chat.displayName ?? "Chat")
                        .font(.headline)
                        .lineLimit(1)
                        .onTapGesture {
                            if chat.participants.count > 2 { showGroupSheet = true }
                            else { showProfileSheet = true }
                        }
                    
                    if chat.participants.count > 2 {
                        Text("\(chat.participants.count) miembros")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .onTapGesture { showGroupSheet = true }
                    } else {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(userStatus == "en línea" ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                                .onTapGesture { showProfileSheet = true }
                            Text(userStatus)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .onTapGesture { showProfileSheet = true }
                        }
                    }
                }
            }
            
            
            
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation { isSearching.toggle() }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    
                    avatarView(for: chat)
                        .padding(.trailing, 4)
                        .onTapGesture {
                            if chat.participants.count > 2 { showGroupSheet = true }
                            else { showProfileSheet = true }
                        }
                }
            }
            
        }
        .onTapGesture { UIApplication.shared.endEditing(true) }
        .onAppear {
            ensureImageCacheDirExists()   // ✅ por si entramos directo al detalle
            vm.start()
            Task {
                await loadUserStatus()
                await preloadAvatar()
                // Estado de mute por chat (grupos)
                isGroupMuted = await ChatPrefsService.shared.getMute(chatId: chat.id)
                // ✅ Resolver nombres/avatares de miembros para la sheet (sin UIDs en UI)
                await resolveGroupMembers()
                if chat.participants.count > 2 {
                    let vm = ChatsViewModel.shared
                    for uid in chat.participants {
                        if let url = vm.profileImages[uid] {
                            MediaCache.shared.prefetch(urlString: url)
                        }
                    }
                }
                
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { isReady = true }
        }
        
        
        .onDisappear {
            statusListener?.remove()
            if let uid = Auth.auth().currentUser?.uid {
                let lastMsgAt = vm.messages.last?.createdAt ?? Date()
                let bump = lastMsgAt.addingTimeInterval(10)
                
                // Mantén el override local (idéntico a 1:1)
                ChatsViewModel.shared.applyLocalRead(chatId: chat.id, uid: uid, at: bump)
                
                // NEW: deja handoff para que la Home lo consuma en el primer frame (solo grupos)
                if chat.participants.count > 2 {
                    UserDefaults.standard.set(
                        ["chatId": chat.id, "overrideAt": bump.timeIntervalSince1970],
                        forKey: "Chats.justReadOverride.v1"
                    )
                }
            }
            Task {
                if let uid = Auth.auth().currentUser?.uid {
                    await vm.markAsRead(for: uid)
                    ChatsViewModel.shared.forceUpdate(chatId: chat.id, uid: uid)
                }
            }
            markChatRead(chat.id)
        }
        
        
        .onChange(of: scenePhase) { phase in
            if phase == .inactive || phase == .background {
                // Igual que en onDisappear, dispara la escritura que lanza el trigger del servidor
                markChatRead(chat.id)
            }
        }
        
        .sheet(isPresented: $showProfileSheet) {
            ProfileSheetView(displayName: chat.displayName, chat: chat)
        }
        
        .sheet(isPresented: $showGroupSheet) {
            GroupMembersSheet(
                chatId: chat.id,
                currentUserId: Auth.auth().currentUser?.uid ?? "",
                members: groupMembers,             // ✅ nombres/avatares reales
                initialMute: isGroupMuted,
                onAdd: {
                    // El picker ya lo presenta el propio GroupMembersSheet;
                    // aquí, si quieres, solo forzamos un refresh externo:
                    Task { await resolveGroupMembers() }
                },
                onRemove: { uid in
                    Task {
                        try? await GroupAPI.shared.removeMember(chatId: chat.id, uid: uid)
                        await resolveGroupMembers()
                    }
                },
                onPromote: { uid in
                    Task {
                        do {
                            let fn = Functions.functions(region: "europe-west1").httpsCallable("grantAdmin")
                            _ = try await fn.call(["chatId": chat.id, "userId": uid])
                            await resolveGroupMembers()
                        } catch {
                            print("❌ grantAdmin:", error.localizedDescription)
                        }
                    }
                },
                onDemote: { uid in
                    Task {
                        do {
                            let fn = Functions.functions(region: "europe-west1").httpsCallable("revokeAdmin")
                            _ = try await fn.call(["chatId": chat.id, "userId": uid])
                            await resolveGroupMembers()
                        } catch {
                            print("❌ revokeAdmin:", error.localizedDescription)
                        }
                    }
                },
                onLeave: {
                    Task {
                        try? await GroupAPI.shared.leaveGroup(chatId: chat.id)
                        await resolveGroupMembers()
                    }
                },
                onToggleMute: { mute in
                    Task { try? await ChatPrefsService.shared.setMute(chatId: chat.id, mute: mute) }
                }
            )
        }
        
        
        
        
        .onReceive(NotificationCenter.default.publisher(for: .userReportedFromProfile)) { _ in
            self.toastMessage = "Reporte enviado"
            self.toastIcon = "exclamationmark.triangle.fill"
            self.showToast = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("Chat.StartEditMessage"))) { note in
            if let id = note.userInfo?["id"] as? String,
               let msg = vm.messages.first(where: { $0.id == id }) {
                vm.startEdit(msg)
                self.input = msg.text
            }
        }
        .onAppear {
            spotsVM.syncFavorites(favorites: favoritesVM.favoriteIds)
            print("🔁 syncFavorites (onAppear)")
        }
        .onReceive(favoritesVM.$favoriteIds) { ids in
            spotsVM.syncFavorites(favorites: ids)
            print("🔁 syncFavorites (onReceive) ->", ids.count, "ids")
        }
        
        .toast(isPresented: $showToast, message: toastMessage, systemImage: toastIcon, duration: 3.0)
        
        .safeAreaInset(edge: .bottom, spacing: 0) {
            composerView
        }
        
        // 👇 El sheet real del detalle de spot
        .sheet(item: $sheetSpot) { spot in
            SpotDetailView(spot: spot)
                .environmentObject(userSession)
                .environmentObject(spotsVM)
                .environmentObject(favoritesVM)
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .ignoresSafeArea()
                .environment(\.fromChat, true)   // 👈 indica al detalle que viene desde el chat
            
        }
    }
    
    
    // MARK: - Composer (safe-area inset)
    @ViewBuilder
    private var composerView: some View {
        VStack(spacing: 6) {
            
            // ✏️ Barra de edición
            if let editing = vm.editTarget {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .frame(width: 3)
                        .foregroundStyle(Color.orange.opacity(0.9))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Editando mensaje")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text(editing.text)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        vm.cancelEdit()
                        self.input = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color.orange.opacity(0.08))
                .cornerRadius(8)
            }
            // 🧩 Barra de reply (si hay objetivo)
            if let quote = vm.replyTarget {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .frame(width: 3)
                        .foregroundStyle(Color.blue.opacity(0.8))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Respondiendo")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text((quote.fileUrl != nil) ? (quote.fileName ?? "Archivo") : quote.text)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button {
                        vm.clearReply()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
            }
            
            HStack(spacing: 8) {
                Button {
                    showPickerDialog = true
                } label: {
                    Image(systemName: "paperclip").font(.title2).foregroundColor(.blue)
                }
                .confirmationDialog("Adjuntar", isPresented: $showPickerDialog) {
                    Button("Foto o Video") {
                        selectedPickerType = .photoVideo
                        showFilePicker = true
                    }
                    Button("Archivo") {
                        selectedPickerType = .document
                        showFilePicker = true
                    }
                    Button("Cancelar", role: .cancel) {}
                }
                .sheet(isPresented: $showFilePicker) {
                    FilePickerController(type: selectedPickerType ?? .photoVideo) { picked in
                        guard let picked else { return }
                        Task { await vm.sendFile(picked: picked) }
                    }
                }
                
                AutoGrowingTextEditor(
                    text: $input,
                    placeholder: "Escribe un mensaje…",
                    minHeight: 36,
                    maxHeight: 140,
                    onSend: { sendMessage(actorId: supportMode ? SUPPORT_BOT_ID : (Auth.auth().currentUser?.uid ?? "")) }
                )
                .autocorrectionDisabled(false)
                .textInputAutocapitalization(.sentences)
                .frame(maxWidth: .infinity)
                .onChange(of: input) { newValue in
                    // Abrir sugerencias cuando haya un '@' al final, con o sin token
                    if newValue.range(of: #"(^|[\s])@([^\s]{0,})$"#, options: .regularExpression) != nil {
                        self.showMentionList = true
                        if let r = newValue.range(of: #"@([^\s]{0,})$"#, options: .regularExpression) {
                            let token = String(newValue[r]).dropFirst()
                            self.mentionQuery = String(token)
                        } else {
                            self.mentionQuery = ""
                        }
                    } else {
                        self.showMentionList = false
                        self.mentionQuery = ""
                    }
                }
                .overlay(alignment: .topLeading) {
                    if showMentionList {
                        let myUid = Auth.auth().currentUser?.uid
                        // Construye la lista base excluyendo al usuario actual
                        let baseItems: [(id: String, name: String)] = groupMembers
                            .filter { $0.id != myUid }
                            .map { ($0.id, $0.displayName) }
                        
                        // Filtrado “contiene” (sin tildes, sin emojis, case-insensitive)
                        let q = norm(mentionQuery)
                        let items: [(id: String, name: String)] = {
                            if q.isEmpty {
                                return baseItems.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                            } else {
                                return baseItems
                                    .filter { norm($0.name).contains(q) }
                                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                            }
                        }()
                        
                        // Altura por fila y caja: 10 visibles mínimo; si hay >10 → scroll
                        let rowHeight: CGFloat = 40
                        let visibleRows = min(max(items.count, 10), 10) // 10 visibles si hay ≥10; si hay menos, se ajusta a los que haya
                        let boxHeight = CGFloat(min(items.count, 10)) * rowHeight
                        
                        VStack(alignment: .leading, spacing: 0) {
                            ScrollView {
                                VStack(spacing: 0) {
                                    ForEach(items, id: \.id) { item in
                                        Button {
                                            // Sustituye el '@...' actual (o '@' a pelo) por @Nombre␣
                                            if let r = input.range(of: #"@([^\s]{0,})$"#, options: .regularExpression) {
                                                input.replaceSubrange(r, with: "@\(item.name) ")
                                            } else {
                                                input.append("@\(item.name) ")
                                            }
                                            showMentionList = false
                                            mentionQuery = ""
                                        } label: {
                                            HStack {
                                                Text(item.name).font(.callout)
                                                Spacer()
                                            }
                                            .frame(height: rowHeight)
                                            .padding(.horizontal, 12)
                                        }
                                        .buttonStyle(.plain)
                                        Divider()
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: 360)
                        .frame(height: boxHeight)              // muestra hasta 10 filas; si hay más, scroll
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(radius: 8)
                        .zIndex(1000)
                        // Mostrar HACIA ARRIBA del compose:
                        .offset(y: -(boxHeight + 8))
                        .padding(.leading, 4)
                        .padding(.bottom, 4)
                        .allowsHitTesting(true)
                    }
                }
                
                
                
                
                Button { sendMessage(actorId: supportMode ? SUPPORT_BOT_ID : (Auth.auth().currentUser?.uid ?? "")) } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                        .foregroundColor(input.trimmingCharacters(in: .whitespaces).isEmpty ? .gray : .blue)
                }
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Estados de picker
    @State private var showPickerDialog = false
    @State private var showFilePicker = false
    @State private var selectedPickerType: FileType? = nil
    
    // MARK: - Envío
    private func sendMessage(actorId: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        Task {
            switch ModerationService.evaluate(trimmed) {
            case .allow: break
            case .warn(let reason):
                await MainActor.run {
                    toastMessage = "⚠️ Mensaje dudoso: \(reason)"
                    toastIcon = "exclamationmark.circle.fill"
                    showToast = true
                }
            case .block(let reason):
                await MainActor.run {
                    toastMessage = "⛔️ Bloqueado: \(reason)"
                    toastIcon = "nosign"
                    showToast = true
                }
                return
            }
            
            if supportMode {
                await MainActor.run { self.input = "" }
                await vm.sendSupport(text: trimmed)
            } else if vm.editTarget != nil {
                let m = resolveMentions(in: trimmed)
                await vm.updateMessage(text: trimmed, mentions: m)
                await MainActor.run { self.input = "" }
            } else {
                let m = resolveMentions(in: trimmed)
                await vm.send(text: trimmed, mentions: m)
                await MainActor.run { self.input = "" }
            }
            
            
        }
    }
    
    // MARK: - Cerrar aplicando read local
    private func markReadLocallyAndDismiss() {
        guard let uid = Auth.auth().currentUser?.uid else { dismiss(); return }
        
        let listUpdatedAt = ChatsViewModel.shared.chats.first(where: { $0.id == chat.id })?.updatedAt ?? .distantPast
        let lastMsgAt = vm.messages.last?.createdAt ?? .distantPast
        let base = max(listUpdatedAt, lastMsgAt, Date())
        let overrideAt = base.addingTimeInterval(10)
        
        // Igual que 1:1: override local inmediato
        ChatsViewModel.shared.applyLocalRead(chatId: chat.id, uid: uid, at: overrideAt)
        
        // NEW: handoff solo si es grupo
        if chat.participants.count > 2 {
            UserDefaults.standard.set(
                ["chatId": chat.id, "overrideAt": overrideAt.timeIntervalSince1970],
                forKey: "Chats.justReadOverride.v1"
            )
        }
        
        Task { await vm.markAsRead(for: uid) }
        dismiss()
    }
    
    
    private func handlePickedFile(_ picked: PickedFile?) {
        guard let picked else { return }
        Task { await vm.sendFile(picked: picked) }
    }
    
    private func resolveOtherUserId() -> String? {
        let myUid = Auth.auth().currentUser?.uid
        var candidates = chat.participants
        if supportMode {
            candidates.removeAll(where: { $0 == SUPPORT_BOT_ID || $0 == myUid })
            return candidates.first
        } else {
            return chat.participants.first(where: { $0 != myUid })
        }
    }
    
    // Resolver menciones @DisplayName -> [uid]
    private func resolveMentions(in text: String) -> [String] {
        guard text.contains("@") else { return [] }
        // Índice por nombre normalizado
        var index: [String: String] = [:] // normName -> uid
        for m in groupMembers {
            let norm = m.displayName
                .lowercased()
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            index[norm] = m.id
        }
        // Regex simple para tokens @xxxxx
        let pattern = #"@([A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9_]{2,})"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var uids: [String] = []
        uids.reserveCapacity(4)
        for m in matches {
            guard m.numberOfRanges >= 2 else { continue }
            let token = ns.substring(with: m.range(at: 1))
            let norm = token
                .lowercased()
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            if let uid = index[norm] {
                uids.append(uid)
            } else if let uid = index.keys.first(where: { $0.hasPrefix(norm) }).flatMap({ index[$0] }) {
                uids.append(uid)
            }
            if uids.count >= 10 { break }
        }
        // únicos
        var seen = Set<String>(); var res: [String] = []
        for u in uids { if seen.insert(u).inserted { res.append(u) } }
        return res
    }
    
    // Normaliza cadenas: minúsculas, sin tildes, sin símbolos/emoji, solo alfanumérico
    // Normaliza: minúsculas, sin tildes, sin emojis/símbolos → solo alfanumérico
    private func norm(_ s: String) -> String {
        let lowered = s.lowercased()
        let folded = lowered.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
                                     locale: .current)
        let compat = (folded as NSString).precomposedStringWithCompatibilityMapping
        let scalars = compat.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }
        return String(String.UnicodeScalarView(scalars))
    }
    
    
    
    // Sugerencias de menciones con ranking: prefijo del nombre > prefijo de palabra > contiene
    private func mentionSuggestions(for query: String) -> [(id: String, name: String, rank: Int)] {
        let q = norm(query)
        guard !q.isEmpty else { return [] }
        
        let raw: [(String, String)] = groupMembers.map { ($0.id, $0.displayName) }
        
        let ranked = raw.map { (id, name) -> (id: String, name: String, rank: Int) in
            let n = norm(name)
            let wordTokens = name
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .map(norm)
                .filter { !$0.isEmpty }
            
            var rank = 99
            if n.hasPrefix(q) {
                rank = 0                  // prefijo del nombre completo
            } else if wordTokens.contains(where: { $0.hasPrefix(q) }) {
                rank = 1                  // prefijo de palabra
            } else if n.contains(q) {
                rank = 2                  // contiene
            }
            return (id, name, rank)
        }
            .filter { $0.rank < 99 }
            .sorted {
                if $0.rank != $1.rank { return $0.rank < $1.rank }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
        
        return Array(ranked.prefix(8))
    }
    
    
    
    private func loadUserStatus() async {
        guard let otherId = resolveOtherUserId() else { return }
        statusListener = db.collection("users").document(otherId)
            .addSnapshotListener { snap, _ in
                guard let data = snap?.data() else {
                    self.userStatus = "desconocido"
                    return
                }
                self.userStatus = UserStatusFormatter.format(from: data)
            }
    }
    
    private func preloadAvatar() async {
        guard let otherId = resolveOtherUserId() else { return }
        if ChatsViewModel.shared.profileImages[otherId] == nil {
            if let urlStr = await UserService.shared.profileImageUrl(for: otherId) {
                await MainActor.run {
                    ChatsViewModel.shared.profileImages[otherId] = urlStr
                }
            }
        }
    }
    
    private func avatarView(for chat: Chat) -> some View {
        if chat.participants.count > 2 {
            if let urlStr = ChatsViewModel.shared.groupPhotos[chat.id] {
                return AnyView(
                    CachedAvatarImageView(
                        urlString: urlStr,
                        initials: chat.displayName,
                        size: 36
                    )
                    .overlay(avatarBorder.frame(width: 36, height: 36))
                )
            } else {
                return AnyView(
                    placeholderAvatar(initials: chat.displayName)
                        .overlay(avatarBorder.frame(width: 36, height: 36))
                )
            }
        } else {
            if let otherId = resolveOtherUserId(),
               let urlStr = ChatsViewModel.shared.profileImages[otherId] {
                return AnyView(
                    CachedAvatarImageView(
                        urlString: urlStr,
                        initials: chat.displayName,
                        size: 36
                    )
                    .overlay(avatarBorder.frame(width: 36, height: 36))
                )
            } else {
                return AnyView(
                    placeholderAvatar(initials: chat.displayName)
                        .overlay(avatarBorder.frame(width: 36, height: 36))
                )
            }
        }
    }
    
    
    private func placeholderAvatar(initials: String?) -> some View {
        let letters = String((initials ?? "U").prefix(2)).uppercased()
        return ZStack {
            Circle().fill(Color.blue.opacity(0.2)).frame(width: 36, height: 36)
            Text(letters).font(.caption.bold()).foregroundColor(.blue)
        }
    }
    
    private var avatarBorder: some View {
        ZStack {
            Circle().stroke(Color.white, lineWidth: 6)
            Circle()
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.0, green: 0.85, blue: 0.9),
                            Color(red: 0.2, green: 0.5, blue: 1.0)
                        ]),
                        center: .center
                    ),
                    lineWidth: 3
                )
                .padding(-2)
        }
    }
    
    private func recalcSearchResults() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else {
            searchResults = []
            currentResultIndex = 0
            return
        }
        searchResults = vm.messages
            .filter {
                let t = $0.text.lowercased()
                let n = ($0.fileName ?? "").lowercased()
                return (!t.isEmpty && t.contains(q)) || (!n.isEmpty && n.contains(q))
            }
            .map { $0.id }
        currentResultIndex = 0
    }
    
    private func markChatRead(_ chatId: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Firestore.firestore()
            .collection("users").document(uid)
            .collection("chatsReads").document(chatId)
            .setData(["lastReadAt": FieldValue.serverTimestamp()], merge: true)
    }
    // MARK: - Resolver miembros (nombres/avatares) sin mostrar UID
    private func resolveGroupMembers() async {
        guard chat.participants.count > 0 else {
            await MainActor.run { self.groupMembers = [] }
            return
        }
        
        let ids = chat.participants
        var rows: [MemberRow] = []
        let col = Firestore.firestore().collection("users")
        
        // Sencillo y seguro: fetch por documento (grupos pequeños/medios)
        for uid in ids {
            do {
                let snap = try await col.document(uid).getDocument()
                let data = snap.data() ?? [:]
                let name =
                (data["displayName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (data["username"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (data["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (data["fullName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? "Usuario"
                let photo =
                (data["profileImageUrl"] as? String)
                ?? (data["photoURL"] as? String)
                ?? (data["avatarURL"] as? String)
                ?? (data["profilePhotoURL"] as? String)
                rows.append(MemberRow(id: uid, displayName: name, photoURL: photo, role: "member"))
            } catch {
                rows.append(MemberRow(id: uid, displayName: "Usuario", photoURL: nil, role: "member"))
            }
        }
        
        await MainActor.run { self.groupMembers = rows }
    }
    
}

// ✅ Helper local a este archivo: asegura que la carpeta de caché exista
private func ensureImageCacheDirExists() {
    let fm = FileManager.default
    if let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
        let dir = base.appendingPathComponent("ImageCache", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}


// MARK: - PreferenceKeys
private struct MessageRowHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct TopVisibleKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - Lista de mensajes
struct MessagesList: View {
    @ObservedObject var vm: ChatViewModel
    let chat: Chat
    let actorId: String
    
    // Search bindings from ChatDetailView
    let searchText: String
    @Binding var searchResults: [String]
    @Binding var currentResultIndex: Int
    
    // 👉 Callback para abrir un spot (lo define ChatDetailView)
    var onOpenSpot: ((String) -> Void)? = nil
    
    // Scroll/state
    @State private var didReachBottom = false
    @State private var showScrollButton = false
    @State private var lastMessageId: String? = nil
    @State private var requestedScrollId: String? = nil
    @State private var topVisibleId: String? = nil
    @State private var measuredHeights: [String: CGFloat] = [:]
    
    private let bottomAnchorId = "BOTTOM_ANCHOR"
    
    var body: some View {
        let uid = Auth.auth().currentUser?.uid ?? ""
        let lastReadDate = chat.lastRead?[uid] ?? Date.distantPast
        let otherUserUnread = vm.messages.filter { $0.senderId != uid && $0.createdAt > lastReadDate }
        let firstUnreadId = otherUserUnread.first?.id
        let unreadCount = otherUserUnread.count
        
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(vm.messages.enumerated()), id: \.element.id) { index, msg in
                        if index == 0 || !Calendar.current.isDate(msg.createdAt, inSameDayAs: vm.messages[index - 1].createdAt) {
                            DateSeparatorView(date: msg.createdAt)
                        }
                        
                        if msg.id == firstUnreadId {
                            UnreadSeparatorView(count: unreadCount)
                        }
                        
                        // ⬇️ cálculo de bloque consecutivo (mismo remitente y ≤5 min)
                        let prev = (index > 0) ? vm.messages[index - 1] : nil
                        let thr: TimeInterval = 5 * 60
                        let sameSender = (prev?.senderId == msg.senderId)
                        let closeInTime = (prev != nil) && (abs(prev!.createdAt.timeIntervalSince(msg.createdAt)) <= thr)
                        let isSameBlock = sameSender && closeInTime
                        
                        MessageRow(
                            msg: msg,
                            isMine: msg.senderId == actorId,
                            highlight: searchText,
                            isHighlighted: (searchResults.indices.contains(currentResultIndex) && searchResults[currentResultIndex] == msg.id),
                            showSenderHeader: (chat.participants.count > 2),
                            groupDisplayName: (chat.participants.count > 2 ? chat.displayName : nil),
                            onOpenSpot: onOpenSpot   // ⬅️ propagamos el callback
                        )
                        .padding(.top, isSameBlock ? -9 : 0)
                        .id(msg.id)
                        .background(
                            GeometryReader { geo in
                                Color.clear
                                    .preference(
                                        key: TopVisibleKey.self,
                                        value: [msg.id: geo.frame(in: .named("messagesScroll")).minY]
                                    )
                            }
                        )
                    }
                    
                    BottomAnchorView()
                        .id(bottomAnchorId)
                        .onAppear { didReachBottom = true; showScrollButton = false }
                        .onDisappear { didReachBottom = false; showScrollButton = true }
                }
                .padding(.horizontal)
            }
            .scrollDismissesKeyboard(.interactively)
            .coordinateSpace(name: "messagesScroll")
            .onReceive(NotificationCenter.default.publisher(for: .init("Chat.ScrollToMessage"))) { note in
                if let id = note.object as? String { requestedScrollId = id }
            }
            .onChange(of: vm.messages) { newMessages in
                if let last = newMessages.last, last.id != lastMessageId {
                    lastMessageId = last.id
                    if last.senderId == actorId {
                        scrollToBottom(proxy, animated: false)
                    } else if didReachBottom {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            scrollToBottom(proxy, animated: true)
                        }
                    }
                } else if didReachBottom {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        scrollToBottom(proxy, animated: true)
                    }
                }
                let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if !q.isEmpty {
                    let currentId = (searchResults.indices.contains(currentResultIndex) ? searchResults[currentResultIndex] : nil)
                    searchResults = vm.messages.compactMap { m in
                        let t = m.text.lowercased()
                        let n = (m.fileName ?? "").lowercased()
                        if (!t.isEmpty && t.contains(q)) || (!n.isEmpty && n.contains(q)) { return m.id }
                        return nil
                    }
                    if let currentId, let newIdx = searchResults.firstIndex(of: currentId) {
                        currentResultIndex = newIdx
                    } else if !searchResults.isEmpty {
                        currentResultIndex = min(currentResultIndex, searchResults.count - 1)
                    } else {
                        currentResultIndex = 0
                    }
                }
            }
            .onChange(of: vm.messages.map { m in
                let p = m.uploadProgress.map { String(format: "%.3f", $0) } ?? ""
                return (m.id + "|" + (m.fileUrl ?? "") + "|" + (m.thumbnailUrl ?? "") + "|" + p)
            }.joined(separator: "§")) { _ in
                guard didReachBottom else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { scrollToBottom(proxy, animated: true) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { scrollToBottom(proxy, animated: true) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) { scrollToBottom(proxy, animated: true) }
            }
            .onPreferenceChange(MessageRowHeightKey.self) { map in
                guard let lastId = vm.messages.last?.id,
                      let newH = map[lastId] else { return }
                let prevH = measuredHeights[lastId] ?? 0
                measuredHeights[lastId] = newH
                if abs(newH - prevH) < 0.5 { return }
                let wasAtBottomSaved = UserDefaults.standard.bool(forKey: "Chat.wasAtBottom.v1.\(chat.id)")
                if didReachBottom || wasAtBottomSaved {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { scrollToBottom(proxy, animated: false) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { scrollToBottom(proxy, animated: true) }
                }
            }
            .onChange(of: requestedScrollId) { id in
                guard let id else { return }
                proxy.scrollTo(id, anchor: .center)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo(id, anchor: .center) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
                requestedScrollId = nil
            }
            .onChange(of: searchText) { _ in
                let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if q.isEmpty {
                    searchResults = []
                    currentResultIndex = 0
                } else {
                    searchResults = vm.messages.compactMap { m in
                        let t = m.text.lowercased()
                        let n = (m.fileName ?? "").lowercased()
                        if (!t.isEmpty && t.contains(q)) || (!n.isEmpty && n.contains(q)) { return m.id }
                        return nil
                    }
                    if !searchResults.isEmpty {
                        currentResultIndex = 0
                        requestedScrollId = searchResults[0]
                    }
                }
            }
            .onChange(of: currentResultIndex) { _ in
                if searchResults.indices.contains(currentResultIndex) {
                    let id = searchResults[currentResultIndex]
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
            .onPreferenceChange(TopVisibleKey.self) { map in
                let sorted = map.sorted(by: { $0.value < $1.value })
                if let vis = sorted.first(where: { $0.value >= 0 })?.key ?? sorted.last?.key {
                    topVisibleId = vis
                }
            }
            .onAppear {
                let wasAtBottom = UserDefaults.standard.bool(forKey: "Chat.wasAtBottom.v1.\(chat.id)")
                let savedTopId = UserDefaults.standard.string(forKey: "Chat.topAnchor.v1.\(chat.id)")
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if unreadCount > 0 {
                        if let last = vm.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    } else if wasAtBottom {
                        scrollToBottom(proxy, animated: false)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { scrollToBottom(proxy, animated: false) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { scrollToBottom(proxy, animated: true) }
                    } else if let anchor = savedTopId,
                              vm.messages.contains(where: { $0.id == anchor }) {
                        proxy.scrollTo(anchor, anchor: .top)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { proxy.scrollTo(anchor, anchor: .top) }
                    }
                    lastMessageId = vm.messages.last?.id
                }
            }
            .onDisappear {
                UserDefaults.standard.set(didReachBottom, forKey: "Chat.wasAtBottom.v1.\(chat.id)")
                if let top = topVisibleId {
                    UserDefaults.standard.set(top, forKey: "Chat.topAnchor.v1.\(chat.id)")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if showScrollButton {
                    Button { scrollToBottom(proxy, animated: true) } label: {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.title)
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.blue).frame(width: 48, height: 48))
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 80)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
                if didReachBottom {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        scrollToBottom(proxy, animated: true)
                    }
                }
            }
        }
    }
    
    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo(bottomAnchorId, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(bottomAnchorId, anchor: .bottom)
        }
    }
}

// MARK: - MessageRow
struct MessageRow: View {
    let msg: Message
    let isMine: Bool
    let highlight: String
    let isHighlighted: Bool
    var showSenderHeader: Bool = false
    let groupDisplayName: String?
    @EnvironmentObject var vm: ChatViewModel
    
    // Paleta “fluo” y color estable por usuario (mismo color siempre para el mismo uid)
    private let fluoPalette: [Color] = [
        Color(red: 1.00, green: 0.48, blue: 0.00), // naranja fluo
        Color(red: 0.22, green: 1.00, blue: 0.08), // verde fluo
        Color(red: 0.00, green: 0.90, blue: 1.00)  // azul fluo
    ]
    
    private func nameColor(for uid: String) -> Color {
        var h = 5381
        for u in uid.unicodeScalars { h = ((h << 5) &+ h) &+ Int(u.value) }
        let idx = abs(h) % fluoPalette.count
        return fluoPalette[idx]
    }
    
    
    // Propagación del callback hacia la burbuja
    var onOpenSpot: ((String) -> Void)? = nil
    
    var body: some View {
        // Cache de nombres y avatares (ya existente en la VM compartida)
        let chatsVM = ChatsViewModel.shared
        let senderName = chatsVM.usernames[msg.senderId] ?? "Usuario"
        let senderAvatarURL = chatsVM.profileImages[msg.senderId]
        let isGroup = showSenderHeader  // true si participants.count > 2 en el padre
        
        // BEGIN REPLACE — Mensaje (grupos + 1:1) con agrupación estilo Telegram
        HStack(spacing: 8) {
            // Cálculo del rol dentro del bloque (misma persona y ≤5 min)
            let all = vm.messages
            let idx = all.firstIndex(where: { $0.id == msg.id })
            let role: GroupRole = {
                guard let i = idx else { return .solo }
                let cur = all[i]
                let thr: TimeInterval = 5 * 60
                let prev: Message? = (i > 0) ? all[i - 1] : nil
                let next: Message? = (i + 1 < all.count) ? all[i + 1] : nil
                let samePrev = (prev?.senderId == cur.senderId) && (abs(prev!.createdAt.timeIntervalSince(cur.createdAt)) <= thr)
                let sameNext = (next?.senderId == cur.senderId) && (abs(next!.createdAt.timeIntervalSince(cur.createdAt)) <= thr)
                switch (samePrev, sameNext) {
                case (false, false): return .solo
                case (false, true):  return .top
                case (true, false):  return .bottom
                case (true, true):   return .middle
                }
            }()
            
            if isMine {
                // Salientes: a la derecha, sin avatar ni nombre
                Spacer(minLength: 0)
                if (msg.fileUrl != nil) || (msg.fileType != nil) || (msg.fileName != nil) || (msg.uploadProgress ?? 0) > 0 {
                    FileMessageBubble(
                        msg: msg,
                        isMine: true,
                        groupRole: role,
                        isGroup: isGroup,
                        senderName: nil
                    )
                } else {
                MessageBubble(
                    msg: msg,
                    isMine: true,
                    groupRole: role,
                    isGroup: isGroup,
                    senderName: nil,
                    groupDisplayName: groupDisplayName,
                    highlight: highlight,
                    isHighlighted: isHighlighted,
                    onOpenSpot: onOpenSpot
                )
                }
                
            } else if isGroup {
                // Entrantes en grupo: avatar sólo en .bottom /.solo; nombre sólo en .top /.solo
                let showAvatar = (role == .bottom || role == .solo)
                
                if showAvatar {
                    CachedAvatarImageView(
                        urlString: senderAvatarURL,
                        initials: senderName,
                        size: 36
                    )
                } else {
                    Color.clear.frame(width: 36, height: 36)
                }
                
                // BEGIN REPLACE — VStack de mensaje entrante en grupo (nombre dentro del bubble)
                VStack(alignment: .leading, spacing: 4) {
                    let inlineSenderName: String? = ((role == .top || role == .solo) ? senderName : nil)
                    
                    if (msg.fileUrl != nil) || (msg.fileType != nil) || (msg.fileName != nil) || (msg.uploadProgress ?? 0) > 0 {
                        FileMessageBubble(
                            msg: msg,
                            isMine: false,
                            groupRole: role,
                            isGroup: true,
                            senderName: inlineSenderName
                        )
                    } else {
                    MessageBubble(
                        msg: msg,
                        isMine: false,
                        groupRole: role,
                        isGroup: true,
                        senderName: inlineSenderName,   // 👈 nombre viaja dentro del bubble
                        groupDisplayName: groupDisplayName,
                        highlight: highlight,
                        isHighlighted: isHighlighted,
                        onOpenSpot: onOpenSpot
                    )
                    }
                }
                // END REPLACE — VStack de mensaje entrante en grupo (nombre dentro del bubble)
                
                
                Spacer(minLength: 0)
            } else {
                // 1:1 entrante (sin avatar ni nombre)
                if (msg.fileUrl != nil) || (msg.fileType != nil) || (msg.fileName != nil) || (msg.uploadProgress ?? 0) > 0 {
                    FileMessageBubble(
                        msg: msg,
                        isMine: false,
                        groupRole: role,
                        isGroup: false,
                        senderName: nil
                    )
                } else {
                MessageBubble(
                    msg: msg,
                    isMine: false,
                    groupRole: role,
                    isGroup: false,
                    senderName: nil,
                    groupDisplayName: groupDisplayName,
                    highlight: highlight,
                    isHighlighted: isHighlighted,
                    onOpenSpot: onOpenSpot
                )
                }
                
                Spacer(minLength: 0)
            }
        }
        // END REPLACE — Mensaje (grupos + 1:1)
        
        .onAppear {
            // Prefetch del avatar del remitente para evitar “flash”
            if let url = senderAvatarURL {
                MediaCache.shared.prefetch(urlString: url)
            }
        }
    }
    
    
}

// MARK: - MessageBubble
struct MessageBubble: View {
    let msg: Message
    let isMine: Bool
    let groupRole: GroupRole
    let isGroup: Bool
    let senderName: String?
    let groupDisplayName: String?
    let highlight: String
    let isHighlighted: Bool
    @EnvironmentObject var vm: ChatViewModel
    
    // BEGIN REPLACE — colores de burbuja estilo Telegram (100%)
    @Environment(\.colorScheme) private var colorScheme
    
    
    
    // BEGIN INSERT — paleta fija local a MessageBubble + color de texto
    private enum TG {
        // Fondos
        static let incomingLight = Color.white                                 // #FFFFFF
        static let incomingDark  = Color(red: 0.17, green: 0.19, blue: 0.21)   // ≈ #2B3036
        static let outgoingLight = Color(red: 0.80, green: 0.90, blue: 1.00)
        static let outgoingDark  = Color(red: 0.18, green: 0.46, blue: 0.77)   // ≈ #2E76C5 (azul original)  // ≈ #475733 (tono oliva en dark)
        // Texto
        static let textLight     = Color.black                                 // #000000
        static let textDark      = Color.white                                 // #FFFFFF
        // Hora/✓✓
        static let timeGrey      = Color(red: 0.56, green: 0.56, blue: 0.60)   // #8E8E93
    }
    
    private var bubbleTextColor: Color {
        colorScheme == .dark ? TG.textDark : TG.textLight
    }
    // END INSERT — paleta fija local a MessageBubble + color de texto
    
    
    // BEGIN REPLACE — fondo con colores fijos
    private var bubbleBackground: Color {
        if isMine {
            return colorScheme == .dark ? TG.outgoingDark : TG.outgoingLight
        } else {
            return colorScheme == .dark ? TG.incomingDark : TG.incomingLight
        }
    }
    
    private let senderPalette: [Color] = [
        Color(#colorLiteral(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)),     // #007AFF
        Color(#colorLiteral(red: 1.0, green: 0.231, blue: 0.188, alpha: 1.0)),   // #FF3B30
        Color(#colorLiteral(red: 0.204, green: 0.78, blue: 0.349, alpha: 1.0)),  // #34C759
        Color(#colorLiteral(red: 1.0, green: 0.584, blue: 0.0, alpha: 1.0)),     // #FF9500
        Color(#colorLiteral(red: 0.345, green: 0.337, blue: 0.839, alpha: 1.0)), // #5856D6
        Color(#colorLiteral(red: 1.0, green: 0.176, blue: 0.333, alpha: 1.0)),   // #FF2D55
        Color(#colorLiteral(red: 0.686, green: 0.322, blue: 0.871, alpha: 1.0)), // #AF52DE
        Color(#colorLiteral(red: 0.353, green: 0.784, blue: 0.98, alpha: 1.0))   // #5AC8FA
    ]
    
    private func nameColorFor(_ uid: String) -> Color {
        var h: UInt64 = 0
        for u in uid.unicodeScalars { h = ((h << 5) &+ h) &+ UInt64(u.value) }
        let idx = Int(h % UInt64(senderPalette.count))
        return senderPalette[idx]
    }
    // END INSERT — palette + helper
    
    @State private var showDeleteAlert = false
    @State private var showForwardPicker = false
    
    // Callback que sube a ChatDetailView
    var onOpenSpot: ((String) -> Void)? = nil
    
    private var bubbleMaxWidth: CGFloat {
        min(340, UIScreen.main.bounds.width * 0.75)
    }
    
    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: msg.createdAt)
    }
    
    
    
    var body: some View {
        // BEGIN REPLACE — BUBBLE ÚNICO (contenido + fondo + hora DENTRO)
        VStack(alignment: .leading, spacing: 6) {
            if let name = senderName, !isMine, isGroup {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(name)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(nameColorFor(msg.senderId))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    // ⛔️ Sin Spacer aquí: el mínimo del bubble pasa a ser el ancho del nombre
                }
                .padding(.bottom, 2)
            }
            
            // Reply inline (tarjeta dentro del mismo bubble)
            if let rid = msg.replyToMessageId,
               let ref = vm.messages.first(where: { $0.id == rid }) {
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .foregroundStyle(nameColorFor(ref.senderId).opacity(0.95))
                        .frame(width: 3)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ChatsViewModel.shared.usernames[ref.senderId] ?? "Usuario")
                            .font(.caption2.weight(.semibold))
                            .foregroundColor(nameColorFor(ref.senderId))
                            .lineLimit(1)
                        
                        Text((ref.fileUrl != nil) ? (ref.fileName ?? "Archivo") : ref.text)
                            .font(.caption2)
                            .foregroundColor(bubbleTextColor.opacity(0.72))
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(colorScheme == .dark ? Color(UIColor.systemFill)
                            : nameColorFor(ref.senderId).opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onTapGesture {
                    NotificationCenter.default.post(name: .init("Chat.ScrollToMessage"), object: rid)
                }
            }
            
            // Mensaje de texto (si no es un enlace puro)
            if linkIfOnly(msg.text) == nil {
                highlightedText(msg.text, query: highlight)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Enlaces internos spots://…
            if let internalURL = firstSpotsDeepLink(in: msg.text) {
                let host = internalURL.host?.lowercased()
                if host == "spot" {
                    SpotsLinkCard(spotURL: internalURL, onOpen: { id in onOpenSpot?(id) })
                        .padding(.horizontal, 2)
                } else if host == "coord" {
                    SpotsCoordChip(url: internalURL).padding(.horizontal, 2)
                } else if host == "invite" {
                    SpotsInviteChip(url: internalURL, groupName: groupDisplayName).padding(.horizontal, 2)
                }
            }
            
            // Previews http/https
            if let url = firstHTTPURL(in: msg.text) {
                LinkPreviewView(url: url)
                    .task {
                        URLPreviewPrefetcher.shared.prefetchIfNeeded(url)
                    }
            }
            
        }
        // ——— estilo del BUBBLE completo ———
        .foregroundColor(bubbleTextColor)                             // texto negro/blanco fijo
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        // ⬆️ dejamos padding vertical normal…
        .padding(.bottom, 16)                                        // ⬅️ más hueco para la hora/✓✓
        .background(bubbleBackground)

        // ⬇️ Hora superpuesta sin alterar el ancho del bubble
        .overlay(alignment: .bottomTrailing) {
            HStack(spacing: 6) {
                Text(timeString)
                if msg.editedAt != nil { Text("· editado") }
                // (ticks eliminados)
            }
            .font(.caption2)
            .foregroundColor(
                (colorScheme == .dark && isMine)
                ? Color.white.opacity(0.9)   // ⬅️ más claro en salientes + dark
                : TG.timeGrey                // ⬅️ resto igual que antes
            )
            .padding(.trailing, isMine ? 8 : 12)
            .padding(.bottom, 6)
        }
        .clipShape(GroupedBubbleShape(isMine: isMine, role: groupRole, radius: 20))

        // límite de ancho + no estirar
        .frame(maxWidth: bubbleMaxWidth, alignment: isMine ? .trailing : .leading)
        .fixedSize(horizontal: false, vertical: true)
        // END REPLACE — BUBBLE ÚNICO
        
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .contextMenu {
            // Editar (solo texto propio; evita archivos)
            if isMine && msg.fileUrl == nil && !msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    NotificationCenter.default.post(
                        name: .init("Chat.StartEditMessage"),
                        object: nil,
                        userInfo: ["id": msg.id]
                    )
                } label: {
                    Label("Editar", systemImage: "pencil")
                }
            }

            // Responder (todos)
            Button { vm.setReply(to: msg) } label: {
                Label("Responder", systemImage: "arrowshape.turn.up.left")
            }

            // Reenviar (todos)
            Button { showForwardPicker = true } label: {
                Label("Reenviar…", systemImage: "arrowshape.turn.up.right")
            }

            // Copiar (si hay texto)
            if !msg.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button { UIPasteboard.general.string = msg.text } label: {
                    Label("Copiar", systemImage: "doc.on.doc")
                }
            }

            // 🗑️ Borrar (solo mis mensajes; texto o archivo da igual)
            if isMine {
                Button(role: .destructive) {
                    showDeleteAlert = true
                } label: {
                    Label("Borrar", systemImage: "trash")
                }
            }
        }
        
        
        .alert("¿Borrar mensaje?", isPresented: $showDeleteAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Borrar", role: .destructive) {
                Task { await vm.deleteMessage(msg) }
            }
        }
        .sheet(isPresented: $showForwardPicker) {
            ForwardPickerSheet(currentChatId: msg.chatId) { targetId in
                Task { await forward(msg, to: targetId) }
            }
        }
    }
    
    private func forward(_ message: Message, to targetChatId: String) async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let db = Firestore.firestore()
        let msgRef = db.collection("chats").document(targetChatId).collection("messages").document()
        let now = Date()
        
        var data: [String: Any] = [
            "id": msgRef.documentID,
            "senderId": uid,
            "createdAtClient": Timestamp(date: now),
            "createdAt": FieldValue.serverTimestamp()
        ]
        
        if !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            data["text"] = message.text
        }
        
        if let fileUrl = message.fileUrl {
            data["fileUrl"] = fileUrl
            if let fileName = message.fileName { data["fileName"] = fileName }
            if let fileSize = message.fileSize { data["fileSize"] = fileSize }
            if let fileType = message.fileType { data["fileType"] = fileType }
            if let thumb = message.thumbnailUrl { data["thumbnailUrl"] = thumb }
        }
        
        do {
            try await msgRef.setData(data)
            
            let ft = (message.fileType ?? "").lowercased()
            let label: String = {
                if message.fileUrl != nil {
                    if ft.hasPrefix("image/") { return "📷 Foto" }
                    if ft.hasPrefix("video/") { return "🎬 Vídeo" }
                    if ft.hasPrefix("audio/") { return "🎵 Audio" }
                    return "📎 " + (message.fileName ?? "Archivo")
                } else {
                    return message.text
                }
            }()
            
            try await db.collection("chats").document(targetChatId).setData([
                "lastMessage": label,
                "updatedAt": FieldValue.serverTimestamp(),
                "lastSenderId": uid
            ], merge: true)
        } catch {
            print("❌ Error reenviando:", error.localizedDescription)
        }
    }
    
    private func highlightedText(_ text: String, query: String) -> Text {
        let ns = text as NSString
        let mutable = NSMutableAttributedString(string: text)
        
        // 1) Resaltado por búsqueda (igual que antes)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            var searchRange = NSRange(location: 0, length: ns.length)
            while true {
                let found = ns.range(of: q, options: [.caseInsensitive], range: searchRange)
                if found.location == NSNotFound { break }
                mutable.addAttributes([
                    .backgroundColor: UIColor.yellow,
                    .foregroundColor: UIColor.black
                ], range: found)
                let nextLocation = found.location + found.length
                let remaining = ns.length - nextLocation
                if remaining <= 0 { break }
                searchRange = NSRange(location: nextLocation, length: remaining)
            }
        }
        
        // 2) Resaltado de @menciones (sutil: subrayado)
        if let regex = try? NSRegularExpression(pattern: "@[A-Za-zÁÉÍÓÚÜÑáéíóúüñ0-9_]{2,}", options: []) {
            let full = NSRange(location: 0, length: ns.length)
            regex.enumerateMatches(in: text, options: [], range: full) { match, _, _ in
                guard let r = match?.range, r.location != NSNotFound else { return }
                mutable.addAttributes([
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ], range: r)
            }
        }
        
        if let attributed = try? AttributedString(mutable) {
            return Text(attributed)
        } else {
            return Text(text)
        }
    }
    
    
    private func firstURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(location: 0, length: (text as NSString).length)
        return detector?.firstMatch(in: text, options: [], range: range)?.url
    }
    
    private func linkIfOnly(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = firstURL(in: trimmed) else { return nil }
        
        let ns = trimmed as NSString
        let range = ns.range(of: url.absoluteString)
        guard range.location != NSNotFound else { return nil }
        
        let rest = ns.replacingCharacters(in: range, with: "")
        let punct = CharacterSet(charactersIn: "[](){}<>.,;:!?'\"")
        let leftover = rest.trimmingCharacters(in: punct.union(.whitespacesAndNewlines))
        
        return leftover.isEmpty ? url : nil
    }
    
    private func extractYouTubeID(from url: URL) -> String? {
        if url.host?.contains("youtu.be") == true {
            return url.lastPathComponent
        } else if url.host?.contains("youtube.com") == true {
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "v" })?.value
        }
        return nil
    }
}

// MARK: - Deep links internos "spots://..."
private func firstSpotsDeepLink(in text: String) -> URL? {
    let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let r = s.range(of: "spots://") else { return nil }
    let raw = String(s[r.lowerBound...])
    return URL(string: raw)
}

// Primer enlace http(s) usando NSDataDetector (para LinkPreviewView)
private func firstHTTPURL(in text: String) -> URL? {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
    let ns = text as NSString
    let range = NSRange(location: 0, length: ns.length)
    guard let match = detector.firstMatch(in: text, options: [], range: range),
          let url = match.url,
          let scheme = url.scheme?.lowercased(),
          (scheme == "http" || scheme == "https")
    else { return nil }
    return url
}

private func deepLinkLabel(for url: URL) -> String {
    guard url.scheme == "spots" else { return "Abrir en Spots" }
    switch url.host?.lowercased() {
    case "spot":   return "Abrir spot"
    case "coord":  return "Ir a coordenadas"
    case "invite": return "Unirse al grupo"
    default:       return "Abrir en Spots"
    }
}


// MARK: - Parseo de spots://spot/<id>?n=&lat=&lon=&img=&loc=&rm=
private struct ParsedSpotDL {
    let id: String
    let name: String?
    let lat: Double?
    let lon: Double?
    let img: String?
    let loc: String?
    let rating: Double?
}

private func parseSpotDeepLink(_ url: URL) -> ParsedSpotDL? {
    guard url.scheme == "spots", url.host?.lowercased() == "spot" else { return nil }
    guard let id = url.pathComponents.dropFirst().first, !id.isEmpty else { return nil }
    let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
    func val(_ k: String) -> String? { comps?.queryItems?.first(where: { $0.name == k })?.value }
    let lat = val("lat").flatMap(Double.init)
    let lon = val("lon").flatMap(Double.init)
    let rm  = val("rm").flatMap(Double.init)
    return ParsedSpotDL(
        id: id,
        name: val("n"),
        lat: lat,
        lon: lon,
        img: val("img"),
        loc: val("loc"),
        rating: rm
    )
}

// MARK: - Card del spot con hidratación de mini datos
private struct MiniSpot {
    let id: String
    let name: String
    let ratingMean: Double?
    let imageUrl: String?
    let locality: String?
    let latitude: Double?
    let longitude: Double?
}

private final class SpotSummaryCache {
    static let shared = SpotSummaryCache()
    private var dict: [String: MiniSpot] = [:]
    func get(_ id: String) -> MiniSpot? { dict[id] }
    func set(_ s: MiniSpot) { dict[s.id] = s }
}

private extension String {
    var dehyphenated: String { replacingOccurrences(of: "-", with: " ") }
}

private struct SpotsLinkCard: View {
    let spotURL: URL
    @State private var mini: MiniSpot? = nil
    
    // 👇 callback hacia arriba (ChatDetailView)
    var onOpen: ((String) -> Void)? = nil
    
    var body: some View {
        let parsed = parseSpotDeepLink(spotURL)
        
        Button {
            if let parsed = parseSpotDeepLink(spotURL) {
                onOpen?(parsed.id)  // ⬅️ devolver control al padre (no notificamos global)
            }
        } label: {
            HStack(spacing: 10) {
                CachedThumbView(urlString: mini?.imageUrl ?? parsed?.img, w: 56, h: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text((mini?.name ?? parsed?.name?.dehyphenated) ?? "Spot")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    if let loc = (mini?.locality ?? parsed?.loc), !loc.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.circle")
                            Text(loc)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    
                    if let r = (mini?.ratingMean ?? parsed?.rating) {
                        HStack(spacing: 6) {
                            TinyStarRating(value: r)
                            Text(String(format: "%.1f", r))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Color.gray.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onAppear { hydrateIfNeeded(parsed) }
    }
    
    // ✅ Thumb cacheado
    private struct CachedThumbView: View {
        let urlString: String?
        let w: CGFloat
        let h: CGFloat
        var body: some View {
            Group {
                if let urlString {
                    CachedImageView(urlString: urlString, height: h, cornerRadius: 8)
                        .frame(width: w, height: h)
                        .clipped()
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15))
                        Image(systemName: "photo").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(width: w, height: h)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
    
    private func hydrateIfNeeded(_ parsed: ParsedSpotDL?) {
        guard let parsed, !parsed.id.isEmpty else { return }
        if let cached = SpotSummaryCache.shared.get(parsed.id) {
            mini = cached
            return
        }
        let bootstrap = MiniSpot(
            id: parsed.id,
            name: (parsed.name?.dehyphenated) ?? "Spot",
            ratingMean: parsed.rating,
            imageUrl: parsed.img,
            locality: parsed.loc,
            latitude: parsed.lat,
            longitude: parsed.lon
        )
        mini = bootstrap
        
        let doc = Firestore.firestore().collection("spots").document(parsed.id)
        doc.getDocument { snap, _ in
            guard let data = snap?.data() else { return }
            let m = MiniSpot(
                id: parsed.id,
                name: (data["name"] as? String) ?? bootstrap.name,
                ratingMean: (data["ratingMean"] as? Double) ?? bootstrap.ratingMean,
                imageUrl: (data["imageUrl"] as? String) ?? bootstrap.imageUrl,
                locality: (data["locality"] as? String) ?? bootstrap.locality,
                latitude: (data["latitude"] as? Double) ?? bootstrap.latitude,
                longitude: (data["longitude"] as? Double) ?? bootstrap.longitude
            )
            let keyURL = "spotThumbURL_\(parsed.id)"
            let keyBust = "spotThumbBust_\(parsed.id)"
            let oldURL = UserDefaults.standard.string(forKey: keyURL)
            let newURL = m.imageUrl
            if let oldURL, let newURL, oldURL != newURL {
                Task { await ImageCache.shared.remove(for: oldURL) }
                let bust = UUID().uuidString
                UserDefaults.standard.set(bust, forKey: keyBust)
                UserDefaults.standard.set(newURL, forKey: keyURL)
            } else if oldURL == nil, let newURL {
                UserDefaults.standard.set(newURL, forKey: keyURL)
            }
            DispatchQueue.main.async {
                SpotSummaryCache.shared.set(m)
                self.mini = m
            }
        }
    }
}

// Thumb asíncrono (no usado aquí pero útil)
private struct SpotsAsyncThumb: View {
    let urlString: String?
    let w: CGFloat
    let h: CGFloat
    var body: some View {
        Group {
            if let s = urlString, let url = URL(string: s) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15))
                            ProgressView()
                        }
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure:
                        thumbPlaceholder
                    @unknown default:
                        thumbPlaceholder
                    }
                }
            } else {
                thumbPlaceholder
            }
        }
        .frame(width: w, height: h)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    private var thumbPlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15))
            Image(systemName: "photo").font(.caption).foregroundStyle(.secondary)
        }
    }
}

// Estrellas pequeñas (0..5)
private struct TinyStarRating: View {
    let value: Double
    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<5, id: \.self) { i in
                let filled = Double(i+1) <= round(value)
                Image(systemName: filled ? "star.fill" : "star")
                    .font(.caption2)
            }
        }
        .foregroundStyle(.yellow)
    }
}

// MARK: - Chips / utilidades varias
private struct SpotsCoordChip: View {
    let url: URL
    var body: some View {
        Button {
            NotificationCenter.default.post(
                name: .openSpotsDeepLink,
                object: nil,
                userInfo: ["url": url.absoluteString]
            )
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "location.north.line")
                Text("Ir a coordenadas").font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.gray.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct SpotsInviteChip: View {
    let url: URL
    let groupName: String?
    
    @State private var resolvedGroupName: String? = nil
    @State private var hasResolved = false
    
    private var code: String {
        // spots://invite/<CODE>
        let comps = url.pathComponents.dropFirst() // quita la "/"
        return comps.first ?? ""
    }
    
    private func resolveGroupName() {
        guard !hasResolved else { return }
        hasResolved = true

        let raw = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return }
        let inviteCode = raw.uppercased()

        print("[INVITE] resolve start code=\(inviteCode)")

        // 👇 región correcta: europe-west1
        let fn = Functions.functions(region: "europe-west1").httpsCallable("getInviteMeta")
        fn.call(["code": inviteCode]) { result, error in
            if let error = error {
                print("[INVITE] getInviteMeta error:", error.localizedDescription)
                if let fallback = groupName, !fallback.isEmpty {
                    DispatchQueue.main.async { self.resolvedGroupName = fallback }
                }
                return
            }
            guard let dict = result?.data as? [String: Any] else {
                print("[INVITE] getInviteMeta no dict (result?.data == nil)")
                if let fallback = groupName, !fallback.isEmpty {
                    DispatchQueue.main.async { self.resolvedGroupName = fallback }
                }
                return
            }
            let name = (dict["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            print("[INVITE] getInviteMeta ok name=\(name ?? "nil")")
            if let name, !name.isEmpty {
                DispatchQueue.main.async { self.resolvedGroupName = name }
            } else if let fallback = groupName, !fallback.isEmpty {
                DispatchQueue.main.async { self.resolvedGroupName = fallback }
            }
        }
    }


    
    var body: some View {
        Button {
            // Reutilizamos tu router global: RootView ya maneja spots://invite/*
            NotificationCenter.default.post(
                name: .openSpotsDeepLink,
                object: nil,
                userInfo: ["url": url.absoluteString]
            )
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "link.badge.plus")
                VStack(alignment: .leading, spacing: 2) {
                    if let name = (resolvedGroupName ?? groupName), !name.isEmpty {
                        Text("Unirse al grupo \(name)").font(.subheadline.weight(.semibold))
                    } else {
                        Text("Unirse al grupo").font(.subheadline.weight(.semibold))
                    }
                    if !code.isEmpty {
                        Text(code).font(.caption2).foregroundStyle(.secondary).monospaced()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.blue.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .onAppear { resolveGroupName() }
    }
}





private struct SpotsDeepLinkBubble: View {
    let url: URL
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.and.ellipse")
            Text(deepLinkLabel(for: url))
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.green.opacity(0.18))
        .cornerRadius(12)
        .onTapGesture {
            NotificationCenter.default.post(
                name: .openSpotsDeepLink,
                object: nil,
                userInfo: ["url": url.absoluteString]
            )
        }
    }
}

// MARK: - URL Preview Prefetcher (BG cache sin tocar UI)
final class URLPreviewPrefetcher {
    static let shared = URLPreviewPrefetcher()

    private let queue = DispatchQueue(label: "URLPreviewPrefetcher.queue", qos: .utility)
    private var inflight = Set<String>()
    private let cacheDir: URL

    private init() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDir = base.appendingPathComponent("URLPreviewCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // Public API: fire-and-forget
    func prefetchIfNeeded(_ url: URL) {
        let key = self.key(for: url)
        queue.async {
            // skip si ya existe algo cacheado o ya estamos en vuelo
            let imgURL = self.imageURL(forKey: key)
            let metaURL = self.metaURL(forKey: key)
            if (FileManager.default.fileExists(atPath: imgURL.path) &&
                FileManager.default.fileExists(atPath: metaURL.path)) {
                return
            }
            if self.inflight.contains(key) { return }
            self.inflight.insert(key)

            Task.detached(priority: .utility) { [weak self] in
                defer { self?.queue.async { self?.inflight.remove(key) } }
                await self?.fetchAndCache(url: url, key: key)
            }
        }
    }

    // MARK: - Internals

    private func key(for url: URL) -> String {
        // FNV-1a 64
        let bytes = Array(url.absoluteString.utf8)
        var h: UInt64 = 0xcbf29ce484222325
        for b in bytes { h ^= UInt64(b); h &*= 0x100000001b3 }
        return String(format: "%016llx", h)
    }

    private func imageURL(forKey key: String) -> URL { cacheDir.appendingPathComponent(key).appendingPathExtension("jpg") }
    private func metaURL(forKey key: String) -> URL { cacheDir.appendingPathComponent(key).appendingPathExtension("meta") }

    private func fetchAndCache(url: URL, key: String) async {
        let provider = LPMetadataProvider()
        provider.timeout = 8

        do {
            let meta = try await provider.startFetchingMetadata(for: url)

            // 1) Imagen principal
            if let item = meta.imageProvider,
               let img = try? await item.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) as? UIImage {
                self.save(image: img, forKey: key)
            }
            // 2) Fallback: icono del sitio (favicon)
            else if let icon = meta.iconProvider,
                    let img = try? await icon.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) as? UIImage {
                self.save(image: img, forKey: key)
            }
            // 3) Fallback YouTube directo
            else if let yt = youtubeThumbnailURL(for: url),
                    let data = try? Data(contentsOf: yt),
                    let img = UIImage(data: data) {
                self.save(image: img, forKey: key)
            }

            // Guarda metadata serializada (por si en un futuro la quieres leer)
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: meta, requiringSecureCoding: true) {
                try? data.write(to: self.metaURL(forKey: key), options: .atomic)
            }
        } catch {
            // Si falla todo, no bloqueamos: intentamos al menos YouTube
            if let yt = youtubeThumbnailURL(for: url),
               let data = try? Data(contentsOf: yt),
               let img = UIImage(data: data) {
                self.save(image: img, forKey: key)
            }
        }
    }

    private func save(image: UIImage, forKey key: String) {
        if let data = image.jpegData(compressionQuality: 0.9) {
            try? data.write(to: self.imageURL(forKey: key), options: .atomic)
        }
    }

    private func youtubeThumbnailURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              host.contains("youtube") || host.contains("youtu.be") else { return nil }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let id = (comps?.queryItems?.first(where: { $0.name == "v" })?.value) ?? url.lastPathComponent
        guard !id.isEmpty else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")
    }
}


struct ForwardPickerSheet: View {
    let currentChatId: String
    let onSelect: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var chatsVM = ChatsViewModel.shared
    
    var body: some View {
        NavigationView {
            List {
                ForEach(chatsVM.chats.filter { $0.id != currentChatId }, id: \.id) { chat in
                    Button {
                        onSelect(chat.id)
                        dismiss()
                    } label: {
                        HStack {
                            Text(chat.displayName ?? "Chat")
                                .foregroundColor(.primary)
                                .lineLimit(1)
                            Spacer()
                            if let last = chat.lastMessage, !last.isEmpty {
                                Text(last)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                }
            }
            .navigationTitle("Reenviar a…")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
        }.onAppear {
            chatsVM.start()
        }
    }
}

struct LinkText: View {
    let text: String
    var body: some View {
        Text(makeAttributedString(text)).textSelection(.enabled)
    }
    private func makeAttributedString(_ input: String) -> AttributedString {
        let mutable = NSMutableAttributedString(string: input)
        let fullRange = NSRange(location: 0, length: (input as NSString).length)
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
            detector.enumerateMatches(in: input, options: [], range: fullRange) { match, _, _ in
                guard let match else { return }
                if let url = match.url {
                    mutable.addAttribute(.link, value: url, range: match.range)
                }
            }
        }
        if let attr = try? AttributedString(mutable, including: \.uiKit) {
            return attr
        } else {
            return AttributedString(input)
        }
    }
}

struct BottomAnchorView: View { var body: some View { Color.clear.frame(height: 1) } }

struct UnreadSeparatorView: View {
    let count: Int
    var body: some View {
        HStack {
            Spacer()
            Text(count == 1 ? "1 mensaje no leído" : "\(count) mensajes no leídos")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(10)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct DateSeparatorView: View {
    let date: Date
    var body: some View {
        HStack {
            VStack { Divider().background(Color.gray.opacity(0.4)) }
            Text(formattedDate(date))
                .font(.caption2.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .background(Color(.systemBackground))
                .cornerRadius(12)
            VStack { Divider().background(Color.gray.opacity(0.4)) }
        }
        .padding(.vertical, 8)
    }
    private func formattedDate(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Hoy" }
        else if Calendar.current.isDateInYesterday(date) { return "Ayer" }
        else {
            let f = DateFormatter()
            f.locale = Locale(identifier: "es_ES")
            f.dateFormat = "d MMMM yyyy"
            return f.string(from: date)
        }
    }
}

struct ProfileSheetView: View {
    let displayName: String?
    let chat: Chat
    
    @State private var userStatus: String = "conectando…"
    @State private var statusListener: ListenerRegistration?
    
    // Mute 1:1
    @State private var isMuted = false
    @State private var isLoadingMute = true
    
    @State private var showReasonDialog = false
    @State private var isReporting = false
    @State private var selectedReason: ReportReason? = nil
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            avatarLarge
            Text(displayName ?? "Usuario").font(.title2.bold())
            
            HStack(spacing: 6) {
                Circle().fill(userStatus == "en línea" ? Color.green : Color.gray).frame(width: 10, height: 10)
                Text(userStatus).font(.caption).foregroundColor(.secondary)
            }
            
            // Toggle de silencio (esta sheet solo se usa en 1:1)
            if isLoadingMute {
                ProgressView().controlSize(.small).padding(.top, 8)
            } else {
                Toggle(isOn: $isMuted) {
                    Label("Silenciar chat", systemImage: "bell.slash.fill")
                }
                .toggleStyle(SwitchToggleStyle(tint: .orange))
                .padding(.top, 8)
                .accessibilityIdentifier("muteToggle")
                .onChange(of: isMuted) { newValue in
                    Task { try? await ChatPrefsService.shared.setMute(chatId: chat.id, mute: newValue) }
                }
            }
            
            Button(role: .destructive) { showReasonDialog = true } label: {
                Label("Reportar usuario", systemImage: "exclamationmark.triangle.fill")
            }
            .accessibilityIdentifier("reportUserButton")
            .padding(.top, 8)
            .disabled(isReporting)
            
            Spacer()
            Button("Cerrar") { dismiss() }
        }
        .padding()
        .onAppear {
            loadUserStatus()
            // Leer mute de este chat (1:1)
            Task {
                isMuted = await ChatPrefsService.shared.getMute(chatId: chat.id)
                isLoadingMute = false
            }
        }
        .onDisappear { statusListener?.remove() }
        .confirmationDialog("Motivo del reporte", isPresented: $showReasonDialog, titleVisibility: .visible) {
            ForEach(ReportReason.allCases) { reason in
                Button(reason.title) {
                    selectedReason = reason
                    Task { await sendReport(reason: reason) }
                }
            }
            Button("Cancelar", role: .cancel) {}
        }
    }
    
    enum ReportReason: String, CaseIterable, Identifiable {
        case spam = "Spam"
        case falseInfo = "Contenido falso/incorrecto"
        case inappropriate = "Inapropiado"
        case hate = "Discurso de odio/Insultos"
        case personalData = "Datos personales"
        
        var id: String { rawValue }
        var title: String { rawValue }
    }
    
    private func sendReport(reason: ReportReason) async {
        guard !isReporting else { return }
        isReporting = true
        defer { isReporting = false }
        
        guard let myId = Auth.auth().currentUser?.uid,
              let otherId = chat.participants.first(where: { $0 != myId }) else {
            print("❌ No se pudo resolver otherUserId para reporte")
            return
        }
        
        await ReportService.reportUser(otherUserId: otherId, reason: reason.title)
        
        NotificationCenter.default.post(name: .userReportedFromProfile, object: nil)
        await MainActor.run { dismiss() }
    }
    
    private var avatarLarge: some View {
        let myId = Auth.auth().currentUser?.uid
        let otherId = chat.participants.first { $0 != myId }
        if let otherId, let urlStr = ChatsViewModel.shared.profileImages[otherId] {
            return AnyView(
                CachedAvatarImageView(
                    urlString: urlStr,
                    initials: displayName,
                    size: 120
                )
                .overlay(avatarBorder.frame(width: 120, height: 120))
            )
        } else {
            return AnyView(
                ZStack {
                    Circle().fill(Color.blue.opacity(0.2)).frame(width: 120, height: 120)
                    Text(String((displayName ?? "U").prefix(2)).uppercased())
                        .font(.largeTitle.bold())
                        .foregroundColor(.blue)
                }
                    .overlay(avatarBorder.frame(width: 120, height: 120))
            )
        }
    }
    
    private func loadUserStatus() {
        guard let myId = Auth.auth().currentUser?.uid,
              let otherId = chat.participants.first(where: { $0 != myId }) else { return }
        
        statusListener = Firestore.firestore().collection("users").document(otherId)
            .addSnapshotListener { snap, _ in
                guard let data = snap?.data() else {
                    self.userStatus = "desconocido"
                    return
                }
                self.userStatus = UserStatusFormatter.format(from: data)
            }
    }
    
    private var avatarBorder: some View {
        ZStack {
            Circle().stroke(Color.white, lineWidth: 6)
            Circle().stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.0, green: 0.85, blue: 0.9),
                        Color(red: 0.2, green: 0.5, blue: 1.0)
                    ]),
                    center: .center
                ),
                lineWidth: 3
            )
            .padding(-2)
        }
    }
}

extension UIApplication {
    func endEditing(_ force: Bool) {
        connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.endEditing(force)
    }
}


// MARK: - Cached Link Preview (disk cache for metadata + image)


