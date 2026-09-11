import Foundation

/// Minimal ZIP writer (STORE method, no compression) that places every entry at
/// the archive root — which is what a `.pkpass` requires. The system file
/// coordinator zips a *folder* (entries nested under a directory), so we build
/// the archive ourselves.
struct PkPassZip {
    private var body = Data()
    private var central = Data()
    private var count: UInt16 = 0

    // Made by Unix (upper byte 3), so extractors honor the mode below.
    private static let versionMadeBy: UInt16 = 3 << 8 | 20
    // Regular file, rw-r--r--, as a Unix mode in the upper 16 bits.
    private static let externalAttrs: UInt32 = 0o100644 << 16

    // DOS timestamp stamped on every entry. All-zero is not a valid DOS date
    // (month 0, day 0), so use the time the archive is built.
    private let modTime: UInt16
    private let modDate: UInt16

    init(date: Date = Date()) {
        let c = Calendar(identifier: .gregorian)
            .dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        modTime = UInt16(c.hour! << 11 | c.minute! << 5 | c.second! / 2)
        modDate = UInt16((max(c.year!, 1980) - 1980) << 9 | c.month! << 5 | c.day!)
    }

    mutating func add(_ name: String, _ content: Data) {
        let nameBytes = Array(name.utf8)
        let crc = CRC32.checksum(content)
        let size = UInt32(content.count)
        let offset = UInt32(body.count)

        // Local file header
        body.append(le32: 0x0403_4b50)
        body.append(le16: 20)          // version needed
        body.append(le16: 0)           // flags
        body.append(le16: 0)           // method: store
        body.append(le16: modTime)
        body.append(le16: modDate)
        body.append(le32: crc)
        body.append(le32: size)        // compressed
        body.append(le32: size)        // uncompressed
        body.append(le16: UInt16(nameBytes.count))
        body.append(le16: 0)           // extra length
        body.append(contentsOf: nameBytes)
        body.append(content)

        // Central directory record
        central.append(le32: 0x0201_4b50)
        central.append(le16: Self.versionMadeBy)
        central.append(le16: 20)       // version needed
        central.append(le16: 0)        // flags
        central.append(le16: 0)        // method
        central.append(le16: modTime)
        central.append(le16: modDate)
        central.append(le32: crc)
        central.append(le32: size)
        central.append(le32: size)
        central.append(le16: UInt16(nameBytes.count))
        central.append(le16: 0)        // extra length
        central.append(le16: 0)        // comment length
        central.append(le16: 0)        // disk number
        central.append(le16: 0)        // internal attrs
        central.append(le32: Self.externalAttrs)
        central.append(le32: offset)
        central.append(contentsOf: nameBytes)

        count += 1
    }

    func finalize() -> Data {
        var out = body
        let cdOffset = UInt32(out.count)
        out.append(central)
        let cdSize = UInt32(central.count)

        // End of central directory
        out.append(le32: 0x0605_4b50)
        out.append(le16: 0)            // disk number
        out.append(le16: 0)            // cd start disk
        out.append(le16: count)
        out.append(le16: count)
        out.append(le32: cdSize)
        out.append(le32: cdOffset)
        out.append(le16: 0)            // comment length
        return out
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) {
        append(contentsOf: [UInt8(value & 0xff), UInt8(value >> 8 & 0xff)])
    }
    mutating func append(le32 value: UInt32) {
        append(contentsOf: [
            UInt8(value & 0xff),
            UInt8(value >> 8 & 0xff),
            UInt8(value >> 16 & 0xff),
            UInt8(value >> 24 & 0xff)
        ])
    }
}

/// CRC-32 (IEEE) for ZIP entries.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
