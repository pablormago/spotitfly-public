//
//  ChatSpotDetailView.swift
//  Spots
//

import SwiftUI
import MapKit
import UIKit
import FirebaseAuth
import FirebaseFirestore

struct ChatSpotDetailView: View {
    let spot: Spot
    
    @EnvironmentObject var userSession: UserSession
    @EnvironmentObject var spotsVM: SpotsViewModel
    @EnvironmentObject var favoritesVM: FavoritesViewModel
    @Environment(\.dismiss) private var dismiss
    
    // 🆕 Reporte de spot
    @State private var showReportReasons = false
    @State private var reportingSpot = false

    // Contexto / creador
    @State private var showContext = false
    @State private var loadingContext = true
    @State private var contextData: SpotContextData?
    @State private var creatorName: String = ""
    
    // Acciones propietario
    @State private var showEdit = false
    @State private var showDeleteAlert = false
    @State private var deleting = false
    
    // Acceso y comentarios
    @State private var showAcceso = false
    @State private var showCommentsSheet = false
    
    // Toast (editar/borrar/reportar)
    @State private var showToast = false
    @State private var toastMessage = ""
    @State private var toastIcon: String? = nil
    
    // Chat con el creador
    @State private var openChat: Chat? = nil
    
    // ⭐️ Votación
    @State private var showVoting = false
    
    // ☁️ Día seleccionado para sheet por horas
    @State private var selectedDay: WeatherDayData? = nil
    
    // Spot vivo por si cambió en el VM
    private var s: Spot {
        spotsVM.spots.first(where: { $0.id == spot.id }) ?? spot
    }
    
    @State private var showShareMenu = false
    @State private var showChatPicker = false

    private func enc(_ s: String?) -> String {
        guard let s, !s.isEmpty else { return "" }
        return s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s
    }

    private var deepLinkForSpot: String {
        let n   = enc(s.name)
        let img = enc(s.imageUrl)
        let loc = enc(s.locality)
        let rm  = String(format: "%.1f", s.ratingMean)

        var comps = "spots://spot/\(s.id)?n=\(n)&lat=\(s.latitude)&lon=\(s.longitude)&rm=\(rm)"
        if !img.isEmpty { comps += "&img=\(img)" }
        if !loc.isEmpty { comps += "&loc=\(loc)" }
        return comps
    }


    private func copySpotLink() {
        UIPasteboard.general.string = deepLinkForSpot
        toastMessage = "Enlace copiado"
        toastIcon = "link"
        withAnimation { showToast = true }
    }

    
    // Propietario
    private var isOwner: Bool {
        let createdByLower = s.createdBy.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let uidLower = (userSession.uid ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let emailLower = (userSession.email ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let usernameLower = (userSession.username ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !createdByLower.isEmpty && (createdByLower == uidLower || createdByLower == emailLower || createdByLower == usernameLower)
    }
    
    private var miniRegion: MKCoordinateRegion {
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: s.latitude, longitude: s.longitude),
            latitudinalMeters: 2000,
            longitudinalMeters: 2000
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                
                // Imagen
                imageSection
                
                // Botones propietario + categoría / reportar
                ownerButtons
                
                // Título + descripción + usuario + estrellas
                titleStarsCategory
                
                // Línea: bocadillo+contador (izda) + Acceso (dcha)
                commentsAndAccessRow
                
                // Best date opcional
                if let bestDate = s.bestDate, !bestDate.isEmpty {
                    HStack {
                        Image(systemName: "calendar")
                        Text(bestDate)
                    }
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Restricciones
                restrictionsBlock
                
                // 📍 Localidad (si existe)
                if let localidad = s.locality, !localidad.isEmpty {
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.red)
                        Text(localidad)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                
                // Mapa (con placeholder de carga)
                Group {
                    if s.latitude != 0 && s.longitude != 0 {
                        Map(
                            coordinateRegion: .constant(miniRegion),
                            annotationItems: [s]
                        ) { spot in
                            MapMarker(
                                coordinate: CLLocationCoordinate2D(latitude: spot.latitude, longitude: spot.longitude),
                                tint: .blue
                            )
                        }
                        .frame(height: 180)
                        .cornerRadius(12)
                        .shadow(radius: 4)
                    } else {
                        ZStack {
                            Rectangle().fill(Color.gray.opacity(0.15))
                            ProgressView()
                        }
                        .frame(height: 180)
                        .cornerRadius(12)
                        .shadow(radius: 2)
                    }
                }
                
                Spacer(minLength: 0)
                
                // Botón IR
                directionsButton
                // Botón Reportar (al final)
                reportSpotBottomButton
                    .padding(.top, 8)
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .presentationDetents([.medium, .large])
        .task {
            await loadCreator()
            await loadContext()
        }
        .onAppear {
            if isOwner, let uid = userSession.uid {
                Task { await CommentReadService.shared.markSeen(spotId: s.id, userId: uid) }
            }
        }
        .onChange(of: s.latitude) { _ in Task { await invalidateAndReloadContext() } }
        .onChange(of: s.longitude) { _ in Task { await invalidateAndReloadContext() } }
        
        // Editar
        .sheet(isPresented: $showEdit) {
            SpotEditView(spot: s) { _ in
                toastMessage = "Spot actualizado"
                toastIcon = "checkmark.circle.fill"
                withAnimation { showToast = true }
            }
            .environmentObject(spotsVM)
        }
        
        .confirmationDialog("Compartir spot", isPresented: $showShareMenu, titleVisibility: .visible) {
            Button("Compartir en chat…") { showChatPicker = true }
            Button("Copiar enlace") { copySpotLink() }
            Button("Cancelar", role: .cancel) {}
        }
        .sheet(isPresented: $showChatPicker) {
            // Reutilizamos el selector de chats que ya tienes en ChatDetailView
            ForwardPickerSheet(currentChatId: "") { targetChatId in
                Task {
                    let vm = ChatViewModel(chatId: targetChatId)
                    await vm.send(text: deepLinkForSpot)
                    toastMessage = "Enlace enviado al chat"
                    toastIcon = "paperplane.fill"
                    withAnimation { showToast = true }
                }
            }
        }

        
        // Borrar
        .alert("¿Borrar este spot?", isPresented: $showDeleteAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Borrar", role: .destructive) { Task { await deleteSpot() } }
        } message: {
            Text("Esta acción no se puede deshacer.")
        }
        
        // Toast
        .toast(isPresented: $showToast, message: toastMessage, systemImage: toastIcon, duration: 3.0)
        
        // Acceso
        .sheet(isPresented: $showAcceso) {
            VStack(spacing: 16) {
                Text("Cómo acceder").font(.headline)
                ScrollView {
                    Text(s.acceso ?? "")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
            }
            .padding()
        }
        
        // Sheet de comentarios
        .sheet(isPresented: $showCommentsSheet) {
            CommentsSheetView(
                spotId: s.id,
                spotDescription: s.description,
                creatorName: creatorName
            )
            .environmentObject(userSession)
            .presentationDetents([.medium, .large])
        }
        
        // Chat como sheet
        .sheet(item: $openChat) { chat in
            NavigationView {
                ChatDetailView(chat: chat, backLabel: "Spot")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        
        // ☁️ Sheet del tiempo por horas (binding derivado para evitar Identifiable)
        .sheet(
            isPresented: Binding<Bool>(
                get: { selectedDay != nil },
                set: { if !$0 { selectedDay = nil } }
            ),
            content: {
                if let d = selectedDay {
                    WeatherHourlySheet(
                        lat: s.latitude,
                        lon: s.longitude,
                        isoDate: d.isoDate,
                        title: "\(d.day) \(d.date)"
                    )
                } else {
                    EmptyView()
                }
            }
        )
    }
    
    // MARK: - Secciones
    private var imageSection: some View {
        ZStack {
            // Imagen principal
            Group {
                if let urlString = s.imageUrl, !urlString.isEmpty {
                    SpotDetailThumb(urlString: urlString)
                        .frame(height: 220)
                        .cornerRadius(12)
                        .shadow(radius: 4)
                        .padding(.bottom,-20)
                } else {
                    ZStack {
                        Rectangle().fill(Color.gray.opacity(0.18))
                        Image(systemName: "photo")
                            .resizable().scaledToFit()
                            .frame(width: 64, height: 64)
                            .foregroundColor(.gray)
                    }
                    .frame(height: 220)
                    .cornerRadius(12)
                    .shadow(radius: 2)
                    .padding(.bottom,-20)
                }
            }
        }
        // ❌ Botón cerrar → arriba derecha
        .overlay(
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.gray)
                    .frame(width: 34, height: 34)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.25), radius: 4, x: 0, y: 2)
            }
                .padding([.top, .trailing], 6),
            alignment: .topTrailing
        )
        // ❤️ Botón favoritos → abajo derecha
        .overlay(
            Button {
                Task { await favoritesVM.toggleFavorite(spot: s) }
            } label: {
                Image(systemName: s.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(s.isFavorite ? .red : .white)
                    .padding(8)
                    .background(Color.black.opacity(0.4))
                    .clipShape(Circle())
                    .shadow(radius: 3)
            }
                .padding(.trailing, 3)
                .padding(.bottom, -15),
            alignment: .bottomTrailing
        )
    }
    
    private var ownerButtons: some View {
        HStack {
            if isOwner {
                Button { showEdit = true } label: {
                    Label("Editar", systemImage: "pencil")
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.12))
                        .foregroundColor(.blue)
                        .cornerRadius(8)
                }
                Button(role: .destructive) { showDeleteAlert = true } label: {
                    Label("Borrar", systemImage: "trash")
                        .font(.subheadline)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.12))
                        .foregroundColor(.red)
                        .cornerRadius(8)
                }
                .disabled(deleting)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }


    private var titleStarsCategory: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(s.name)
                .font(.title)
                .bold()
            
            // 👤 Creador (clicable → abre chat)
            Button {
                Task { await openChatWithCreator() }
            } label: {
                Text(creatorName.isEmpty ? s.createdBy : creatorName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            
            // 🏷️ Categoría
            CategoryChip(category: s.category)
            
            // 📄 Descripción
            Text(s.description)
                .font(.body)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
            
            // ⭐️ Media real
            HStack(spacing: 8) {
                StaticStarRatingView(average: s.ratingMean, maxStars: 5, starSize: 20)
                Text(String(format: "%.1f", s.ratingMean))
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.primary)
                Spacer()
                // 🔗 Compartir (entre estrellas y VOTAR)
                Button {
                    showShareMenu = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .accessibilityIdentifier("shareSpotButton")

                Spacer()

                Button("VOTAR") {
                    withAnimation { showVoting.toggle() }
                }
                .font(.subheadline.weight(.bold))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.15))
                .cornerRadius(8)
            }

            
            // ⭐️ Estrellas interactivas (solo si se pulsa VOTAR)
            if showVoting, let uid = userSession.uid {
                GeometryReader { geo in
                    let starWidth = geo.size.width / 5
                    StarRatingView(spot: s, userId: uid, starSize: starWidth) {
                        withAnimation { showVoting = false }
                    }
                    .environmentObject(spotsVM)
                    .frame(width: geo.size.width, height: starWidth)
                }
                .frame(height: 60)
                .padding(.vertical, 8)
            }
            
            // ☁️ BLOQUE DEL TIEMPO (con onSelect de día)
            SpotWeatherSection(lat: s.latitude, lon: s.longitude) { d in
                selectedDay = d
            }
            .padding(.vertical, 8)
        }
    }
    
    private var commentsAndAccessRow: some View {
        HStack {
            Button { showCommentsSheet = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "text.bubble")
                        .font(.headline)
                    CommentCountInline(spotId: s.id, initialCount: s.commentCount ?? 0)
                }
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            if let acceso = s.acceso, !acceso.isEmpty {
                Button { showAcceso = true } label: {
                    Text("Acceso")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundColor(.white)
                        .background(Color.green)
                        .cornerRadius(8)
                }
            }
        }
    }
    
    private var restrictionsBlock: some View {
        VStack(spacing: 8) {
            Button {
                guard !loadingContext else { return }
                withAnimation(.easeInOut) { showContext.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.white)
                    Image(systemName: "megaphone.fill").foregroundColor(.white)
                    Text("Restricciones").bold().foregroundColor(.white)
                    Spacer()
                    if loadingContext {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                            .padding(.trailing, 6)
                    }
                    Image(systemName: showContext ? "chevron.up" : "chevron.down")
                        .foregroundColor(.white)
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(Color.red)
                .cornerRadius(10)
            }
            .disabled(loadingContext)
            .opacity(loadingContext ? 0.75 : 1.0)
            
            if showContext, !loadingContext {
                VStack(spacing: 12) {
                    if let contextData = contextData {
                        SpotDetailContextViewLoaded(contextData: contextData)
                            .frame(maxHeight: 300)
                            .transition(.opacity)
                    } else {
                        Text("No se encontraron datos de restricciones.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }
                    
                    // 🆕 Botón recargar datos
                    Button {
                        withAnimation { loadingContext = true }
                        Task { await invalidateAndReloadContext() }
                    } label: {
                        Label("Recargar datos", systemImage: "arrow.clockwise")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.15))
                            .cornerRadius(8)
                    }
                }
            }
        }
    }
    
    private var directionsButton: some View {
        Button(action: {
            let destination = "\(s.latitude),\(s.longitude)"
            let googleMapsURL = URL(string: "comgooglemaps://?daddr=\(destination)&directionsmode=driving")!
            let appleMapsURL = URL(string: "maps://?daddr=\(destination)&dirflg=d")!
            
            if UIApplication.shared.canOpenURL(googleMapsURL) {
                UIApplication.shared.open(googleMapsURL)
            } else {
                UIApplication.shared.open(appleMapsURL)
            }
        }) {
            Label("Ir", systemImage: "car.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.purple)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
        .padding(.top, 8)
    }
    
    // Botón de Reporte al final de la vista
    private var reportSpotBottomButton: some View {
        Group {
            if !isOwner {
                Button(role: .destructive) {
                    showReportReasons = true
                } label: {
                    Label("Reportar Spot", systemImage: "exclamationmark.bubble")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.12))
                        .foregroundColor(.red)
                        .cornerRadius(10)
                }
                .accessibilityIdentifier("reportSpotButton")
                .disabled(reportingSpot) // 👈 evita taps dobles

                .confirmationDialog("Motivo del reporte",
                                    isPresented: $showReportReasons,
                                    titleVisibility: .visible) {
                    Button("Spam", role: .destructive) { Task { await reportSpot(reason: "Spam") } }
                    Button("Contenido falso/incorrecto", role: .destructive) { Task { await reportSpot(reason: "Contenido falso/incorrecto") } }
                    Button("Contenido inapropiado", role: .destructive) { Task { await reportSpot(reason: "Contenido inapropiado") } }
                    Button("Discurso de odio/Insultos", role: .destructive) { Task { await reportSpot(reason: "Discurso de odio/Insultos") } }
                    Button("Datos personales", role: .destructive) { Task { await reportSpot(reason: "Datos personales") } }
                    Button("Cancelar", role: .cancel) { }
                }
            }
        }
    }

    
    // MARK: - Datos auxiliares
    private func loadCreator() async {
        guard !s.createdBy.isEmpty else { return }
        if let name = await UserService.shared.username(for: s.createdBy) {
            await MainActor.run { self.creatorName = name }
        } else {
            await MainActor.run { self.creatorName = s.createdBy }
        }
    }
    
    private func loadContext() async {
        loadingContext = true
        defer { loadingContext = false }
        if let cached = await SpotContextCache.shared.get(for: s.id) {
            await MainActor.run { self.contextData = cached }
            return
        }
        let vm = SpotDetailViewModel()
        await vm.fetchContext(for: s)
        let data = vm.contextData
        await SpotContextCache.shared.set(data, for: s.id)
        await MainActor.run { self.contextData = data }
    }
    
    private func invalidateAndReloadContext() async {
        await SpotContextCache.shared.remove(id: s.id)
        await loadContext()
    }
    
    private func deleteSpot() async {
        guard !deleting else { return }
        deleting = true
        defer { deleting = false }
        
        do {
            try await spotsVM.deleteSpot(id: s.id)
            if let url = s.imageUrl, !url.isEmpty {
                await ImageCache.shared.remove(for: url)
            }
            await SpotContextCache.shared.remove(id: s.id)
            await MainActor.run {
                toastMessage = "Spot borrado"
                toastIcon = "trash"
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation { showToast = true }
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { dismiss() }
        } catch {
            print("❌ Error al borrar spot:", error.localizedDescription)
        }
    }
    
    private func openChatWithCreator() async {
        guard let myUid = Auth.auth().currentUser?.uid else { return }
        let otherId = s.createdBy
        guard !otherId.isEmpty, otherId != myUid else { return }
        
        let db = Firestore.firestore()
        let participants = [myUid, otherId].sorted()
        let chatId = participants.joined(separator: "_")
        let ref = db.collection("chats").document(chatId)
        
        do {
            let snap = try await ref.getDocument()
            if !snap.exists {
                try await ref.setData([
                    "participants": participants,
                    "lastMessage": "",
                    "updatedAt": FieldValue.serverTimestamp(),
                    "lastSenderId": FieldValue.delete()
                ], merge: false)
            }
            
            let chat = Chat(
                id: chatId,
                participants: participants,
                lastMessage: snap.data()?["lastMessage"] as? String,
                updatedAt: (snap.data()?["updatedAt"] as? Timestamp)?.dateValue(),
                displayName: creatorName.isEmpty ? otherId : creatorName,
                lastRead: [:],
                lastSenderId: snap.data()?["lastSenderId"] as? String
            )
            
            await MainActor.run { openChat = chat }
        } catch {
            print("❌ Error creando/abriendo chat con creador:", error.localizedDescription)
        }
    }
    
    // 🆕 Reporte Spot (cerrando diálogo, háptica y toast)
    private func reportSpot(reason: String) async {
        guard !reportingSpot else { return }
        reportingSpot = true
        defer { reportingSpot = false }

        // cierra el confirmationDialog en cuanto elijas motivo
        await MainActor.run { showReportReasons = false }

        // háptica ligera de confirmación
        let haptic = UINotificationFeedbackGenerator()
        haptic.notificationOccurred(.success)

        await ReportService.reportSpot(spotId: s.id, reason: reason)

        await MainActor.run {
            toastMessage = "Reporte enviado. Gracias por avisar."
            toastIcon = "exclamationmark.bubble.fill"
            withAnimation { showToast = true }
        }
    }

}

// MARK: - Mini contador inline para comentarios
private struct CommentCountInline: View {
    let spotId: String
    @State private var count: Int? = nil
    @State private var loaded = false
    
    init(spotId: String, initialCount: Int) {
        self.spotId = spotId
        _count = State(initialValue: nil)
    }
    
    var body: some View {
        Text(count.map { "\($0)" } ?? "")
            .font(.headline)
            .foregroundColor(.secondary)
            .onAppear {
                if !loaded { Task { await loadCount() } }
            }
            .task(id: spotId) {
                await loadCount()
            }
            .onReceive(NotificationCenter.default.publisher(for: .commentsDidChange)) { _ in
                Task { await loadCount() }
            }
    }
    
    private func loadCount() async {
        defer { loaded = true }
        let ref = Firestore.firestore()
            .collection("spots").document(spotId)
            .collection("comments")
        do {
            let snap = try await ref.count.getAggregation(source: .server)
            if let n = snap.count as? NSNumber {
                await MainActor.run { self.count = n.intValue }
                return
            }
        } catch {
            do {
                let docs = try await ref.getDocuments()
                await MainActor.run { self.count = docs.documents.count }
            } catch {
                await MainActor.run { self.count = 0 }
            }
        }
    }
}

private struct SpotDetailThumb: View {
    let urlString: String
    @State private var image: UIImage? = nil
    
    var body: some View {
        Group {
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(Color.gray.opacity(0.18))
                    ProgressView()
                }
            }
        }
        .task { image = await ImageCache.shared.image(for: urlString) }
        .clipped()
    }
}
