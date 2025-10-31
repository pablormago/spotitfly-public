import SwiftUI
import PhotosUI
import UIKit

struct GroupAvatarPicker: View {
    @Binding var uiImage: UIImage?
    @State private var showSourceSheet = false
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var phItem: PhotosPickerItem?
    @State private var tempImage: UIImage?

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                if let img = uiImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color.black.opacity(0.08), lineWidth: 1))
                        .contentShape(Circle())
                        .onTapGesture { showSourceSheet = true }
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.12))
                        .frame(width: 96, height: 96)
                        .overlay(
                            Image(systemName: "camera.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .opacity(0.6)
                        )
                        .onTapGesture { showSourceSheet = true }
                }
            }

            HStack(spacing: 12) {
                Button { showSourceSheet = true } label: {
                    Label(uiImage == nil ? "Elegir foto" : "Reemplazar", systemImage: "photo.on.rectangle.angled")
                }
                .buttonStyle(.bordered)

                if uiImage != nil {
                    Button(role: .destructive) {
                        uiImage = nil
                    } label: {
                        Label("Quitar", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
        }
        .confirmationDialog("Selecciona origen", isPresented: $showSourceSheet, titleVisibility: .visible) {
            Button("Cámara") { showCamera = true }
            Button("Carrete") { showPhotoLibrary = true }   // ✅ ahora abre PhotosPicker
            Button("Cancelar", role: .cancel) { }
        }
        .sheet(isPresented: $showCamera) { CameraPicker(image: $tempImage).ignoresSafeArea() }
        .photosPicker(isPresented: $showPhotoLibrary, selection: $phItem, matching: .images) // ✅
        .onChange(of: tempImage) { _, new in
            guard let img = new else { return }
            uiImage = img.centerSquare() // recorte 1:1
            tempImage = nil
        }
        .onChange(of: phItem) { _, new in
            guard let item = new else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    uiImage = img.centerSquare() // recorte 1:1
                }
                phItem = nil
            }
        }
    }
}

// MARK: - Camera Picker (UIKit bridge)
private struct CameraPicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            let img = (info[.originalImage] as? UIImage) ?? (info[.editedImage] as? UIImage)
            parent.image = img
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Helpers
private extension UIImage {
    /// Recorta al cuadrado (centrado) sin redimensionar.
    func centerSquare() -> UIImage {
        let side = min(size.width, size.height)
        let x = (size.width - side) / 2.0
        let y = (size.height - side) / 2.0
        let rect = CGRect(x: x, y: y, width: side, height: side)
        guard let cg = self.cgImage?.cropping(to: rect.scaled(by: scale)) else { return self }
        return UIImage(cgImage: cg, scale: scale, orientation: imageOrientation)
    }
}
private extension CGRect {
    func scaled(by scale: CGFloat) -> CGRect {
        CGRect(x: origin.x * scale, y: origin.y * scale, width: size.width * scale, height: size.height * scale)
    }
}
