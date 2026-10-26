import Foundation
import Testing
import UIKit
@testable import BugCoffee

@Suite struct CRC32Tests {
    @Test func knownVectors() {
        #expect(CRC32.checksum(Data()) == 0)
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(CRC32.checksum(Data("The quick brown fox jumps over the lazy dog".utf8)) == 0x414F_A339)
    }
}

@Suite struct PkPassZipTests {
    private func u16(_ data: Data, _ offset: Int) -> UInt16 {
        UInt16(data[data.startIndex + offset]) | UInt16(data[data.startIndex + offset + 1]) << 8
    }

    private func u32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(u16(data, offset)) | UInt32(u16(data, offset + 2)) << 16
    }

    private let buildDate: Date = {
        var components = DateComponents(year: 2026, month: 9, day: 11, hour: 14, minute: 37, second: 58)
        components.calendar = Calendar(identifier: .gregorian)
        return components.date!
    }()

    @Test func emptyArchiveIsJustTheEndRecord() {
        let data = PkPassZip().finalize()
        #expect(data.count == 22)
        #expect(u32(data, 0) == 0x0605_4b50)
        #expect(u16(data, 8) == 0)
    }

    @Test func entriesSitAtTheRootWithValidHeaders() throws {
        var zip = PkPassZip(date: buildDate)
        let pass = Data(#"{"formatVersion":1}"#.utf8)
        let icon = Data([0x89, 0x50, 0x4E, 0x47])
        zip.add("pass.json", pass)
        zip.add("icon.png", icon)
        let data = zip.finalize()

        // First local header.
        #expect(u32(data, 0) == 0x0403_4b50)
        #expect(u16(data, 8) == 0) // stored, not deflated
        let dosTime = u16(data, 10), dosDate = u16(data, 12)
        #expect(dosTime == UInt16(14 << 11 | 37 << 5 | 58 / 2))
        #expect(dosDate == UInt16((2026 - 1980) << 9 | 9 << 5 | 11))
        #expect(u32(data, 14) == CRC32.checksum(pass))
        #expect(u32(data, 18) == UInt32(pass.count))
        #expect(u16(data, 26) == UInt16("pass.json".utf8.count))
        #expect(String(data: data[30..<39], encoding: .utf8) == "pass.json")
        #expect(data[39..<(39 + pass.count)] == pass)

        // End of central directory points back at a two-entry directory.
        let end = data.count - 22
        #expect(u32(data, end) == 0x0605_4b50)
        #expect(u16(data, end + 8) == 2)
        #expect(u16(data, end + 10) == 2)
        let cdSize = Int(u32(data, end + 12)), cdOffset = Int(u32(data, end + 16))
        #expect(cdOffset + cdSize == end)

        // First central record: made by Unix, rw-r--r-- regular file, offset 0.
        #expect(u32(data, cdOffset) == 0x0201_4b50)
        #expect(u16(data, cdOffset + 4) == 3 << 8 | 20)
        #expect(u32(data, cdOffset + 38) == 0o100644 << 16)
        #expect(u32(data, cdOffset + 42) == 0)

        // Second central record points at the second local header.
        let secondCD = cdOffset + 46 + "pass.json".utf8.count
        let secondLocal = Int(u32(data, secondCD + 42))
        #expect(u32(data, secondLocal) == 0x0403_4b50)
        #expect(u32(data, secondLocal + 14) == CRC32.checksum(icon))
    }

    @Test func datesBeforeDOSEpochClampTo1980() {
        var components = DateComponents(year: 1970, month: 1, day: 2, hour: 0, minute: 0, second: 0)
        components.calendar = Calendar(identifier: .gregorian)
        var zip = PkPassZip(date: components.date!)
        zip.add("a", Data())
        let data = zip.finalize()
        #expect(u16(data, 12) >> 9 == 0)
    }
}

@Suite struct PassBuilderTests {
    private func storeCardValue(_ json: [String: Any], _ section: String) -> String? {
        let card = json["storeCard"] as? [String: Any]
        let fields = card?[section] as? [[String: Any]]
        return fields?.first?["value"] as? String
    }

    @Test func passJSONDescribesTheAccount() throws {
        let json = PassBuilder.passJSON(for: Fixtures.account)
        #expect(json["formatVersion"] as? Int == 1)
        #expect(json["passTypeIdentifier"] as? String == PassConfig.passTypeIdentifier)
        #expect(json["teamIdentifier"] as? String == PassConfig.teamIdentifier)
        #expect(json["serialNumber"] as? String == "uid-123")
        #expect(json["backgroundColor"] as? String == PassConfig.backgroundColor)
        #expect(storeCardValue(json, "secondaryFields") == "bug@example.com")
        #expect(storeCardValue(json, "primaryFields") == "0 / 9")

        let barcode = try #require((json["barcodes"] as? [[String: Any]])?.first)
        #expect(barcode["message"] as? String == "uid-123")
        #expect(barcode["format"] as? String == "PKBarcodeFormatQR")

        let location = try #require((json["locations"] as? [[String: Any]])?.first)
        #expect(location["latitude"] as? Double == PassConfig.latitude)
        #expect(location["longitude"] as? Double == PassConfig.longitude)
        #expect(location["maxDistance"] == nil)
        #expect(json["maxDistance"] as? Int == PassConfig.locationMaxDistance)

        // Must be serializable as-is.
        #expect(JSONSerialization.isValidJSONObject(json))
    }

    @Test func memberNameOverridesTheEmailWhenGiven() {
        #expect(storeCardValue(PassBuilder.passJSON(for: Fixtures.account, memberName: "  Ada \n"), "secondaryFields") == "Ada")
    }

    @Test(arguments: [nil, "", "   \n"])
    func blankMemberNameFallsBackToTheEmail(_ name: String?) {
        #expect(storeCardValue(PassBuilder.passJSON(for: Fixtures.account, memberName: name), "secondaryFields") == "bug@example.com")
    }

    @Test func bundledImagesAreUsed() throws {
        let images = PassBuilder.passImages()
        let icon = try #require(images["icon.png"])
        #expect(UIImage(data: icon) != nil)
    }

    @Test func missingIconsAreRenderedAsAFallback() throws {
        // The test bundle carries no pass images.
        let images = PassBuilder.passImages(in: Bundle(for: StubURLProtocol.self))
        #expect(Set(images.keys) == ["icon.png", "icon@2x.png", "icon@3x.png"])
        let icon3xData = try #require(images["icon@3x.png"])
        let icon3x = try #require(UIImage(data: icon3xData))
        #expect(icon3x.size.width * icon3x.scale == 87)
    }

    @Test func passFilesAddPassJSON() throws {
        let files = try PassBuilder.passFiles(for: Fixtures.account, memberName: "Grace")
        let data = try #require(files["pass.json"])
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(storeCardValue(json, "secondaryFields") == "Grace")
        #expect(files["icon.png"] != nil)
    }

    @Test func unsignedBundleIsWrittenToDisk() throws {
        let dir = try PassBuilder.buildUnsignedBundle(for: Fixtures.account)
        defer { try? FileManager.default.removeItem(at: dir) }
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.contains("pass.json"))
        #expect(names.contains("icon.png"))
    }

    @Test func unsignedZipIsExported() throws {
        let zip = try PassBuilder.exportUnsignedZip(for: Fixtures.account)
        defer { try? FileManager.default.removeItem(at: zip) }
        #expect(zip.lastPathComponent == "BugCoffee-pass-unsigned.zip")
        let data = try Data(contentsOf: zip)
        #expect(data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))
    }
}

@Suite struct ZipTests {
    @Test func zipsADirectory() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ZipTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: dir.appendingPathComponent("a.txt"))
        let name = "ZipTests-\(UUID().uuidString)"
        let zip = try Zip.zip(contentsOf: dir, named: name)
        defer { try? FileManager.default.removeItem(at: zip); try? FileManager.default.removeItem(at: dir) }
        #expect(zip.lastPathComponent == "\(name).zip")
        #expect(try Data(contentsOf: zip).prefix(2) == Data("PK".utf8))
    }

    @Test func missingDirectoryThrows() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nope-\(UUID().uuidString)")
        #expect(throws: (any Error).self) { try Zip.zip(contentsOf: missing, named: "nope") }
    }
}

@Suite struct QRTests {
    @Test func rendersAScaledCode() throws {
        let small = try #require(QRGenerator.cgImage(from: "uid-123", scale: 1))
        let big = try #require(QRGenerator.cgImage(from: "uid-123"))
        #expect(big.width == small.width * 12)
        #expect(QRGenerator.image(from: "uid-123")?.size.width == CGFloat(big.width))
    }

    @Test func pngRoundTripsThroughImageDecode() throws {
        let png = try #require(QRGenerator.pngData(from: "uid-123"))
        let decoded = try #require(ImageDecode.cgImage(fromPNG: png))
        let raw = try #require(QRGenerator.cgImage(from: "uid-123", scale: 10))
        #expect(decoded.width == raw.width)
    }

    @Test func imageDecodeRejectsGarbage() {
        #expect(ImageDecode.cgImage(fromPNG: Data("not a png".utf8)) == nil)
        #expect(ImageDecode.cgImage(fromPNG: Data()) == nil)
    }
}
