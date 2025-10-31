//
//  EnhancedFilePreviewController.swift
//  Spots
//

import SwiftUI
import QuickLook
import Photos

struct EnhancedFilePreviewController: UIViewControllerRepresentable {
    let url: URL
    let mimeType: String?

    func makeUIViewController(context: Context) -> UINavigationController {
        let ql = QLPreviewController()
        ql.dataSource = context.coordinator

        // 🔹 Añadimos un botón de acción en la barra
        let nav = UINavigationController(rootViewController: ql)
        ql.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .action,
            target: context.coordinator,
            action: #selector(context.coordinator.shareFile)
        )
        context.coordinator.parentVC = ql
        return nav
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url, mimeType: mimeType)
    }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        let mimeType: String?
        weak var parentVC: UIViewController?

        init(url: URL, mimeType: String?) {
            self.url = url
            self.mimeType = mimeType
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            return url as NSURL
        }

        // 🔹 Acción de guardar/compartir
        @objc func shareFile() {
            if mimeType?.starts(with: "image") == true {
                saveImageToPhotos(url: url)
            } else if mimeType?.starts(with: "video") == true {
                saveVideoToPhotos(url: url)
            } else {
                let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                parentVC?.present(activityVC, animated: true)
            }
        }

        private func saveImageToPhotos(url: URL) {
            if let img = UIImage(contentsOfFile: url.path) {
                PHPhotoLibrary.requestAuthorization { status in
                    if status == .authorized || status == .limited {
                        UIImageWriteToSavedPhotosAlbum(img, nil, nil, nil)
                    }
                }
            }
        }

        private func saveVideoToPhotos(url: URL) {
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized || status == .limited {
                    UISaveVideoAtPathToSavedPhotosAlbum(url.path, nil, nil, nil)
                }
            }
        }
    }
}
