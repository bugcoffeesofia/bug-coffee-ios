import UIKit
import CoreImage

/// QR generation (iOS only — CoreImage isn't available on watchOS, so the phone
/// renders the code and ships a PNG to the watch). Correction level H matches the
/// web app.
enum QRGenerator {
    private static let context = CIContext(options: nil)

    static func cgImage(from string: String, scale: CGFloat = 12) -> CGImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(string.utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        return context.createCGImage(output, from: output.extent)
    }

    static func image(from string: String, scale: CGFloat = 12) -> UIImage? {
        guard let cg = cgImage(from: string, scale: scale) else { return nil }
        return UIImage(cgImage: cg)
    }

    /// PNG bytes of the QR, for sending to the Watch app.
    static func pngData(from string: String, scale: CGFloat = 10) -> Data? {
        image(from: string, scale: scale)?.pngData()
    }
}
