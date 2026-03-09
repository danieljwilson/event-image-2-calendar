import SwiftUI
import UIKit

struct CameraSheet: View {
    var onImageCaptured: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showCamera = false
    @State private var showLibrary = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 80))
                    .foregroundStyle(.tint)

                Text("Snap an event poster")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Spacer()

                VStack(spacing: 12) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        showLibrary = true
                    } label: {
                        Label("Choose from Library", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showCamera) {
                ImagePicker(sourceType: .camera, onImagePicked: { image in
                    onImageCaptured(image)
                })
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showLibrary) {
                ImagePicker(sourceType: .photoLibrary, onImagePicked: { image in
                    onImageCaptured(image)
                })
                .ignoresSafeArea()
            }
        }
    }
}

// MARK: - UIImagePickerController wrapper

struct ImagePicker: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImagePicked: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImagePicked(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
