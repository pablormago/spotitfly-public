import SwiftUI
import UniformTypeIdentifiers

#if canImport(PhotosUI)
import PhotosUI
#endif

struct PickedItem {
    enum Source { case photoLibrary, files }
    var source: Source
    var data: Data?
    var fileURL: URL?
    var suggestedName: String?
    var mime: String
}

struct AttachmentPickers {
    // MARK: Photo picker (imágenes/vídeos) – devuelve Data o URL local (vídeo)
    @MainActor
    static func presentPhotoPicker(on viewController: UIViewController,
                                   completion: @escaping (PickedItem?) -> Void) {
        #if canImport(PhotosUI)
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 1
        config.filter = .any(of: [.images, .videos])

        let picker = PHPickerViewController(configuration: config)
        picker.delegate = PickerDelegate { item in
            completion(item)
        }
        viewController.present(picker, animated: true, completion: nil)
        #else
        completion(nil)
        #endif
    }

    // MARK: Files picker – devuelve URL local
    @MainActor
    static func presentDocumentPicker(on viewController: UIViewController,
                                      completion: @escaping (PickedItem?) -> Void) {
        let types: [UTType] = [.item]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        let delegate = DocDelegate { url in
            guard let url else { completion(nil); return }
            let ext = url.pathExtension
            let mime = MIME.from(fileExtension: ext)
            completion(PickedItem(source: .files, data: nil, fileURL: url, suggestedName: url.lastPathComponent, mime: mime))
        }
        picker.delegate = delegate
        // Retener delegates mientras el picker viva
        objc_setAssociatedObject(picker, &AssocKeys.docDelegate, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        viewController.present(picker, animated: true, completion: nil)
    }
}

// MARK: – Delegates internos
private enum AssocKeys { static var docDelegate = "docDelegate"; static var photoDelegate = "photoDelegate" }

#if canImport(PhotosUI)
private final class PickerDelegate: NSObject, PHPickerViewControllerDelegate {
    let completion: (PickedItem?) -> Void
    init(completion: @escaping (PickedItem?) -> Void) { self.completion = completion }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { completion(nil); return }
        let prov = result.itemProvider

        if prov.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            prov.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                DispatchQueue.main.async {
                    guard let data else { self.completion(nil); return }
                    self.completion(PickedItem(source: .photoLibrary,
                                               data: data,
                                               fileURL: nil,
                                               suggestedName: prov.suggestedName ?? "image.jpg",
                                               mime: "image/jpeg"))
                }
            }
            return
        }

        if prov.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            prov.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                DispatchQueue.main.async {
                    guard let url else { self.completion(nil); return }
                    self.completion(PickedItem(source: .photoLibrary,
                                               data: nil,
                                               fileURL: url,
                                               suggestedName: url.lastPathComponent,
                                               mime: "video/quicktime"))
                }
            }
            return
        }

        completion(nil)
    }
}
#endif

private final class DocDelegate: NSObject, UIDocumentPickerDelegate {
    let completion: (URL?) -> Void
    init(completion: @escaping (URL?) -> Void) { self.completion = completion }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        completion(nil)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion(urls.first)
    }
}
