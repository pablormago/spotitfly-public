//
//  SpotRow.swift
//  Spots
//

import SwiftUI
import CoreLocation
import FirebaseFirestore
import UIKit // 👈 para UIPasteboard si hiciera falta



struct SpotRow: View {
    let spot: Spot
    let userCoordinate: CLLocationCoordinate2D?
    var onOpenDirections: () -> Void
    // 👇 nueva (opcional, con valor por defecto para no romper otros llamadores)
    var onShare: (() -> Void)? = nil
    var onViewOnMap: (() -> Void)? = nil
    
    @EnvironmentObject var favoritesVM: FavoritesViewModel
    
    private let thumbSize: CGFloat = 96
    
    private var distanceText: String? {
        guard let userCoordinate else { return nil }
        let user = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        let here = CLLocation(latitude: spot.latitude, longitude: spot.longitude)
        let d = here.distance(from: user)
        return d >= 1000 ? String(format: "%.1f km", d/1000.0) : "\(Int(d)) m"
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Fila principal: miniatura + textos
            HStack(alignment: .top, spacing: 14) {
                SpotThumb(urlString: spot.imageUrl, width: thumbSize, height: thumbSize)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text(spot.name)
                        .font(.headline)
                        .foregroundColor(.black)        // fijo negro
                    
                    Text(spot.description)
                        .font(.subheadline)
                        .foregroundColor(.gray)         // fijo gris
                        .lineLimit(3)
                    
                    HStack {
                        // Estrellas (y posible media) con prioridad de layout para evitar truncados
                        StaticStarRatingView(average: spot.ratingMean, maxStars: 5, starSize: 14)
                            .layoutPriority(1)

                        Spacer() // Empuja el grupo derecho

                        // Grupo derecho: "Ver" pegado al corazón
                        HStack(spacing: 8) {
                            Button {
                                onViewOnMap?()
                            } label: {
                                Text("Ver Mapa")
                                    .font(.subheadline.bold())
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .foregroundColor(.blue)
                                    .background(Color.blue.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .accessibilityLabel("Ver en mapa")
                            }
                            .buttonStyle(.plain)
                            .fixedSize() // No ocupa más ancho del necesario

                            let isFav = favoritesVM.favoriteIds.contains(spot.id)
                            Button {
                                Task { await favoritesVM.toggleFavorite(spot: spot) }
                            } label: {
                                Image(systemName: isFav ? "heart.fill" : "heart")
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(isFav ? .red : .gray)
                            }
                            .buttonStyle(.plain)
                        }
                    }


                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            // 🔹 Pill + contador ALINEADOS AL BORDE IZDO DE LA FOTO (sin padding extra)
            HStack(spacing: 8) {
                SpotWeatherCompact(lat: spot.latitude, lon: spot.longitude)
                    .layoutPriority(1)
                
                Spacer(minLength: 8)
                
                // 🔗 botón compartir (entre tiempo y comentarios)
                Button {
                    if let onShare { onShare() }
                    else {
                        // Fallback: copiar enlace si no nos pasan closure
                        let url = "spots://spot/\(spot.id)?lat=\(spot.latitude)&lon=\(spot.longitude)"
                        UIPasteboard.general.string = url
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 28, height: 28)
                        .foregroundColor(.blue)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .accessibilityLabel("Compartir spot")
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                CommentCountView(spotId: spot.id, initialCount: spot.commentCount ?? 0)
                    .layoutPriority(0)
            }
            .padding(.top, 2)
            
            
            HStack(spacing: 10) {
                CategoryChip(category: spot.category)
                Spacer()
                if let distanceText { DistanceBadge(text: distanceText) }
            }
            
            HStack(spacing: 10) {
                if let loc = spot.locality, !loc.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.circle")
                        Text(loc)
                    }
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                }
                Spacer()
                Button(action: onOpenDirections) {
                    Label("Ir", systemImage: "car.fill")
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.purple)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white)
                .shadow(color: Color.black.opacity(0.08), radius: 6, x: 0, y: 2)
        )
    }
}


// MARK: - Thumb con caché
struct SpotThumb: View {
    let urlString: String?
    let width: CGFloat
    let height: CGFloat
    
    @State private var image: UIImage? = nil
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray.opacity(0.15))
            
            if let uiImage = image {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .cornerRadius(12)
            } else if isLoading {
                ProgressView()
                    .frame(width: width, height: height)
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .cornerRadius(12)
        .shadow(radius: 1)
        .task(id: urlString) { image = nil; await loadImage() }
    }
    
    private var placeholder: some View {
        ZStack {
            Color.clear
            Image("dronePlaceholder")
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .foregroundColor(.gray)
        }
        .frame(width: width, height: height)
    }
    
    private func loadImage() async {
        guard let urlString, !urlString.isEmpty else { return }
        //if image != nil { return }
        isLoading = true
        defer { isLoading = false }
        
        if let cached = await ImageCache.shared.image(for: urlString) {
            await MainActor.run { self.image = cached }
        }
    }
}

// MARK: - Contador de comentarios fiable
struct CommentCountView: View {
    let spotId: String
    @State private var count: Int
    @State private var loaded = false
    
    init(spotId: String, initialCount: Int) {
        self.spotId = spotId
        _count = State(initialValue: initialCount)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bubble.left")
                .font(.caption)
                .foregroundColor(.gray)
            Text("\(count)")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .onAppear {
            if !loaded { Task { await loadCount() } }
        }
        .task(id: spotId) {
            await loadCount()
        }
        .onReceive(NotificationCenter.default.publisher(for: .commentsDidChange)) { _ in
            Task { await loadCount() }
        }
    }
    
    private func loadCount() async {
        defer { loaded = true }
        let ref = Firestore.firestore()
            .collection("spots").document(spotId)
            .collection("comments")
        
        do {
            let snap = try await ref.count.getAggregation(source: .server)
            if let n = snap.count as? NSNumber {
                await MainActor.run { self.count = n.intValue }
                return
            }
        } catch {
            do {
                let docs = try await ref.getDocuments()
                await MainActor.run { self.count = docs.documents.count }
            } catch {
                await MainActor.run { self.count = 0 }
            }
        }
    }
}

// MARK: - Chips auxiliares
struct CategoryChip: View {
    let category: SpotCategory
    var body: some View {
        Text(category.rawValue)
            .font(.caption2)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundColor(.blue)
            .background(Color.blue.opacity(0.12))
            .cornerRadius(8)
    }
}

struct DistanceBadge: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundColor(.gray)
            .background(Color.gray.opacity(0.12))
            .cornerRadius(10)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }
}
