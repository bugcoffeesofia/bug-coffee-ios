import Foundation

/// Minimal ZIP writer (STORE method, no compression) that places every entry at
/// the archive root — which is what a `.pkpass` requires. The system file
/// coordinator zips a *folder* (entries nested under a directory), so we build
/// the archive ourselves.
struct PkPassZip {
    private var body = Data()
    private var central = Data()
    private var count: UInt16 = 0

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
        body.append(le16: 0)           // mod time
        body.append(le16: 0)           // mod date
        body.append(le32: crc)
        body.append(le32: size)        // compressed
        body.append(le32: size)        // uncompressed
        body.append(le16: UInt16(nameBytes.count))
        body.append(le16: 0)           // extra length
        body.append(contentsOf: nameBytes)
        body.append(content)

        // Central directory record
        central.append(le32: 0x0201_4b50)
        central.append(le16: 20)       // version made by
        central.append(le16: 20)       // version needed
        central.append(le16: 0)        // flags
        central.append(le16: 0)        // method
        central.append(le16: 0)        // mod time
        central.append(le16: 0)        // mod date
        central.append(le32: crc)
        central.append(le32: size)
        central.append(le32: size)
        central.append(le16: UInt16(nameBytes.count))
        central.append(le16: 0)        // extra length
        central.append(le16: 0)        // comment length
        central.append(le16: 0)        // disk number
        central.append(le16: 0)        // internal attrs
        central.append(le32: 0)        // external attrs
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
