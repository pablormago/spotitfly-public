//
//  ImagePickerController.swift
//  Spots
//
//  Created by Pablo Jimenez on 25/9/25.
//


import SwiftUI
import UIKit

struct ImagePickerController: UIViewControllerRepresentable {
    enum Source { case camera, library }

    @Environment(\.dismiss) private var dismiss
    let source: Source
    let allowsEditing: Bool
    let onImagePicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.delegate = context.coordinator
        vc.allowsEditing = allowsEditing
        vc.sourceType = (source == .camera && UIImagePickerController.isSourceTypeAvailable(.camera))
            ? .camera : .photoLibrary
        vc.modalPresentationStyle = .fullScreen
        return vc
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: ImagePickerController
        init(_ parent: ImagePickerController) { self.parent = parent }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let key: UIImagePickerController.InfoKey = parent.allowsEditing ? .editedImage : .originalImage
            if let img = info[key] as? UIImage {
                parent.onImagePicked(img)
            }
            parent.dismiss()
        }
    }
}
