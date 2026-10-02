import Foundation
import UIKit
import PassKit
import CryptoKit

/// Fill these in with your own Apple Developer values before signing a pass.
/// They are NOT secrets — they are baked into every distributed .pkpass.
enum PassConfig {
    /// Your Pass Type ID (Apple Developer → Identifiers → Pass Type IDs).
    static let passTypeIdentifier = "pass.com.zerogravityroom.bugwallet"
    /// Your 10-character Apple Developer Team ID.
    static let teamIdentifier = "4F5J749858"
    static let organizationName = "Bug Coffee"
    static let description = "Bug Coffee Loyalty Card"

    // Brand colors from the reverse-engineering doc (§6 / §9.1).
    static let backgroundColor = "rgb(31, 4, 9)"     // #1F0409 darkBrown
    static let foregroundColor = "rgb(255, 255, 255)"
    static let labelColor = "rgb(204, 30, 65)"       // #CC1E41 accent red

    // The shop's coordinates. A pass carrying `locations` surfaces on the Lock
    // Screen when the holder is nearby, which is the whole point of a store card.
    static let latitude = 42.69323
    static let longitude = 23.34402
    static let locationRelevantText = "Bug Coffee е наблизо"
    /// Geofence radius in metres for the location relevance above.
    static let locationMaxDistance = 15
}

/// Assembles an Apple Wallet `storeCard` pass for a signed-in account.
///
/// A .pkpass MUST be cryptographically signed with your Pass Type ID certificate
/// + Apple's WWDR certificate. That signing key cannot safely live in the app and
/// on-device CMS signing is not available in the iOS SDK, so this builder produces
/// the *unsigned* pass contents (pass.json + images) and exports them. Sign them
/// once with `Scripts/make_pkpass.sh` (the UID is stable, so you only do this once
/// per account). See README.
enum PassBuilder {

    /// The pass.json dictionary for this account. `memberName`, when non-empty,
    /// overrides the member field (used for a scanned pass, where we ask the user
    /// for the holder's name instead of an email).
    static func passJSON(for account: Account, memberName: String? = nil) -> [String: Any] {
        let member = memberName.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap { $0.isEmpty ? nil : $0 } ?? account.email
        return [
            "formatVersion": 1,
            "passTypeIdentifier": PassConfig.passTypeIdentifier,
            "teamIdentifier": PassConfig.teamIdentifier,
            "organizationName": PassConfig.organizationName,
            "description": PassConfig.description,
            // Serial number is stable per account so re-issuing updates the same pass.
            "serialNumber": account.uid,
            "storeCard": [
                "headerFields": [
                    ["key": "program", "label": "BUG COFFEE", "value": "Loyalty"]
                ],
                "primaryFields": [
                    ["key": "stamps", "label": "ПЕЧАТИ", "value": "0 / 9"]
                ],
                "secondaryFields": [
                    ["key": "member", "label": "ЧЛЕН", "value": member]
                ]
            ],
            // The QR staff scan: the raw UID string, level built in by Wallet.
            "barcodes": [
                [
                    "format": "PKBarcodeFormatQR",
                    "message": account.uid,
                    "messageEncoding": "iso-8859-1"
                ]
            ],
            // Lock Screen relevance when the holder is near the shop.
            "locations": [
                [
                    "latitude": PassConfig.latitude,
                    "longitude": PassConfig.longitude,
                    "relevantText": PassConfig.locationRelevantText
                ]
            ],
            // Top-level, not per-location: Wallet ignores `maxDistance` inside a
            // location dictionary. It can only shrink Wallet's default radius.
            "maxDistance": PassConfig.locationMaxDistance,
            "backgroundColor": PassConfig.backgroundColor,
            "foregroundColor": PassConfig.foregroundColor,
            "labelColor": PassConfig.labelColor
        ]
    }

    /// Writes pass.json + bundled pass images into a fresh temp directory and
    /// returns that directory URL, ready to be zipped/signed.
    static func buildUnsignedBundle(for account: Account) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("BugCoffee.pass-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // pass.json
        let json = try JSONSerialization.data(withJSONObject: passJSON(for: account),
                                              options: [.prettyPrinted, .sortedKeys])
        try json.write(to: dir.appendingPathComponent("pass.json"))

        // Pass images (icon.png guaranteed present).
        for (name, data) in passImages() {
            try data.write(to: dir.appendingPathComponent(name))
        }
        return dir
    }

    /// The pass images keyed by their filename. Loads the bundled PassTemplate
    /// PNGs by exact path (avoiding the `@2x`/`@3x` scale-suffix gotcha in
    /// `Bundle.url(forResource:)`), and guarantees an `icon.png` by rendering a
    /// fallback so a generated pass can never be icon-less — which Wallet rejects.
    static func passImages(in bundle: Bundle = .main) -> [String: Data] {
        var images: [String: Data] = [:]
        for name in ["icon.png", "icon@2x.png", "icon@3x.png", "logo.png", "logo@2x.png"] {
            if let data = bundlePNG(name, in: bundle) { images[name] = data }
        }
        if images["icon.png"] == nil {
            images["icon.png"] = renderFallbackIcon(points: 29, scale: 1)
            images["icon@2x.png"] = renderFallbackIcon(points: 29, scale: 2)
            images["icon@3x.png"] = renderFallbackIcon(points: 29, scale: 3)
        }
        return images
    }

    /// Reads a bundled resource by exact filename from the bundle's resource dir.
    private static func bundlePNG(_ filename: String, in bundle: Bundle) -> Data? {
        guard let base = bundle.resourceURL else { return nil }
        let url = base.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// A simple opaque branded icon, used only if the bundled PNGs are missing.
    private static func renderFallbackIcon(points: CGFloat, scale: CGFloat) -> Data {
        let size = CGSize(width: points, height: points)
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            UIColor(red: 204/255, green: 30/255, blue: 65/255, alpha: 1).setFill()
            let inset = points * 0.18
            let rect = CGRect(x: inset, y: inset, width: points - 2 * inset, height: points - 2 * inset)
            UIBezierPath(roundedRect: rect, cornerRadius: points * 0.2).fill()
        }
        return image.pngData() ?? Data()
    }

    /// Zips the unsigned bundle so it can be AirDropped/shared to a Mac for signing.
    static func exportUnsignedZip(for account: Account) throws -> URL {
        let dir = try buildUnsignedBundle(for: account)
        return try Zip.zip(contentsOf: dir, named: "BugCoffee-pass-unsigned")
    }

    /// The files that make up the pass (excluding manifest/signature): pass.json
    /// plus the bundled images.
    static func passFiles(for account: Account, memberName: String? = nil) throws -> [String: Data] {
        var files: [String: Data] = passImages()
        files["pass.json"] = try JSONSerialization.data(
            withJSONObject: passJSON(for: account, memberName: memberName),
            options: [.prettyPrinted, .sortedKeys])
        return files
    }

    // Signing a .pkpass on-device is "local pass creation" — compiled only into
    // the Debug-LocalPass config (BugWallet-LocalPass scheme). See
    // Config/LocalPassCreation.xcconfig.
    #if LOCAL_PASS_CREATION
    enum BuildError: LocalizedError {
        case missingIcon
        var errorDescription: String? {
            "Couldn't include icon.png in the pass (Wallet requires it)."
        }
    }

    /// Builds a fully signed `.pkpass` in memory for the given account, ready to
    /// hand to `PKPass`/`PKAddPassesViewController`. Signs on-device (see PassSigner).
    /// `memberName`, when non-empty, is shown on the pass instead of the email.
    static func buildSignedPass(for account: Account, memberName: String? = nil) throws -> Data {
        let files = try passFiles(for: account, memberName: memberName)
        guard files["icon.png"] != nil else { throw BuildError.missingIcon }

        // manifest.json — SHA1 of every file.
        var manifest: [String: String] = [:]
        for (name, data) in files {
            manifest[name] = Insecure.SHA1.hash(data: data)
                .map { String(format: "%02x", $0) }.joined()
        }
        let manifestData = try JSONSerialization.data(withJSONObject: manifest,
                                                      options: [.sortedKeys])

        // signature — detached CMS over the manifest.
        let assets = try PassSigner.loadAssets()
        let signature = try PassSigner.sign(manifest: manifestData, assets: assets)

        // zip everything at the archive root.
        var zip = PkPassZip()
        for (name, data) in files.sorted(by: { $0.key < $1.key }) {
            zip.add(name, data)
        }
        zip.add("manifest.json", manifestData)
        zip.add("signature", signature)
        return zip.finalize()
    }
    #endif
}
