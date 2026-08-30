import Foundation

/// Minimal zip helper using the system file coordinator (no dependencies).
/// `.forUploading` produces a .zip of a directory's contents.
enum Zip {
    static func zip(contentsOf directory: URL, named base: String) throws -> URL {
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var result: URL?
        var thrown: Error?

        coordinator.coordinate(readingItemAt: directory,
                               options: [.forUploading],
                               error: &coordError) { zippedURL in
            // `zippedURL` is a temporary .zip the coordinator created; copy it to a stable name.
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(base).zip")
            try? FileManager.default.removeItem(at: dest)
            do {
                try FileManager.default.copyItem(at: zippedURL, to: dest)
                result = dest
            } catch {
                thrown = error
            }
        }

        if let coordError { throw coordError }
        if let thrown { throw thrown }
        guard let result else {
            throw NSError(domain: "Zip", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create zip archive."])
        }
        return result
    }
}
