import SwiftUI
import PhotosUI
import UIKit

/// Photo of a recipe or a step: pick from the library, take one, remove.
struct PhotoField: View {
    @Environment(AppModel.self) private var model
    @Environment(\.m3) private var m3
    @Binding var name: String?
    var height: CGFloat = 160
    @State private var item: PhotosPickerItem?
    @State private var camera = false
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let name {
                StoredPhoto(name: name)
                    .frame(height: height)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        Button { self.name = nil } label: {
                            Image(systemName: "xmark.circle.fill").font(.title2).symbolRenderingMode(.palette)
                                .foregroundStyle(.white, .black.opacity(0.5))
                        }
                        .padding(8)
                        .accessibilityLabel("Rimuovi foto")
                    }
            }
            HStack(spacing: 10) {
                PhotosPicker(selection: $item, matching: .images) {
                    Label(name == nil ? "Libreria" : "Cambia", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { camera = true } label: {
                        Label("Scatta", systemImage: "camera.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                if loading { ProgressView() }
            }
        }
        .onChange(of: item) { _, newItem in
            guard let newItem else { return }
            loading = true
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    name = model.savePhoto(img)
                }
                loading = false
                item = nil
            }
        }
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { img in
                if let img { name = model.savePhoto(img) }
                camera = false
            }
            .ignoresSafeArea()
        }
    }
}

/// UIImagePickerController with the camera.
struct CameraPicker: UIViewControllerRepresentable {
    let done: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?) -> Void
        init(done: @escaping (UIImage?) -> Void) { self.done = done }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            done(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { done(nil) }
    }
}
