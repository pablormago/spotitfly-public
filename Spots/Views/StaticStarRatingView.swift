//
//  StaticStarRatingView.swift
//  Spots
//
//  Created by Pablo Jimenez on 26/9/25.
//

import SwiftUI

/// Vista no interactiva para mostrar la media de votos
struct StaticStarRatingView: View {
    let average: Double
    var maxStars: Int = 5             // 👈 por defecto 5
    var starSize: CGFloat = 14        // 👈 tamaño configurable
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<maxStars, id: \.self) { i in
                Image(systemName: i < Int(round(average)) ? "star.fill" : "star")
                    .resizable()
                    .scaledToFit()
                    .frame(width: starSize, height: starSize)
                    .foregroundColor(.yellow)
            }
            
            Text(String(format: "%.1f", average))
                .font(.system(size: starSize * 0.8, weight: .bold))
                .foregroundColor(.secondary)
        }
    }
}
