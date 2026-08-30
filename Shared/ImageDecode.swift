import Foundation
import ImageIO
import CoreGraphics

/// Decodes PNG bytes into a CGImage. ImageIO is available on both iOS and
/// watchOS, so the Watch app can render the QR the phone sent it.
enum ImageDecode {
    static func cgImage(fromPNG data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
