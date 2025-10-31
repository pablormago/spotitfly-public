import SwiftUI
import FirebaseStorage

struct SpotEditView: View {
    let spot: Spot
    var onSaved: ((Spot) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var spotsVM: SpotsViewModel

    // Campos existentes
    @State private var name: String
    @State private var description: String
    @State private var selectedCategory: SpotCategory
    @State private var rating: Int
    @State private var bestDate: String
    @State private var isSaving = false
    @State private var errorText: String?

    // Foto
    @State private var pickedImage: UIImage? = nil
    @State private var showingImagePicker = false
    @State private var showSourceDialog = false
    @State private var pickerSource: ImagePickerController.Source = .library
    @State private var removeExistingImage: Bool = false

    // 🆕 Campo acceso
    @State private var acceso: String

    // 🆕 Coordenadas editables
    @State private var latitudeText: String
    @State private var longitudeText: String

    init(spot: Spot, onSaved: ((Spot) -> Void)? = nil) {
        self.spot = spot
        self.onSaved = onSaved
        _name = State(initialValue: spot.name)
        _description = State(initialValue: spot.description)
        _selectedCategory = State(initialValue: spot.category)
        _rating = State(initialValue: spot.rating)
        _bestDate = State(initialValue: spot.bestDate ?? "")
        _acceso = State(initialValue: spot.acceso ?? "")
        _latitudeText = State(initialValue: String(format: "%.5f", spot.latitude))
        _longitudeText = State(initialValue: String(format: "%.5f", spot.longitude))
    }

    var body: some View {
        NavigationView {
            Form {
                // === Foto como primera sección ===
                Section(header: Text("Foto")) {
                    VStack(alignment: .leading, spacing: 10) {
                        photoPreview
                            .frame(height: 180)
                            .clipped()
                            .cornerRadius(10)
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

                        HStack(spacing: 16) {
                            Button {
                                showSourceDialog = true
                            } label: {
                                Label("Cambiar foto", systemImage: "photo.on.rectangle.angled")
                                    .labelStyle(.titleAndIcon)
                                    .lineLimit(1)
                            }

                            if pickedImage != nil || (spot.imageUrl?.isEmpty == false && !removeExistingImage) {
                                Button(role: .destructive) {
                                    pickedImage = nil
                                    removeExistingImage = true
                                } label: {
                                    Label("Quitar foto", systemImage: "trash")
                                        .labelStyle(.titleAndIcon)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // === Detalles ===
                Section(header: Text("Detalles")) {
                    TextField("Nombre del spot", text: $name)
                        .textInputAutocapitalization(.sentences)

                    TextField("Descripción", text: $description, axis: .vertical)
                        .lineLimit(3...6)

                    Picker("Categoría", selection: $selectedCategory) {
                        ForEach(SpotCategory.allCases, id: \.self) { cat in
                            Text(cat.rawValue).tag(cat)
                        }
                    }

                    Stepper(value: $rating, in: 0...5) {
                        HStack {
                            Text("Valoración")
                            Spacer()
                            RatingStars(rating: rating)
                        }
                    }

                    TextField("Mejor fecha (opcional)", text: $bestDate)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }

                // 🆕 Acceso
                Section(header: Text("Acceso (opcional)")) {
                    TextEditor(text: $acceso)
                        .frame(minHeight: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3))
                        )
                }

                // 🆕 Ubicación editable
                Section(header: Text("Ubicación")) {
                    LabeledContent("Latitud") {
                        TextField("Ej. 40.4168", text: $latitudeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                    LabeledContent("Longitud") {
                        TextField("Ej. -3.7038", text: $longitudeText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Editar spot")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading:
                    Button("Cancelar") { dismiss() }
                        .disabled(isSaving),
                trailing:
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Guardar").bold() }
                    }
                    .disabled(!canSave || isSaving)
            )
        }
        // 🔹 Diálogo de selección fuente
        .confirmationDialog("Elegir foto", isPresented: $showSourceDialog, titleVisibility: .visible) {
            Button("Cámara") { pickerSource = .camera; showingImagePicker = true }
            Button("Carrete") { pickerSource = .library; showingImagePicker = true }
            Button("Cancelar", role: .cancel) { }
        }
        // 🔹 Picker real
        .sheet(isPresented: $showingImagePicker) {
            ImagePickerController(source: pickerSource, allowsEditing: true) { image in
                self.pickedImage = image
                self.removeExistingImage = false
            }
        }
        .keyboardDismissToolbar()
    }

    // MARK: - Preview de foto
    @ViewBuilder
    private var photoPreview: some View {
        if let uiImg = pickedImage {
            Image(uiImage: uiImg)
                .resizable()
                .scaledToFill()
        } else if let urlStr = spot.imageUrl, !urlStr.isEmpty, !removeExistingImage, let url = URL(string: urlStr) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                case .failure(_):
                    ZStack {
                        Color.gray.opacity(0.15)
                        Image(systemName: "photo").font(.largeTitle).foregroundColor(.gray)
                    }
                default:
                    ZStack {
                        Color.gray.opacity(0.15)
                        ProgressView()
                    }
                }
            }
        } else {
            ZStack {
                Color.gray.opacity(0.15)
                Image(systemName: "photo").font(.largeTitle).foregroundColor(.gray)
            }
        }
    }

    // MARK: - Helpers
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() async {
        guard canSave else { return }
        isSaving = true
        defer { isSaving = false }

        var updated = spot
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.category = selectedCategory
        updated.rating = rating
        let best = bestDate.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.bestDate = best.isEmpty ? nil : best
        updated.acceso = acceso.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : acceso

        // 🆕 Parsear coordenadas
        let lat = Double(latitudeText.replacingOccurrences(of: ",", with: ".")) ?? spot.latitude
        let lon = Double(longitudeText.replacingOccurrences(of: ",", with: ".")) ?? spot.longitude
        updated.latitude = lat
        updated.longitude = lon
        let oldImageUrl = spot.imageUrl

        // 1) Subir imagen si hay nueva
        if let img = pickedImage {
            do {
                let url = try await uploadImageForSpot(id: spot.id, image: img)
                if let old = oldImageUrl, !old.isEmpty {
                    await ImageCache.shared.remove(for: old)
                }
                updated.imageUrl = url
            } catch {
                await MainActor.run {
                    errorText = "Error al subir la imagen: \(error.localizedDescription)"
                }
                return
            }
        } else if removeExistingImage {
            // Borrar foto existente en Storage
            if let urlStr = spot.imageUrl, !urlStr.isEmpty {
                let ref = Storage.storage().reference(forURL: urlStr)
                try? await ref.delete()
                await ImageCache.shared.remove(for: urlStr)
            }
            updated.imageUrl = nil
        }

        // 2) Actualizar Firestore
        do {
            try await spotsVM.updateSpot(updated)
            await MainActor.run {
                onSaved?(updated)
                dismiss()
            }
        } catch {
            await MainActor.run {
                errorText = "Error al actualizar el spot: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Firebase Storage
    private func uploadImageForSpot(id: String, image: UIImage) async throws -> String {
        guard let data = image.jpegData(compressionQuality: 0.75) else {
            throw NSError(domain: "SpotEdit", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo convertir la imagen"])
        }

        let storage = Storage.storage()
        let filename = "main_\(Int(Date().timeIntervalSince1970)).jpg"
        let ref = storage.reference().child("spots/\(id)/\(filename)")


        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ref.putData(data, metadata: meta) { _, err in
                if let err { cont.resume(throwing: err) } else { cont.resume() }
            }
        }

        let url: URL = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            ref.downloadURL { url, err in
                if let err { cont.resume(throwing: err) }
                else if let url { cont.resume(returning: url) }
                else { cont.resume(throwing: URLError(.badURL)) }
            }
        }

        return url.absoluteString
    }
}

// Reutilizamos tus estrellas
private struct RatingStars: View {
    let rating: Int
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < rating ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
        }
    }
}
