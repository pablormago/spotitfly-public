//
//  YouTubePreviewView.swift
//  Spots
//
//  Created by Pablo Jimenez on 25/9/25.
//

import SwiftUI

struct YouTubePreviewView: View {
    let url: URL
    let videoID: String

    var body: some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                // 📺 Thumbnail más grande
                AsyncImage(url: URL(string: "https://img.youtube.com/vi/\(videoID)/hqdefault.jpg")) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .scaledToFill()
                            .frame(height: 200)   // 👈 aumentado para destacar
                            .clipped()
                            .cornerRadius(10)
                    default:
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                            .background(Color.gray.opacity(0.2))
                            .cornerRadius(10)
                    }
                }

                // 📝 Título + link debajo
                VStack(alignment: .leading, spacing: 4) {
                    Text("YouTube Video")
                        .font(.headline)
                        .foregroundColor(.primary)
                        .lineLimit(2)

                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
