import SwiftUI
import UIKit

struct PhotoPreview: View {
    let photo: UIImage

    private enum Preset {
        case original, fullness, definition
    }

    @State private var previews: LipPreviews?
    @State private var isLoading = true
    @State private var preset = Preset.original

    private var displayedPhoto: UIImage {
        let preview: CGImage?
        switch preset {
        case .original: preview = nil
        case .fullness: preview = previews?.fullness
        case .definition: preview = previews?.definition
        }
        return preview.map { UIImage(cgImage: $0) } ?? photo
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(uiImage: displayedPhoto)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(preset == .original ? "Original photo" : "Simulated lip preview")

            VStack(spacing: 8) {
                if let previews {
                    Picker("Lip preview", selection: $preset) {
                        Text("Original").tag(Preset.original)
                        Text("Fullness").tag(Preset.fullness)
                        if previews.definition != nil {
                            Text("Definition").tag(Preset.definition)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(preset == .original ? "Original photo" : "Simulated preview")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if isLoading {
                    ProgressView("Preparing preview…")
                } else {
                    Text("Preview unavailable. Try a straight-on photo with one face and visible lips.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: 400)
            .padding([.horizontal, .bottom], 16)
            .layoutPriority(1)
        }
        .navigationTitle("Photo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .task {
            guard isLoading else { return }
            let result = await Task.detached(priority: .userInitiated) {
                Self.makePreviews(from: photo)
            }.value
            guard !Task.isCancelled else { return }
            previews = result
            isLoading = false
        }
    }

    nonisolated private static func makePreviews(from photo: UIImage) -> LipPreviews? {
        let longestSide = max(photo.size.width, photo.size.height)
        guard longestSide > 0 else { return nil }

        // Draw the photo upright at preview size before locating the lips.
        let scale = min(1, 1_800 / longestSide)
        let size = CGSize(width: photo.size.width * scale, height: photo.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let uprightPhoto = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            photo.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let source = uprightPhoto.cgImage else { return nil }
        return LipPreviews.render(source)
    }
}
