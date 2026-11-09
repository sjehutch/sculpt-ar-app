import AVFoundation
import SwiftUI
import UIKit

struct SelfieCameraView: View {
    let onCapture: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var camera = SelfieCamera()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
            }
            .padding(.horizontal, 24)

            LivePreview(camera: camera)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                switch camera.status {
                case .starting:
                    ProgressView("Starting camera…")
                case .guidance(let guidance):
                    Label(guidance.rawValue, systemImage: guidance == .ready ? "checkmark.circle.fill" : "viewfinder")
                        .font(.headline)
                        .foregroundStyle(guidance == .ready ? Color.green : Color.primary)
                case .unavailable(let message):
                    Text(message)
                }

                Button(action: camera.capture) {
                    Text("Capture Photo")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: 320, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(camera.status != .guidance(.ready))
            }
            .multilineTextAlignment(.center)
            .padding([.horizontal, .bottom], 16)
            .layoutPriority(1)
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active { camera.start() } else { camera.stop() }
        }
        .onChange(of: camera.photo) { _, photo in
            if let photo { onCapture(photo) }
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification,
                                                        object: camera.session).receive(on: DispatchQueue.main)) { _ in
            camera.interrupted()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.runtimeErrorNotification,
                                                        object: camera.session).receive(on: DispatchQueue.main)) { _ in
            camera.failed()
        }
        .onDisappear { camera.stop() }
    }
}

private struct LivePreview: UIViewRepresentable {
    @ObservedObject var camera: SelfieCamera

    func makeUIView(context: Context) -> PreviewView { PreviewView() }

    func updateUIView(_ view: PreviewView, context: Context) {
        view.connect(to: camera)
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        private var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
        private weak var camera: SelfieCamera?
        private var rotation: AVCaptureDevice.RotationCoordinator?
        private var rotationObservation: NSKeyValueObservation?
        private var lastSentAngle: CGFloat?

        func connect(to camera: SelfieCamera) {
            guard let device = camera.device, rotation == nil else { return }
            self.camera = camera
            previewLayer.session = camera.session
            previewLayer.videoGravity = .resizeAspect
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
            rotation = coordinator
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview,
                                                       options: [.initial, .new]) { [weak self] coordinator, _ in
                self?.applyRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
            }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            if let rotation { applyRotation(rotation.videoRotationAngleForHorizonLevelPreview) }
        }

        private func applyRotation(_ angle: CGFloat) {
            // Use the same quarter-turn orientation for the preview and analyzed frames.
            let angle = ((angle / 90).rounded() * 90).truncatingRemainder(dividingBy: 360)
            if let connection = previewLayer.connection {
                if connection.isVideoMirroringSupported && !connection.isVideoMirrored {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = true
                }
                if angle != connection.videoRotationAngle && connection.isVideoRotationAngleSupported(angle) {
                    connection.videoRotationAngle = angle
                }
            }
            if lastSentAngle != angle {
                lastSentAngle = angle
                camera?.setRotation(angle)
            }
        }
    }
}
