//
//  GoogleMapsImportButton.swift
//  Spots
//
//  Created by Pablo Jimenez on 8/10/25.
//


// MARK: - GoogleMapsImportButton.swift
//  Spots
//
//  Botón circular rojo con el logo de Google Maps en blanco.
//  Ideal para abrir la vista AdminImportGMapsView().

import SwiftUI

struct GoogleMapsImportButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.red)
                    .frame(width: 64, height: 64)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 2, y: 2)

                Image(systemName: "mappin.and.ellipse")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundColor(.white)
                    .offset(y: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Importar desde Google Maps")
    }
}

#Preview {
    GoogleMapsImportButton {
        print("Importar desde Google Maps")
    }
    .padding()
    .background(Color(.systemBackground))
}
