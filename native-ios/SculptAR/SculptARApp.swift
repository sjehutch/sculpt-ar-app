import PhotosUI
import SwiftUI
import UIKit

@main
struct SculptARApp: App {
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var isLoadingPhoto = false
    @State private var showsPhotoError = false
    @State private var showsCamera = false

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                VStack(spacing: 16) {
                    if let photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .accessibilityHidden(true)
                    }

                    VStack(spacing: 12) {
                        if isLoadingPhoto {
                            ProgressView("Loading photo…")
                        } else if photo != nil {
                            Label("Photo selected", systemImage: "checkmark.circle.fill")
                        }

                        if let photo {
                            NavigationLink {
                                PhotoPreview(photo: photo)
                            } label: {
                                Text("Use Photo")
                                    .font(.title2.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 56)
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                showsCamera = true
                            } label: {
                                Text("Take Another Photo")
                                    .font(.body.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                            }
                            .buttonStyle(.bordered)
                        } else {
                            Button {
                                showsCamera = true
                            } label: {
                                Text("Take a Photo")
                                    .font(.title2.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 56)
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Text("Choose from Library")
                                .font(.body.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                    }
                    .disabled(isLoadingPhoto)
                    .frame(maxWidth: 320)
                    .layoutPriority(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
                .toolbar(.hidden, for: .navigationBar)
            }
            .fullScreenCover(isPresented: $showsCamera) {
                SelfieCameraView { capturedPhoto in
                    photo = capturedPhoto
                    selectedPhoto = nil
                    showsCamera = false
                }
            }
            .task(id: selectedPhoto) { [selectedPhoto] in
                guard let selectedPhoto else { return }

                isLoadingPhoto = true
                let data = try? await selectedPhoto.loadTransferable(type: Data.self)
                guard !Task.isCancelled, selectedPhoto == self.selectedPhoto else { return }

                isLoadingPhoto = false
                if let data, let image = UIImage(data: data) {
                    photo = image
                } else {
                    self.selectedPhoto = nil
                    showsPhotoError = true
                }
            }
            .alert("Couldn’t load photo", isPresented: $showsPhotoError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Try choosing the photo again.")
            }
        }
    }
}
