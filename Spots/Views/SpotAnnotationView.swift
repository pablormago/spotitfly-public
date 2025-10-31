//
//  SpotAnnotationView.swift
//  Spots
//

import SwiftUI
import MapKit

struct SpotAnnotationView: View {
    let spot: Spot
    let scale: CGFloat
    let onInfo: () -> Void
    let onCenter: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            // Nombre
            Button(action: onCenter) {
                Text(spot.name)
                    .font(.title3).bold()
                    .foregroundColor(.black)
                    .padding(8)
                    .background(Color.white.opacity(0.9))
                    .cornerRadius(10)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
            .padding(.bottom, -6)

            // Estrellas + media
            HStack(spacing: 4) {
                StaticStarRatingView(average: spot.ratingMean, maxStars: 5, starSize: 14)

                Text(String(format: "%.1f", spot.ratingMean))
                    .font(.headline.weight(.bold))
                    .foregroundColor(.black.opacity(0.8))
            }
            .padding(.bottom, -6)

            // Icono dron
            Button(action: onCenter) {
                Image("dronePin")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 82, height: 82)
            }
            .buttonStyle(.plain)
            .padding(.bottom, -15)

            // Botón info
            Button(action: onInfo) {
                Image(systemName: "info.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .padding(6)
                    .background(Color.white)
                    .clipShape(Circle())
                    .shadow(radius: 2)
            }
        }
        .scaleEffect(scale)
        .zIndex(100)
    }
}
