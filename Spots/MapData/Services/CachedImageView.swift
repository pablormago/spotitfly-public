//
//  CachedImageView.swift
//  Spots
//
//  Created by Pablo Jimenez on 15/9/25.
//

import SwiftUI
import UIKit

/// Imagen con caché en memoria + disco.
/// Uso: `CachedImageView(urlString: spot.imageUrl, height: 220)`
struct CachedImageView: View {
    let urlString: String?
    var height: CGFloat
    var cornerRadius: CGFloat = 12

    @State private var uiImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            // placeholder
            Rectangle()
                .fill(Color.gray.opacity(0.18))
                .frame(height: height)
                .cornerRadius(cornerRadius)

            if let ui = uiImage {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .cornerRadius(cornerRadius)
                    .transition(.opacity) // 🔹 transición suave
            } else if isLoading {
                ProgressView()
            }
        }
        .shadow(radius: 4)
        .animation(.easeInOut(duration: 0.25), value: uiImage) // 🔹 crossfade
        .onAppear {
            // 1) Intenta instantáneo (memoria o disco)
            if let urlString, let cached = ImageCache.shared.cachedImage(for: urlString) {
                self.uiImage = cached
            }
        }
        .task(id: urlString ?? "nil") {
            // 2) Si aún no hay imagen, descarga/obtén del cache actor
            guard uiImage == nil, !isLoading else { return }
            guard let urlString, !urlString.isEmpty else { return }
            isLoading = true
            uiImage = await ImageCache.shared.image(for: urlString)
            isLoading = false
        }
    }
}
