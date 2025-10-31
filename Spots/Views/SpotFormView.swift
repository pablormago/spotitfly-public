import SwiftUI
import FirebaseStorage
import CoreLocation

struct SpotFormView: View {
    // Callbacks
    var onSaved: ((Spot) -> Void)? = nil

    // Entorno
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var spotsVM: SpotsViewModel
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var userSession: UserSession

    // Campos del formulario
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var selectedCategory: SpotCategory = .otros
    @State private var rating: Int = 0
    @State private var bestDate: String = ""
    @State private var acceso: String = ""   // 🆕 Campo acceso
    @State private var latitudeText: String = ""
    @State private var longitudeText: String = ""

    // Imagen (opcional)
    @State private var pickedImage: UIImage? = nil
    @State private var showingImagePicker = false
    @State private var showSourceDialog = false
    @State private var pickerSource: ImagePickerController.Source = .library
    @State private var uploadedPath: String? = nil   // 🆕 Para borrar si se elimina

    // Guardado
    @State private var isSaving: Bool = false
    @State private var errorText: String?

    var body: some View {
        NavigationView {
            Form {
                // === Imagen primero ===
                Section(header: Text("Imagen (opcional)")) {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.gray.opacity(0.15))
                                .frame(width: 88, height: 88)
                            if let ui = pickedImage {
                                Image(uiImage: ui)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .clipped()
                                    .cornerRadius(10)
                            } else {
                                Image(systemName: "photo")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 34, height: 34)
                                    .foregroundColor(.gray)
                            }
                        }

                        Button {
                            showSourceDialog = true
                        } label: {
                            Label(pickedImage == nil ? "Seleccionar foto" : "Cambiar foto",
                                  systemImage: "photo.on.rectangle")
                        }

                        if pickedImage != nil {
                            Button(role: .destructive) {
                                Task { await removeImageFromStorageIfNeeded() }
                                pickedImage = nil
                            } label: {
                                Label("Quitar", systemImage: "trash")
                            }
                        }
                    }
                }

                // === Detalles ===
                Section(header: Text("Detalles")) {
                    TextField("Nombre del spot", text: $name)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)

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

                // === Acceso ===
                Section(header: Text("Acceso (opcional)")) {
                    TextEditor(text: $acceso)
                        .frame(minHeight: 80)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3))
                        )
                }

                // === Ubicación ===
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

                    let center = locationManager.region.center
                    let latPreview = Double(latitudeText.replacingOccurrences(of: ",", with: ".")) ?? center.latitude
                    let lonPreview = Double(longitudeText.replacingOccurrences(of: ",", with: ".")) ?? center.longitude
                    LocalityLabel(latitude: latPreview, longitude: lonPreview)
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }
            }
            .disabled(isSaving)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Nuevo spot")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading:
                    Button("Cancelar") {
                        Task { await removeImageFromStorageIfNeeded() }
                        dismiss()
                    }
                    .disabled(isSaving),
                trailing:
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("Guardar").bold() }
                    }
                    .disabled(!canSave || isSaving)
            )
            .onAppear {
                let center = locationManager.region.center
                latitudeText = String(format: "%.5f", center.latitude)
                longitudeText = String(format: "%.5f", center.longitude)
            }
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
            }
        }
        .keyboardDismissToolbar()
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Guardar
    private func save() async {
        guard canSave else { return }
        isSaving = true
        errorText = nil

        let center = locationManager.region.center
        let lat = Double(latitudeText.replacingOccurrences(of: ",", with: ".")) ?? center.latitude
        let lon = Double(longitudeText.replacingOccurrences(of: ",", with: ".")) ?? center.longitude

        var imageURL: String? = nil
        if let img = pickedImage {
            do {
                (imageURL, uploadedPath) = try await uploadImage(img)
            } catch {
                errorText = "No se pudo subir la imagen."
                isSaving = false
                return
            }
        }

        do {
            try await spotsVM.addSpot(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                latitude: lat,
                longitude: lon,
                rating: rating,
                bestDate: bestDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : bestDate,
                category: selectedCategory,
                imageUrl: imageURL,
                acceso: acceso.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : acceso
            )

            let temp = Spot(
                id: UUID().uuidString,
                name: name,
                description: description,
                latitude: lat,
                longitude: lon,
                rating: rating,
                bestDate: bestDate.isEmpty ? nil : bestDate,
                category: selectedCategory,
                imageUrl: imageURL,
                createdBy: userSession.uid ?? "",
                createdAt: Date(),
                locality: nil,
                acceso: acceso.isEmpty ? nil : acceso
            )
            onSaved?(temp)

            dismiss()
        } catch {
            errorText = "No se pudo guardar el spot."
        }

        isSaving = false
    }

    // MARK: - Storage
    private func uploadImage(_ image: UIImage) async throws -> (String?, String?) {
        guard let data = image.jpegData(compressionQuality: 0.75) else { return (nil, nil) }
        let fileId = UUID().uuidString
        let path = "spots/\(fileId).jpg"
        let ref = Storage.storage().reference().child(path)

        _ = try await ref.putDataAsync(data)
        let url = try await ref.downloadURL()
        return (url.absoluteString, path)
    }

    private func removeImageFromStorageIfNeeded() async {
        guard let path = uploadedPath else { return }
        do {
            try await Storage.storage().reference().child(path).delete()
            uploadedPath = nil
        } catch {
            print("⚠️ Error borrando imagen no usada:", error.localizedDescription)
        }
    }
}

// Reutilizamos las estrellas
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
