// MARK: - AdminImportGMapsView.swift
//  Spots
//
//  Vista principal de importación admin (pantalla completa).
//  Con FileImporter seguro (security-scoped + copia a tmp) y miniaturas.

import SwiftUI
import FirebaseAuth

// MARK: - PhotoSelectorView
struct PhotoSelectorView: View {
    @Binding var photos: [String]
    @Binding var selectedIndex: Int?  // nil = ninguna
    

    var body: some View {
        Group {
            if photos.isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.08))
                        .frame(width: 88, height: 88)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4]))
                                .foregroundColor(.secondary.opacity(0.4))
                        )
                    VStack(spacing: 4) {
                        Image(systemName: "photo.slash")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text("Sin foto")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } else if photos.count == 1 {
                if let url = URL(string: photos[0]) {
                    ZStack(alignment: .topTrailing) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 88, height: 88)
                                .clipped()
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.2))
                                )
                        } placeholder: {
                            ProgressView().frame(width: 88, height: 88)
                        }
                        Button {
                            photos = []
                            selectedIndex = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.red)
                                .shadow(radius: 2)
                                .padding(6)
                        }
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(0..<photos.count, id: \.self) { idx in
                            if let url = URL(string: photos[idx]) {
                                ZStack(alignment: .topTrailing) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 88, height: 88)
                                            .clipped()
                                            .cornerRadius(8)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(
                                                        (selectedIndex ?? -1) == idx ? Color.green : Color.secondary.opacity(0.2),
                                                        lineWidth: (selectedIndex ?? -1) == idx ? 3 : 1
                                                    )
                                            )
                                    } placeholder: {
                                        ProgressView().frame(width: 88, height: 88)
                                    }

                                    if (selectedIndex ?? -1) == idx {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.green)
                                            .shadow(radius: 2)
                                            .padding(6)
                                    }
                                }
                                .onTapGesture {
                                    selectedIndex = (selectedIndex == idx) ? nil : idx
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(height: 96)
            }
        }
        .frame(minWidth: 88, alignment: .leading)
    }
}

// MARK: - CandidateRowView
struct CandidateRowView: View {
    @Binding var cand: AdminImportViewModel.ImportCandidate

    var body: some View {
        HStack(alignment: .top, spacing: 10) {

            PhotoSelectorView(
                photos: $cand.photos,
                selectedIndex: $cand.selectedPhotoIndex
            )

            VStack(alignment: .leading, spacing: 4) {
                TextField("Nombre", text: $cand.name)
                    .font(.headline)
                TextField("Descripción", text: $cand.description)
                    .font(.subheadline)

                Picker("Categoría", selection: $cand.category) {
                    ForEach(SpotCategory.allCases, id: \.self) { cat in
                        Text(cat.rawValue.capitalized).tag(cat)
                    }
                }
                .pickerStyle(.menu)

                if let loc = cand.locality {
                    Text("📍 \(loc)").font(.caption)
                }

                if let idx = cand.selectedPhotoIndex,
                   cand.photos.indices.contains(idx) {
                    Text(cand.photos[idx])
                        .font(.caption2)
                        .foregroundColor(.gray)
                } else {
                    Text("— Sin foto seleccionada —")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}



struct AdminImportGMapsView: View {
    @StateObject private var vm = AdminImportViewModel()
    @EnvironmentObject var spotsVM: SpotsViewModel
    @State private var showingPicker = false
    @State private var selectedFileURL: URL?
    @State private var exportURL: URL?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Encabezado
                VStack {
                    Text("Importador de Spots (Admin)")
                        .font(.title2.bold())
                    if let user = Auth.auth().currentUser {
                        Text("Usuario logado: \(user.email ?? user.uid)")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    } else {
                        Text("⚠️ No hay usuario autenticado")
                            .foregroundColor(.red)
                    }
                }
                
                // Picker categoría
                Picker("Categoría por defecto", selection: $vm.selectedCategory) {
                    ForEach(SpotCategory.allCases, id: \.self) { cat in
                        Text(cat.rawValue.capitalized).tag(cat)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Botón cargar JSON
                Button {
                    showingPicker = true
                } label: {
                    Label("Seleccionar JSON de Google Maps", systemImage: "doc")
                        .font(.headline)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(10)
                }
                .fileImporter(isPresented: $showingPicker,
                              allowedContentTypes: [.json]) { result in
                    switch result {
                    case .success(let url):
                        // ✅ Security-scoped access + copia al sandbox tmp
                        let shouldStop = url.startAccessingSecurityScopedResource()
                        defer { if shouldStop { url.stopAccessingSecurityScopedResource() } }
                        
                        do {
                            let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                            if FileManager.default.fileExists(atPath: tmpURL.path) {
                                try? FileManager.default.removeItem(at: tmpURL)
                            }
                            try FileManager.default.copyItem(at: url, to: tmpURL)
                            
                            selectedFileURL = tmpURL
                            Task { await vm.loadJSON(from: tmpURL) }
                        } catch {
                            vm.errorMessage = "Error al preparar el archivo: \(error.localizedDescription)"
                        }
                        
                    case .failure(let err):
                        vm.errorMessage = err.localizedDescription
                    }
                }
                
                if let file = vm.fileName {
                    Text("📂 \(file)").font(.footnote)
                }
                
                if vm.isLoading {
                    ProgressView(vm.progressText)
                        .padding(.vertical)
                }
                
                List {
                    ForEach(Array(vm.candidates.indices), id: \.self) { i in
                        CandidateRowView(cand: $vm.candidates[i])
                    }
                }
                
                Spacer()
                
                if !vm.candidates.isEmpty {
                    VStack(spacing: 10) {
                        Button {
                            Task { await vm.importAll(using: spotsVM) }
                        } label: {
                            Label("Subir a Firestore", systemImage: "icloud.and.arrow.up")
                                .font(.headline)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(10)
                        }
                        
                        if let url = exportURL {
                            ShareLink(item: url) {
                                Label("Compartir JSON limpio", systemImage: "square.and.arrow.up")
                                    .font(.subheadline)
                            }
                        } else {
                            Button {
                                exportJSON()
                            } label: {
                                Label("Exportar JSON limpio", systemImage: "square.and.arrow.down")
                                    .font(.subheadline)
                            }
                        }
                        // Estado de la importación
                        if let succeeded = vm.importSucceeded {
                            if succeeded {
                                VStack(spacing: 6) {
                                    Label("Importación completada", systemImage: "checkmark.seal.fill")
                                        .foregroundColor(.green)
                                        .font(.subheadline.bold())
                                    Text("Spots importados: \(vm.importedCount)")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                    if let msg = vm.importError {
                                        Text(msg)
                                            .font(.footnote)
                                            .foregroundColor(.orange)
                                    }
                                }
                                .padding(.vertical, 6)
                            } else {
                                VStack(spacing: 6) {
                                    Label("Importación fallida", systemImage: "xmark.octagon.fill")
                                        .foregroundColor(.red)
                                        .font(.subheadline.bold())
                                    Text(vm.importError ?? "Ha ocurrido un error")
                                        .font(.footnote)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 6)
                            }
                        }


                    }
                    .padding(.horizontal)
                }
                
                if let err = vm.errorMessage {
                    Text("⚠️ \(err)").foregroundColor(.red)
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .keyboardDismissToolbar() // ✅ barra sobre el teclado con botón “Ocultar”
        }
    }
    
    // MARK: - Exportar
    func exportJSON() {
        struct ExportSpot: Codable {
            let name: String
            let description: String
            let latitude: Double
            let longitude: Double
            let category: String
            let imageUrl: String?
            let locality: String?
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let exportable: [ExportSpot] = vm.candidates.map {
            ExportSpot(
                name: $0.name,
                description: $0.description,
                latitude: $0.latitude,
                longitude: $0.longitude,
                category: $0.category.rawValue,
                imageUrl: $0.selectedImageUrl,
                locality: $0.locality
            )
        }

        if let data = try? encoder.encode(exportable),
           let tmpURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
                .appendingPathComponent("spots_clean.json") {
            do {
                try data.write(to: tmpURL)
                exportURL = tmpURL            // ✅ guardamos para ShareLink
                print("✅ Exportado a \(tmpURL.path)")
            } catch {
                print("⚠️ Error al guardar JSON limpio: \(error.localizedDescription)")
            }
        }
    }

}
