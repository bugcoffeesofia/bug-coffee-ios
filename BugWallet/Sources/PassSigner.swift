// On-device pass signing is part of "local pass creation" and is compiled only
// into the Debug-LocalPass configuration (BugWallet-LocalPass scheme). See
// Config/LocalPassCreation.xcconfig. This build embeds a private signing key.
#if LOCAL_PASS_CREATION
import Foundation
@_spi(CMS) import X509
import _CryptoExtras

/// Signs a pass manifest on-device using the bundled Pass Type ID certificate
/// and private key (under Resources/Signing). Produces a detached PKCS#7/CMS
/// signature (DER), exactly what Wallet expects for the `signature` file.
///
/// SECURITY: this embeds your pass-signing private key in the app bundle. Fine
/// for a personal build; do not distribute this build publicly.
enum PassSigner {
    struct Assets {
        let certificate: Certificate
        let intermediate: Certificate
        let privateKey: Certificate.PrivateKey
    }

    enum SignerError: LocalizedError {
        case missingAsset(String)
        var errorDescription: String? {
            switch self {
            case .missingAsset(let name):
                return "Missing signing asset \(name). Put passcert.pem, passkey.pem and wwdr.pem in Resources/Signing."
            }
        }
    }

    static func loadAssets() throws -> Assets {
        func pem(_ name: String) throws -> String {
            let url = Bundle.main.url(forResource: name, withExtension: "pem", subdirectory: "Signing")
                ?? Bundle.main.url(forResource: name, withExtension: "pem")
            guard let url else { throw SignerError.missingAsset("\(name).pem") }
            return try String(contentsOf: url, encoding: .utf8)
        }
        let certificate = try Certificate(pemEncoded: pem("passcert"))
        let intermediate = try Certificate(pemEncoded: pem("wwdr"))
        let rsaKey = try _RSA.Signing.PrivateKey(pemRepresentation: pem("passkey"))
        return Assets(certificate: certificate,
                      intermediate: intermediate,
                      privateKey: Certificate.PrivateKey(rsaKey))
    }

    /// Detached CMS signature (DER) over the pass manifest.
    ///
    /// `signingTime` is required: without it swift-certificates emits a bare
    /// signature with no signed attributes, and PassKit rejects the pass with
    /// "Signature must contain a signing date". With it the signature carries
    /// contentType + messageDigest + signingTime, matching `openssl smime -sign`
    /// (Scripts/make_pkpass.sh).
    static func sign(manifest: Data, assets: Assets) throws -> Data {
        let signature = try CMS.sign(
            manifest,
            signatureAlgorithm: .sha256WithRSAEncryption,
            additionalIntermediateCertificates: [assets.intermediate],
            certificate: assets.certificate,
            privateKey: assets.privateKey,
            signingTime: Date(),
            detached: true
        )
        return Data(signature)
    }
}
#endif
