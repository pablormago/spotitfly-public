//
//  PickedFile.swift
//  Spots
//
//  Created by Pablo Jimenez on 29/9/25.
//


//
//  FilePicker.swift
//  Spots
//
//  Created by Pablo Jimenez on 30/9/25.
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Modelo del archivo seleccionado
struct PickedFile: Identifiable {
    let id = UUID()
    let url: URL?
    let data: Data?
    let fileName: String
    let fileSize: Int64
    let mimeType: String?
}

// MARK: - Tipos de picker
enum FileType {
    case photoVideo
    case document
}

// MARK: - FilePickerController
struct FilePickerController: UIViewControllerRepresentable {
    let type: FileType
    let onPicked: (PickedFile?) -> Void
    
    func makeUIViewController(context: Context) -> UIViewController {
        switch type {
        case .photoVideo:
            var config = PHPickerConfiguration(photoLibrary: .shared())
            config.filter = .any(of: [.images, .videos])
            config.selectionLimit = 1
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = context.coordinator
            return picker
            
        case .document:
            let supportedTypes: [UTType] = [
                .item, .content, .data, .image, .movie, .pdf
            ]
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes, asCopy: true)
            picker.delegate = context.coordinator
            picker.allowsMultipleSelection = false
            return picker
        }
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    // MARK: - Coordinator
    class Coordinator: NSObject, PHPickerViewControllerDelegate, UIDocumentPickerDelegate {
        let parent: FilePickerController
        init(_ parent: FilePickerController) { self.parent = parent }
        
        // PHPicker (fotos/vídeos)
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let item = results.first else {
                parent.onPicked(nil)
                return
            }
            
            if item.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                item.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data, let fileName = item.itemProvider.suggestedName {
                        let file = PickedFile(
                            url: nil,
                            data: data,
                            fileName: fileName,
                            fileSize: Int64(data.count),
                            mimeType: "image/jpeg"
                        )
                        DispatchQueue.main.async { self.parent.onPicked(file) }
                    }
                }
            } else if item.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                item.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                    if let url {
                        let file = self.makePickedFile(from: url)
                        DispatchQueue.main.async { self.parent.onPicked(file) }
                    }
                }
            }
        }
        
        // UIDocumentPicker (otros archivos)
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                parent.onPicked(nil)
                return
            }
            let file = makePickedFile(from: url)
            parent.onPicked(file)
        }
        
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onPicked(nil)
        }
        
        // Helpers
        private func makePickedFile(from url: URL) -> PickedFile {
            let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .localizedNameKey, .typeIdentifierKey])
            let fileName = resourceValues?.localizedName ?? url.lastPathComponent
            let fileSize = Int64(resourceValues?.fileSize ?? 0)
            let uti = resourceValues?.typeIdentifier
            return PickedFile(
                url: url,
                data: try? Data(contentsOf: url),
                fileName: fileName,
                fileSize: fileSize,
                mimeType: uti
            )
        }
    }
}
