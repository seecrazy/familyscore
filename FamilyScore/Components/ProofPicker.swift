import SwiftUI
import PhotosUI

/// 拍照凭证选择（v2.1 需求 2）：相册 PhotosPicker + 相机（真机）；模拟器仅相册
struct ProofPicker: View {
    @Binding var imageData: Data?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showFull = false

    var body: some View {
        VStack(spacing: 8) {
            if let data = imageData, let img = UIImage(data: data) {
                Button {
                    showFull = true
                } label: {
                    Image(uiImage: img)
                        .resizable().scaledToFill()
                        .frame(height: 130)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                self.imageData = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white, .black.opacity(0.55))
                                    .padding(6)
                            }
                        }
                }
                .buttonStyle(.plain)
                .fullScreenCover(isPresented: $showFull) {
                    FullscreenImageView(image: img)
                }
            } else {
                HStack(spacing: 10) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label("相册", systemImage: "photo.on.rectangle")
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showCamera = true
                        } label: {
                            Label("拍照", systemImage: "camera.fill")
                                .font(.footnote.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 9)
                                .background(Theme.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            item.loadTransferable(type: Data.self) { result in
                if case .success(let data?) = result { imageData = data }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker(imageData: $imageData)
                .ignoresSafeArea()
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    @Binding var imageData: Data?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage {
                parent.imageData = img.jpegData(compressionQuality: 0.9)
            }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct FullscreenImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Image(uiImage: image)
                .resizable().scaledToFit()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(20)
            }
        }
        .onTapGesture { dismiss() }
    }
}
