//
//  AsyncImageLoader.swift
//  Spots
//

import SwiftUI
import UIKit

/// Un cargador de imágenes asíncrono con soporte para caché (`ImageCache`)
/// y bust token para forzar recarga cuando cambia la URL.
struct AsyncImageLoader<Content: View, Placeholder: View>: View {
    let urlString: String
    let bustToken: String
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var uiImage: UIImage? = nil
    @State private var isLoading = false

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
                    .transition(.opacity) // 🔹 animación de aparición
            } else {
                placeholder()
                    .task {
                        await loadImage()
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: uiImage) // 🔹 crossfade suave
        .id(bustToken) // 🔹 recarga cuando cambia bustToken
    }

    private func loadImage() async {
        guard !isLoading else { return }
        isLoading = true

        // ✅ Primero intentamos caché
        if let cached = await ImageCache.shared.cachedImage(for: urlString) {
            await MainActor.run { self.uiImage = cached }
            isLoading = false
            return
        }

        // 🔄 Si no está, descargamos
        if let img = await ImageCache.shared.image(for: urlString) {
            await MainActor.run { self.uiImage = img }
        }

        isLoading = false
    }
}
