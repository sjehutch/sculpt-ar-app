import AVFoundation
import Combine
import CoreImage
import UIKit

final class SelfieCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum Status: Equatable {
        case starting
        case guidance(SelfieGuidance)
        case unavailable(String)
    }

    let session = AVCaptureSession()
    @Published private(set) var device: AVCaptureDevice?
    @Published private(set) var status = Status.starting
    @Published private(set) var photo: UIImage?

    private var wantsCamera = false
    private var requestingAccess = false

    // The session, frame analysis and shutter share a serial queue.
    private let queue = DispatchQueue(label: "com.sculptar.selfie-camera", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private let context = CIContext()
    private var configured = false
    private var rotationAngle: CGFloat?
    private var lastAnalysisTime: CFTimeInterval = 0
    private var captureRequested = false
    private var captured = false

    func start() {
        wantsCamera = true
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            queue.async { [self] in
                if !configured {
                    guard let device = configure() else {
                        publish(.unavailable("The front camera is unavailable. You can choose a photo from your library."))
                        return
                    }
                    configured = true
                    DispatchQueue.main.async { self.device = device }
                }
                if !session.isRunning { session.startRunning() }
            }
        case .notDetermined:
            guard !requestingAccess else { return }
            requestingAccess = true
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.requestingAccess = false
                    if self.wantsCamera { self.start() }
                }
            }
        default:
            status = .unavailable("Allow camera access in Settings or choose a photo from your library.")
        }
    }

    func stop() {
        wantsCamera = false
        status = .starting
        queue.async { [self] in
            captureRequested = false
            captured = false
            if session.isRunning { session.stopRunning() }
        }
    }

    func interrupted() {
        guard wantsCamera else { return }
        status = .starting
        queue.async { self.captureRequested = false }
    }

    func failed() {
        guard wantsCamera else { return }
        stop()
        status = .unavailable("The camera stopped. Go back and try again, or choose a photo from your library.")
    }

    func setRotation(_ angle: CGFloat) {
        queue.async { [self] in
            guard angle != rotationAngle, let connection = output.connection(with: .video),
                  connection.isVideoRotationAngleSupported(angle) else { return }
            connection.videoRotationAngle = angle
            rotationAngle = angle
            captureRequested = false
            publish(.starting)
        }
    }

    func capture() {
        guard status == .guidance(.ready) else { return }
        queue.async { [self] in
            if session.isRunning && !session.isInterrupted && !captured { captureRequested = true }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard rotationAngle != nil, !captured, !session.isInterrupted,
              let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = CACurrentMediaTime()
        guard captureRequested || now - lastAnalysisTime >= 0.25 else { return }
        lastAnalysisTime = now

        let image = CIImage(cvPixelBuffer: buffer)
        let guidance = SelfieGuidance.assess(image, context: context)
        publish(.guidance(guidance))
        guard captureRequested else { return }
        captureRequested = false
        guard guidance == .ready else { return }

        // Use the frame that passed the check so the review matches the guidance.
        guard let still = context.createCGImage(image, from: image.extent) else { return }
        captured = true
        let photo = UIImage(cgImage: still)
        DispatchQueue.main.async {
            if self.wantsCamera { self.photo = photo }
        }
    }

    private func configure() -> AVCaptureDevice? {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device) else { return nil }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { return nil }
        session.addInput(input)
        if session.canSetSessionPreset(.hd1920x1080) { session.sessionPreset = .hd1920x1080 }
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            return nil
        }
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        session.addOutput(output)
        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        return device
    }

    private func publish(_ status: Status) {
        DispatchQueue.main.async {
            if self.wantsCamera && self.status != status { self.status = status }
        }
    }
}
