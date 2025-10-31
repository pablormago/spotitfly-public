//
//  RatingView.swift
//  Spots
//
//  Created by Pablo Jimenez on 6/9/25.
//


import SwiftUI

struct RatingView: View {
    @Binding var rating: Int
    private let maxRating = 5
    
    var body: some View {
        HStack {
            ForEach(1...maxRating, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundColor(.yellow)
                    .font(.title2)
                    .onTapGesture {
                        rating = star
                    }
            }
        }
    }
}
