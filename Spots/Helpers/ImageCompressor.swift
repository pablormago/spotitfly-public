//
//  ImageCompressor.swift
//  Spots
//

import UIKit

enum ImageCompressor {
    /// Comprime una imagen para usarla como **avatar de perfil** (círculo pequeño).
    static func avatarData(from image: UIImage) -> Data? {
        let targetSize = CGSize(width: 300, height: 300) // suficiente para avatar
        let resized = resize(image: image, targetSize: targetSize)
        return resized.jpegData(compressionQuality: 0.7) // calidad media-alta
    }

    /// Comprime una imagen para usarla en un **Spot** (vista más grande).
    static func spotData(from image: UIImage) -> Data? {
        let targetSize = CGSize(width: 1280, height: 1280) // suficiente para galería
        let resized = resize(image: image, targetSize: targetSize)
        return resized.jpegData(compressionQuality: 0.75) // un poco más alta
    }

    /// 🔧 Redimensiona manteniendo el aspect ratio
    private static func resize(image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size

        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        let ratio = min(widthRatio, heightRatio)

        let newSize = CGSize(
            width: size.width * ratio,
            height: size.height * ratio
        )

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
