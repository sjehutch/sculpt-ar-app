import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

enum SelfieGuidance: String {
    case findFace = "Center your face in the camera."
    case oneFace = "Keep just one face in the frame."
    case closer = "Move a little closer."
    case farther = "Move back so your whole face fits."
    case faceForward = "Look straight at the camera."
    case showLips = "Keep your lips relaxed and visible."
    case holdStill = "Face a light and hold still."
    case ready = "Looks good. You can take the photo."

    static func assess(_ image: CIImage, context: CIContext) -> SelfieGuidance {
        let handler = VNImageRequestHandler(ciImage: image)
        let landmarks = VNDetectFaceLandmarksRequest()
        guard (try? handler.perform([landmarks])) != nil,
              let faces = landmarks.results, let face = faces.first else { return .findFace }
        guard faces.count == 1 else { return .oneFace }

        let bounds = face.boundingBox
        if bounds.width > 0.85 || bounds.height > 0.85 { return .farther }
        if abs(bounds.midX - 0.5) > 0.16 || abs(bounds.midY - 0.5) > 0.18 { return .findFace }
        if bounds.width < 0.26 || bounds.height < 0.26 { return .closer }
        if bounds.minX < 0.025 || bounds.maxX > 0.975 ||
            bounds.minY < 0.025 || bounds.maxY > 0.975 { return .farther }

        if abs(face.yaw?.doubleValue ?? 0) > 0.28 ||
            abs(face.pitch?.doubleValue ?? 0) > 0.32 ||
            abs(face.roll?.doubleValue ?? 0) > 0.25 { return .faceForward }
        guard let lips = face.landmarks?.outerLips, lips.pointCount >= 3 else { return .showLips }

        let quality = VNDetectFaceCaptureQualityRequest()
        quality.inputFaceObservations = [face]
        if (try? handler.perform([quality])) != nil,
           let score = quality.results?.first?.faceCaptureQuality, score < 0.25 { return .holdStill }
        if isVeryDim(image, face: bounds, context: context) { return .holdStill }
        return .ready
    }

    private static func isVeryDim(_ image: CIImage, face: CGRect, context: CIContext) -> Bool {
        let extent = image.extent
        let facePixels = CGRect(x: extent.minX + face.minX * extent.width,
                                y: extent.minY + face.minY * extent.height,
                                width: face.width * extent.width, height: face.height * extent.height)
        let average = CIFilter.areaAverage()
        average.inputImage = image
        average.extent = facePixels.insetBy(dx: facePixels.width * 0.15, dy: facePixels.height * 0.15)
        guard let pixel = average.outputImage else { return false }

        var rgba = [UInt8](repeating: 0, count: 4)
        rgba.withUnsafeMutableBytes { bytes in
            context.render(pixel, toBitmap: bytes.baseAddress!, rowBytes: 4, bounds: pixel.extent,
                           format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        }
        let luma = 0.2126 * Double(rgba[0]) + 0.7152 * Double(rgba[1]) + 0.0722 * Double(rgba[2])
        // A low floor catches very dark frames without treating skin tone as a quality score.
        return luma < 48
    }
}
