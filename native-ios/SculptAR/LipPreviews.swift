import CoreImage
import CoreImage.CIFilterBuiltins
import Vision

struct LipPreviews {
    let fullness: CGImage
    let definition: CGImage?

    static func render(_ photo: CGImage) -> LipPreviews? {
        let request = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(cgImage: photo)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let faces = request.results, faces.count == 1,
              let lips = faces.first?.landmarks?.outerLips else { return nil }

        let image = CIImage(cgImage: photo)
        let points = lips.pointsInImage(imageSize: image.extent.size)
        guard points.count >= 3 else { return nil }
        let contour = CGMutablePath()
        contour.addLines(between: points)
        let bounds = contour.boundingBoxOfPath
        guard bounds.width > 0, bounds.height > 0 else { return nil }

        let context = CIContext()
        guard let fuller = fullerLips(in: image, bounds: bounds),
              let fullness = context.createCGImage(fuller, from: image.extent) else { return nil }
        let definition = definedLips(in: image, points: points, bounds: bounds).flatMap {
            context.createCGImage($0, from: image.extent)
        }
        return LipPreviews(fullness: fullness, definition: definition)
    }

    private static func fullerLips(in image: CIImage, bounds: CGRect) -> CIImage? {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radiusX = bounds.width * 0.55
        let radiusY = max(bounds.height * 1.1, bounds.width * 0.28)
        // Fit the circular distortion to the wider, shallower shape of the mouth.
        let stretch = CGAffineTransform(scaleX: 1, y: radiusX / radiusY)
        let filter = CIFilter.bumpDistortion()
        filter.inputImage = image.transformed(by: stretch)
        filter.center = center.applying(stretch)
        filter.radius = Float(radiusX)
        filter.scale = 0.35

        let region = CGRect(
            x: center.x - radiusX, y: center.y - radiusY,
            width: radiusX * 2, height: radiusY * 2
        ).integral.intersection(image.extent)
        guard !region.isEmpty, let warped = filter.outputImage else { return nil }

        let mask = CIImage(color: .white).cropped(to: region)
        return blend(warped.transformed(by: stretch.inverted()), over: image, mask: mask)
    }

    private static func definedLips(in image: CIImage, points: [CGPoint], bounds: CGRect) -> CIImage? {
        let outline = upperOutline(of: points)
        guard outline.count >= 3 else { return nil }

        let stroke = max(3, bounds.width * 0.05)
        let region = bounds.insetBy(dx: -stroke * 2, dy: -stroke * 2)
            .integral.intersection(image.extent)
        guard !region.isEmpty, let maskContext = CGContext(
            data: nil, width: Int(region.width), height: Int(region.height),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        maskContext.translateBy(x: -region.minX, y: -region.minY)
        maskContext.setStrokeColor(gray: 1, alpha: 1)
        maskContext.setLineWidth(stroke)
        maskContext.setLineCap(.round)
        maskContext.setLineJoin(.round)
        maskContext.addLines(between: outline)
        maskContext.strokePath()
        guard let strokeImage = maskContext.makeImage() else { return nil }

        let mask = CIImage(cgImage: strokeImage)
            .transformed(by: CGAffineTransform(translationX: region.minX, y: region.minY))
            .applyingGaussianBlur(sigma: stroke * 0.25)
        let filter = CIFilter.sharpenLuminance()
        filter.inputImage = image
        filter.radius = Float(max(2, bounds.width * 0.025))
        filter.sharpness = 0.8
        guard let sharpened = filter.outputImage else { return nil }
        return blend(sharpened, over: image, mask: mask)
    }

    private static func upperOutline(of points: [CGPoint]) -> [CGPoint] {
        guard let left = points.indices.min(by: { points[$0].x < points[$1].x }),
              let right = points.indices.max(by: { points[$0].x < points[$1].x }),
              points[right].x > points[left].x else { return [] }

        // The closed contour can start anywhere. Split it at the mouth corners.
        let start = min(left, right)
        let end = max(left, right)
        let firstArc = Array(points[start...end])
        let secondArc = Array(points[end...] + points[...start])
        let corner = points[left]
        let slope = (points[right].y - corner.y) / (points[right].x - corner.x)
        func heightAboveCorners(_ arc: [CGPoint]) -> CGFloat {
            arc.reduce(0) { $0 + ($1.y - corner.y) - slope * ($1.x - corner.x) } / CGFloat(arc.count)
        }
        return heightAboveCorners(firstArc) > heightAboveCorners(secondArc) ? firstArc : secondArc
    }

    private static func blend(_ foreground: CIImage, over background: CIImage, mask: CIImage) -> CIImage? {
        let blend = CIFilter.blendWithAlphaMask()
        blend.inputImage = foreground
        blend.backgroundImage = background
        blend.maskImage = mask
        return blend.outputImage
    }
}
