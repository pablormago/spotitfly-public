//
//  AddSpotView.swift
//  Spots
//
//  Created by Pablo Jimenez on 5/9/25.
//

import SwiftUI
import FirebaseFirestore

struct AddSpotView: View {
    /// ViewModel que mantiene y refresca la lista de spots (el mismo que usas en el mapa)
    @ObservedObject var spotsVM: SpotsViewModel

    // Estado local del formulario (sin ViewModel adicional)
    @State private var name: String = ""
    @State private var description: String = ""
    @State private var latitudeText: String = ""
    @State private var longitudeText: String = ""
    @State private var errorMessage: String?
    @State private var isSaving: Bool = false

    @Environment(\.dismiss) private var dismiss
    private let db = Firestore.firestore()

    var body: some View {
        Form {
            Section(header: Text("Nuevo spot")) {
                TextField("Nombre", text: $name)
                TextField("Descripción", text: $description)
            }

            Section(header: Text("Coordenadas")) {
                TextField("Latitud", text: $latitudeText)
                    .keyboardType(.decimalPad)
                TextField("Longitud", text: $longitudeText)
                    .keyboardType(.decimalPad)
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundColor(.red)
                    .font(.footnote)
            }

            Button(action: saveSpot) {
                if isSaving {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text("Guardar spot")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(isSaving)
        }
        .navigationTitle("Añadir spot")
    }

    // MARK: - Lógica

    private func saveSpot() {
        errorMessage = nil

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "El nombre es obligatorio."
            return
        }

        guard let lat = parseCoordinate(latitudeText), (-90.0...90.0).contains(lat) else {
            errorMessage = "Latitud inválida (−90 a 90)."
            return
        }

        guard let lon = parseCoordinate(longitudeText), (-180.0...180.0).contains(lon) else {
            errorMessage = "Longitud inválida (−180 a 180)."
            return
        }

        isSaving = true

        let data: [String: Any] = [
            "name": trimmedName,
            "description": description,
            "latitude": lat,
            "longitude": lon,
            "createdAt": FieldValue.serverTimestamp()
        ]

        db.collection("spots").addDocument(data: data) { error in
            DispatchQueue.main.async {
                self.isSaving = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }
                // Refresca y cierra
                Task {
                    await self.spotsVM.fetchSpots()
                }
                self.dismiss()
            }
        }
    }

    /// Acepta comas o puntos como separador decimal
    private func parseCoordinate(_ text: String) -> Double? {
        let t = text.replacingOccurrences(of: ",", with: ".")
        return Double(t)
    }
}
