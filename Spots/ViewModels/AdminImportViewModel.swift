// MARK: - AdminImportViewModel.swift
//  Spots
//
//  Lógica de importación y limpieza de spots desde JSON de Google Maps.
//  Con compresión + subida a Firebase Storage y pruebas con solo 1 resultado.

import Foundation
import CoreLocation
import SwiftUI
import FirebaseAuth
import UIKit
import FirebaseStorage
import MapKit

@MainActor
final class AdminImportViewModel: ObservableObject {
    
    @Published var importedCount: Int = 0
    @Published var importSucceeded: Bool? = nil   // nil: sin intentar; true/false: resultado
    @Published var importError: String? = nil

    struct ImportCandidate: Identifiable {
        let id = UUID().uuidString
        var name: String
        var description: String
        var latitude: Double
        var longitude: Double
        var address: String?
        var category: SpotCategory
        var locality: String?

        // Fotos y selección (ahora opcional para permitir "ninguna")
        var photos: [String] = []
        var selectedPhotoIndex: Int? = nil

        var selectedImageUrl: String? {
            guard let idx = selectedPhotoIndex,
                  photos.indices.contains(idx) else { return nil }
            return photos[idx]
        }

        var valid: Bool { !name.isEmpty && !description.isEmpty && latitude != 0 && longitude != 0 }
    }



    @Published var candidates: [ImportCandidate] = []
    @Published var selectedCategory: SpotCategory = .otros
    @Published var isLoading: Bool = false
    @Published var progressText: String = ""
    @Published var errorMessage: String? = nil
    @Published var fileName: String? = nil

    private let geocoder = CLGeocoder()

    // MARK: - Cargar y limpiar JSON (solo 1 resultado para pruebas)
    func loadJSON(from url: URL) async {
        isLoading = true
        progressText = "Leyendo archivo..."
        defer { isLoading = false }

        do {
            let data = try Data(contentsOf: url)
            let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let itemsAll = raw?["items"] as? [[String: Any]] ?? (raw as? [[String: Any]]) ?? []
            let items = itemsAll // ✅ todos los resultados
            //let items = Array(itemsAll.prefix(1)) // ✅ solo el primer resultado (prueba)

            var cleaned: [ImportCandidate] = []

            for item in items {
                let title = item["title"] as? String ?? ""
                let address = item["address"] as? String ?? ""
                let desc = item["description"] as? String ?? ""
                let lat = item["lat"] as? Double ?? 0
                let lng = item["lng"] as? Double ?? 0
                let photos = item["photos"] as? [String] ?? []
                let photosRaw = item["photos"] as? [String] ?? []
                let photosValid = photosRaw.filter { $0.count > 80 && !$0.contains(" ") }

                // Normalización de texto
                let titleClean = Self.cleanTitle(title)
                let addressClean = Self.cleanAddress(address)
                let descClean = Self.cleanDescription(desc)

                var candidate = ImportCandidate(
                    name: titleClean ?? "",
                    description: descClean ?? "",
                    latitude: lat,
                    longitude: lng,
                    address: addressClean,
                    category: selectedCategory,
                    locality: nil,
                    photos: photosValid,
                    selectedPhotoIndex: 0
                )

                // Autocompletar nombre/descr coherentes
                if !Self.isCoherent(text: candidate.name) {
                    candidate.name = "Spot en \(Self.coordsKey(lat, lng))"
                }
                if !Self.isCoherent(text: candidate.description) {
                    candidate.description = addressClean ?? "Un spot en \(Self.coordsKey(lat, lng))"
                }


                cleaned.append(candidate)
            }

            progressText = "Resolviendo localidades..."
            let withLocality = await resolveLocalities(for: cleaned)
            self.candidates = withLocality
            self.fileName = url.lastPathComponent
            self.progressText = "Listo (\(withLocality.count) spots)"
        } catch {
            self.errorMessage = "Error al leer JSON: \(error.localizedDescription)"
        }
    }

    // MARK: - Geocoding
    private func resolveLocalities(for list: [ImportCandidate]) async -> [ImportCandidate] {
        var result: [ImportCandidate] = []
        for var item in list {
            do {
                if let loc = try await geocoder.reverseGeocodeLocation(
                    CLLocation(latitude: item.latitude, longitude: item.longitude)
                ).first {
                    item.locality = loc.locality ?? loc.administrativeArea ?? loc.country
                    if item.name.contains("Spot en") {
                        item.name = "Spot en \(item.locality ?? "ubicación")"
                    }
                    if item.description.contains("Un spot en") {
                        item.description = "Un spot en \(item.locality ?? "ubicación")"
                    }
                }
            } catch {
                item.locality = nil
            }
            result.append(item)
        }
        return result
    }

    // MARK: - Subida a Storage con compresión
    /// Descarga la imagen desde `urlString`, la comprime con `ImageCompressor.spotData(from:)`
    /// y la sube a Firebase Storage en `spots/{spotId}.jpg`. Devuelve la downloadURL o nil.
    func uploadCompressedImageFromURL(_ urlString: String, spotId: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }

        do {
            // 1) Descargar bytes
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data) else { return nil }

            // 2) Comprimir al 75% SIN redimensionar (igual que formulario/edición)
            guard let compressed = image.jpegData(compressionQuality: 0.75) else { return nil }

            // 3) Subir a Firebase Storage
            let storage = Storage.storage()
            let ref = storage.reference(withPath: "spots/\(spotId).jpg")
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"

            try await putDataAsyncCompat(ref: ref, data: compressed, metadata: metadata)

            // 4) Obtener URL pública
            let downloadURL = try await ref.downloadURL()
            return downloadURL.absoluteString
        } catch {
            print("⚠️ uploadCompressedImageFromURL error:", error.localizedDescription)
            return nil
        }
    }


    /// Wrapper compatible para subir datos a Storage con async/await
    private func putDataAsyncCompat(ref: StorageReference, data: Data, metadata: StorageMetadata?) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ref.putData(data, metadata: metadata) { _, error in
                if let error = error {
                    cont.resume(throwing: error)
                } else {
                    cont.resume()
                }
            }
        }
    }

    // MARK: - Guardar en Firestore (solo 1 para pruebas)
    func importAll(using spotsVM: SpotsViewModel) async {
        guard let _ = Auth.auth().currentUser?.uid else {
            self.errorMessage = "No hay usuario autenticado."
            return
        }
        isLoading = true
        progressText = "Subiendo spots..."
        importedCount = 0
        importSucceeded = nil
        importError = nil

        var count = 0
        var failures = 0

        for candidate in candidates {
            do {
                let spotId = UUID().uuidString

                var finalImageURL: String? = nil
                if let srcURL = candidate.selectedImageUrl, !srcURL.isEmpty {
                    if let uploadedURL = await uploadCompressedImageFromURL(srcURL, spotId: spotId) {
                        finalImageURL = uploadedURL
                    } else {
                        finalImageURL = srcURL // fallback
                    }
                } else {
                    // Snapshot de mapa si no hay foto seleccionada; comenta esta línea si no lo quieres
                    finalImageURL = await uploadMapSnapshot(lat: candidate.latitude, lng: candidate.longitude, spotId: spotId)
                }

                try await spotsVM.addSpot(
                    name: candidate.name,
                    description: candidate.description,
                    latitude: candidate.latitude,
                    longitude: candidate.longitude,
                    rating: 0,
                    bestDate: nil,
                    category: candidate.category,
                    imageUrl: finalImageURL
                )
                count += 1
                progressText = "Subidos \(count)/\(candidates.count)"
            } catch {
                failures += 1
                print("⚠️ Error subiendo spot:", error.localizedDescription)
            }
        }

        importedCount = count
        if count > 0 && failures == 0 {
            importSucceeded = true
            progressText = "✅ Importación completada (\(count) spots)"
        } else if count > 0 && failures > 0 {
            importSucceeded = true
            importError = "Se importaron \(count) spots con \(failures) errores."
            progressText = "⚠️ Parcial: \(count) ok, \(failures) con error"
        } else {
            importSucceeded = false
            importError = "No se pudo importar ningún spot."
            progressText = "❌ Importación fallida"
        }

        isLoading = false
    }


    // MARK: - Helpers de limpieza
    static func isCoherent(text: String?) -> Bool {
        guard let t = text, !t.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if t.lowercased().starts(with: "cerca de") { return false }
        if t.count < 4 { return false }
        if t.range(of: #"^\d+$"#, options: .regularExpression) != nil { return false }
        return true
    }

    static func cleanTitle(_ s: String?) -> String? {
        guard let s else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return isCoherent(text: trimmed) ? trimmed : nil
    }

    static func cleanDescription(_ s: String?) -> String? {
        guard let s else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.range(of: #"^\d+$"#, options: .regularExpression) != nil { return nil }
        return isCoherent(text: trimmed) ? trimmed : nil
    }

    static func cleanAddress(_ s: String?) -> String? {
        guard let s else { return nil }
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().starts(with: "cerca de") ? nil : trimmed
    }

    static func coordsKey(_ lat: Double, _ lng: Double) -> String {
        String(format: "%.4f, %.4f", lat, lng)
    }
    // Snapshot del mapa con MapKit (sin APIs externas)
    private func mapSnapshotData(lat: Double, lng: Double, size: CGSize = CGSize(width: 640, height: 360), scale: CGFloat = UIScreen.main.scale) async -> Data? {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                                            latitudinalMeters: 800, longitudinalMeters: 800)
        options.size = size
        options.scale = scale
        options.mapType = .standard
        options.pointOfInterestFilter = .includingAll

        return await withCheckedContinuation { cont in
            MKMapSnapshotter(options: options).start { snapshot, error in
                guard let snapshot = snapshot, error == nil else {
                    cont.resume(returning: nil)
                    return
                }
                let image = snapshot.image
                // comprimimos con tu helper para mantener coherencia
                let data = image.jpegData(compressionQuality: 0.75)

                cont.resume(returning: data)
            }
        }
    }

    // Genera snapshot y lo sube a Storage. Devuelve downloadURL o nil.
    private func uploadMapSnapshot(lat: Double, lng: Double, spotId: String) async -> String? {
        guard let data = await mapSnapshotData(lat: lat, lng: lng) else { return nil }
        let storage = Storage.storage()
        let ref = storage.reference(withPath: "spots/\(spotId)_map.jpg")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        do {
            try await putDataAsyncCompat(ref: ref, data: data, metadata: metadata)
            let url = try await ref.downloadURL()
            return url.absoluteString
        } catch {
            print("⚠️ uploadMapSnapshot error:", error.localizedDescription)
            return nil
        }
    }

}
