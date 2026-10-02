import XCTest

/// Walks the Watch app's screens and saves a PNG of each into
/// `docs/screenshots/<watch>/`, for the docs (see docs/09-screenshots.md).
///
/// Run with `Scripts/take_screenshots.sh` (or ⌘U on the `BugWalletWatch`
/// scheme). Like the iPhone tests, nothing is paired, synced or written: the
/// account, the QR the phone would have sent and the stamp count are handed to
/// the app as launch arguments, which land in the argument domain and override
/// the watch's standard defaults for this launch only.
@MainActor
final class WatchScreenshotTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Screens

    func test01Home() async throws {
        launch()
        try require(app.buttons["Loyalty card"].waitForExistence(timeout: 10))
        try await capture("01-home")
    }

    func test02Card() async throws {
        launch()
        try open("Loyalty card", title: "Card")
        try require(app.images.firstMatch.waitForExistence(timeout: 5), "No QR on the card")
        try await capture("02-card")
    }

    func test03Stamps() async throws {
        launch()
        try open("Stamps")
        try require(app.staticTexts["\(DemoData.stamps) / 9"].waitForExistence(timeout: 5))
        try await capture("03-stamps")
    }

    func test04LogCaffeine() async throws {
        launch()
        try open("Log caffeine")
        try await capture("04-log-caffeine")
    }

    func test05FindMyBlend() async throws {
        launch()
        try open("Find my blend")
        try await capture("05-find-my-blend")
    }

    func test06BlendMatches() async throws {
        launch()
        try open("Find my blend")
        try pick("Serving", "With milk")
        try pick("Flavor", "Chocolate & nuts")
        // The list is lazy and a swipe flings it to the end, so scroll in
        // short drags until the header shows up, then drag it under the title.
        let matches = app.staticTexts["Your matches"]
        for _ in 0..<6 where !matches.exists {
            drag(fromY: 0.8, toY: 0.5)
        }
        try require(matches.exists, "No matches section")
        let screen = app.frame
        drag(fromY: matches.frame.midY / screen.height, toY: 72 / screen.height)
        try await capture("06-blend-matches")
    }

    func test07SignedOut() async throws {
        launch(signedIn: false)
        try open("Loyalty card", title: "Card")
        try await capture("07-signed-out")
    }

    // MARK: - Navigation

    private func open(_ row: String, title: String? = nil) throws {
        let button = app.buttons[row]
        try require(button.waitForExistence(timeout: 10), "No \(row) row")
        button.tap()
        try require(app.navigationBars[title ?? row].waitForExistence(timeout: 5))
    }

    /// A slow vertical drag between two points given as fractions of the screen
    /// height — no fling, so the list stops where the finger does.
    private func drag(fromY: CGFloat, toY: CGFloat) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: fromY))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: toY))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
    }

    /// Opens a Picker row ("Serving, Black") and chooses an option. On watchOS
    /// the options are a pushed list that pops back once one is tapped.
    private func pick(_ picker: String, _ option: String) throws {
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", picker + ",")).firstMatch
        try require(row.waitForExistence(timeout: 5), "No \(picker) picker")
        row.tap()
        let choice = app.buttons[option].firstMatch
        try require(choice.waitForExistence(timeout: 5), "No \(option) option")
        choice.tap()
        let chosen = app.buttons["\(picker), \(option)"]
        try require(chosen.waitForExistence(timeout: 5), "\(picker) is not \(option)")
    }

    // MARK: - Launch & capture

    private func launch(signedIn: Bool = true) {
        var arguments: [String: String] = [:]
        if signedIn {
            arguments["bug-coffee.uid"] = DemoData.uid
            arguments["bug-coffee.email"] = DemoData.email
            arguments["bug-coffee.stamps"] = String(DemoData.stamps)
            arguments["bug-coffee.qr"] = "<" + DemoData.qrPNGHex + ">"
        } else {
            arguments["bug-coffee.uid"] = "\"\""
            arguments["bug-coffee.qr"] = "<>"
        }
        app.launchArguments = arguments.flatMap { ["-" + $0.key, $0.value] }
        app.launch()
    }

    /// Saves the screen to the output directory and attaches it to the test
    /// result too.
    private func capture(_ name: String) async throws {
        // Let the push animation and scroll settle.
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let png = XCUIScreen.main.screenshot().pngRepresentation

        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let directory = Self.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// Fails the test at the caller's line and stops it — async tests don't
    /// stop on `continueAfterFailure = false` alone.
    private func require(_ condition: Bool, _ message: String = "Requirement failed",
                         file: StaticString = #filePath, line: UInt = #line) throws {
        guard condition else {
            XCTFail(message, file: file, line: line)
            throw RequirementFailed(message: message)
        }
    }

    private struct RequirementFailed: Error { let message: String }

    /// `<root>/<device>`, as in the iPhone `ScreenshotTests`: the root is
    /// `SCREENSHOTS_DIR` (passed as `TEST_RUNNER_SCREENSHOTS_DIR`), else
    /// `docs/screenshots` in this repo; the folder is the simulator's name,
    /// e.g. `apple-watch-series-11-46mm`.
    private static var outputDirectory: URL {
        let environment = ProcessInfo.processInfo.environment
        let root: URL
        if let custom = environment["SCREENSHOTS_DIR"], !custom.isEmpty {
            root = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // BugWalletWatchUITests/
                .deletingLastPathComponent()   // repo root
                .appendingPathComponent("docs/screenshots", isDirectory: true)
        }
        let device = environment["SIMULATOR_DEVICE_NAME"] ?? "apple-watch"
        return root.appendingPathComponent(device.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-"))
    }
}

/// The same made-up customer as the iPhone screenshots.
private enum DemoData {
    static let uid = "Qm3xT8vLr2WdK9pZ4aYc7NfE1sH6"
    static let email = "ana@example.com"
    static let stamps = 6

    /// The loyalty QR for `uid` as the phone would sync it (CIQRCodeGenerator,
    /// correction level H), at one pixel per module — the watch draws it with
    /// `.interpolation(.none)`, so it scales up sharp. CoreImage isn't on
    /// watchOS, so it's generated on a Mac and pasted here; regenerate it if
    /// `uid` changes.
    static let qrPNGHex = """
    89504e470d0a1a0a0000000d49484452000000230000002308060000001ed9b359000000017352474200aece1ce9\
    00000038655849664d4d002a00000008000187690004000000010000001a000000000002a00200040000000100000023\
    a00300040000000100000023000000009b74619d000002b4494441545809cdd45172db400c03d0bad3fb5f390da47912\
    c4ec3af96b39637309022065497e7d7cc6afff24fe648fd7ebb55d27bba66f67e7558e09be731b7f37e75866250c466c\
    c06ea11ee88ccb472de3e9275fcb3498738b2ce5d7487f15d1e0c82b1ebff47aceef1579620486e9778d935e2fd267ba\
    5dfed1326dd80bb8c2992d44a7bf5b02feb84d7d7508c92bdca0e64dae25a67ed63cae6508353a1b2c1baa9669ded5e9\
    ede25866b7698b7a40f8eacef83bbf1d4eb77d6632249f449b34661166966c8e5e327c97afdbd4e49c2d60a041e925e0\
    8c61c9b83cba6e3e0dde631960480903cfea1ea24e9e9a60749d83272c66a9d61fb74963e6293cedee61a95b93733e74\
    9d7b689fdbe3ed036c10d30819bdeb85b70a9af47836f6fa043f1a6822012c79c50dbe8bf0e323e861dd7f3c33112059\
    444db4c20d92a726383d0eacebc7abcd04a16b4ba4e76c009e4c2f87d7d13c5ee93f7e99295a195820bd36ea01ed830f\
    9b1a78fcae676665d658c809e667757fb7a98172583ff13a6e538b6efb73b021c91669acf9064e5e38f4cd77e677dc26\
    85ccf43b1317811fbd73b47d9e3db3e463d6a7e07aef089a1052a268c7559ee8f3b981adf8f4bcd5ad79fc034f42ea89\
    1934f1e6ae7a59c2221698f5e3d50e2904c66d308596929bcb47e6899b9cc89cf6fdf26a2358e8949ddf84e9cd689de1\
    933f39f168afebd59e8dd4d34c9d5e82115c7d76ef6ffd1bb97f955ef07ab55746c19063a466ba1aa297dc7dda64d1de\
    c11eaf36526726316ef1ceb479cd8fa79eb339bcae670680d00257d866787a06f391f1927718df6b9990194f610f22c4\
    ed01cedda385c53b31b9c1bebcda015741cc3cd979f2672f7542ce39cb5910fee36518240b666a798567e0c42d017fdc\
    264da69d091acb796ac233b873eb6870f5ae6576c3109399746e43e7f6b2101f350f9af48f3f3dc47f9dff022886e259\
    b5c4b4080000000049454e44ae426082
    """
}
