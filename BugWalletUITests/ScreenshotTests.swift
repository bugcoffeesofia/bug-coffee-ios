import Foundation
import XCTest

/// Walks the app's main screens and saves a PNG of each into
/// `docs/screenshots/<device>/`, for the docs (see docs/09-screenshots.md).
/// On iPad every screen is captured twice, `-portrait` and `-landscape`,
/// rotating in place so the screen state (an open sheet, the bean page) is kept.
///
/// Run with `Scripts/take_screenshots.sh`, which picks a simulator and pins the
/// status bar so the images don't churn between runs.
///
/// Nothing here signs in or touches the network, and nothing is written to the
/// simulator: the account, stamps, favorites and tasting diary are all handed
/// to the app as launch arguments. Those land in the argument domain, which
/// overrides both standard and App Group defaults for this launch only — so a
/// real login or diary on the simulator is left as it was.
@MainActor
final class ScreenshotTests: XCTestCase {
    private let app = XCUIApplication()

    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Screens

    func test01Login() async throws {
        launch(signedIn: false)
        try require(app.buttons["Sign In"].waitForExistence(timeout: 10))
        try await snapshot("01-login")
    }

    func test02Card() async throws {
        launch()
        try require(app.staticTexts["Show this to the barista"].waitForExistence(timeout: 10))
        try await snapshot("02-card")
    }

    func test03Products() async throws {
        launch()
        try openProducts()
        try await snapshot("03-products")
    }

    func test04BeanPage() async throws {
        launch()
        try openProducts()
        try openBean("Kultura House Blend")
        try await snapshot("04-bean-page")
    }

    func test05TastingEditor() async throws {
        launch()
        try openProducts()
        try openBean("Kultura House Blend")
        let addCup = app.buttons["Add a cup"]
        scrollTo(addCup)
        addCup.tap()
        try require(app.staticTexts["How was it?"].waitForExistence(timeout: 5)
                    || app.staticTexts["HOW WAS IT?"].waitForExistence(timeout: 1))
        try await snapshot("05-tasting-editor")
    }

    func test06BlendFinder() async throws {
        launch()
        try openProducts()
        app.buttons["Find my blend"].firstMatch.tap()
        let chocolatey = app.buttons["Chocolate & nuts"].firstMatch
        try require(chocolatey.waitForExistence(timeout: 5))
        chocolatey.tap()
        try await snapshot("06-blend-finder")
    }

    // MARK: - Navigation

    private func openProducts() throws {
        let tab = app.tabBars.buttons["Products"].exists
            ? app.tabBars.buttons["Products"]
            : app.buttons["Products"].firstMatch
        try require(tab.waitForExistence(timeout: 10))
        tab.tap()
        try require(app.navigationBars["Products"].waitForExistence(timeout: 5))
    }

    private func openBean(_ name: String) throws {
        // The list is lazy, so rows below the fold don't exist until scrolled
        // to. On iPhone the row's text is folded into its NavigationLink's
        // label (a button); in the iPad sidebar the row is a selectable cell.
        let label = NSPredicate(format: "label CONTAINS %@", name)
        let list = app.collectionViews.containing(NSPredicate(format: "label CONTAINS 'Flat White'")).firstMatch
        let row = firstExisting(app.buttons.matching(label).firstMatch,
                                app.cells.containing(label).firstMatch,
                                in: list)
        try require(row.exists, "No row for \(name)")
        row.tap()
        try require(app.navigationBars[name].waitForExistence(timeout: 5))
    }

    /// Swipes `container` until one of the candidates is on screen, and
    /// returns it (or the first candidate, which then doesn't exist).
    private func firstExisting(_ candidates: XCUIElement..., in container: XCUIElement,
                               attempts: Int = 8) -> XCUIElement {
        for attempt in 0...attempts {
            if let hit = candidates.first(where: { $0.exists && $0.isHittable }) { return hit }
            if attempt < attempts { (container.exists ? container : app).swipeUp() }
        }
        return candidates[0]
    }

    private func scrollTo(_ element: XCUIElement) {
        // Swipe the list the element lives in — on iPad the middle of the
        // screen can be a different column.
        let container = app.collectionViews.containing(NSPredicate(format: "label == %@", element.label)).firstMatch
        _ = firstExisting(element, in: container)
    }

    // MARK: - Launch & capture

    /// Launches with a demo account and demo data in the argument domain.
    /// `signedIn: false` blanks the UID instead, which shows the login screen.
    private func launch(signedIn: Bool = true) {
        var arguments: [String: String] = [
            // Never start the App Check WebView (it needs a refresh token).
            "bug-coffee.refresh": "\"\"",
        ]
        if signedIn {
            arguments["bug-coffee.uid"] = DemoData.uid
            arguments["bug-coffee.email"] = DemoData.email
            arguments["bug-coffee.stamps"] = String(DemoData.stamps)
            arguments["bug-coffee.favorites"] = "(" + DemoData.favorites.joined(separator: ",") + ")"
            arguments["bug-coffee.blend-journal"] = "<" + DemoData.journalJSON.hex + ">"
        } else {
            arguments["bug-coffee.uid"] = "\"\""
        }
        app.launchArguments = arguments.flatMap { ["-" + $0.key, $0.value] }
        app.launch()
    }

    /// Captures the current screen as `<name>.png` — on iPad as
    /// `<name>-portrait.png` and `<name>-landscape.png`.
    private func snapshot(_ name: String) async throws {
        guard isPad else {
            try await capture(name)
            return
        }
        for (orientation, suffix) in [(UIDeviceOrientation.portrait, "portrait"),
                                      (.landscapeLeft, "landscape")] {
            XCUIDevice.shared.orientation = orientation
            try await capture("\(name)-\(suffix)")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// Saves the screen to the output directory and attaches it to the test
    /// result too.
    private func capture(_ name: String) async throws {
        // Let transitions, rotation and the tab/sheet animations settle.
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let screenshot = XCUIScreen.main.screenshot()
        let png = Self.upright(screenshot.image)

        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let directory = Self.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// In landscape the capture keeps the display's native (portrait) pixels
    /// and only tags the image as rotated — which `pngData()` drops. Redraw it
    /// so the rotation is baked into the PNG.
    static func upright(_ image: UIImage) -> Data {
        guard image.imageOrientation != .up else { return image.pngData()! }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).pngData { _ in
            image.draw(at: .zero)
        }
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

    /// `<root>/<device>`: the root is `SCREENSHOTS_DIR` (pass it as
    /// `TEST_RUNNER_SCREENSHOTS_DIR` to xcodebuild), else `docs/screenshots` in
    /// this repo; the device folder is `SCREENSHOTS_DEVICE` if set, else the
    /// simulator's name, e.g. `iphone-17-pro`. The simulator's test runner can
    /// write straight to the Mac's file system, so the source path works as-is.
    static var outputDirectory: URL {
        let environment = ProcessInfo.processInfo.environment
        let root: URL
        if let custom = environment["SCREENSHOTS_DIR"], !custom.isEmpty {
            root = URL(fileURLWithPath: custom, isDirectory: true)
        } else {
            root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // BugWalletUITests/
                .deletingLastPathComponent()   // repo root
                .appendingPathComponent("docs/screenshots", isDirectory: true)
        }
        let device = [environment["SCREENSHOTS_DEVICE"], environment["SIMULATOR_DEVICE_NAME"]]
            .compactMap { $0 }.first { !$0.isEmpty } ?? UIDevice.current.model
        return root.appendingPathComponent(deviceFolder(device))
    }

    /// "iPad mini (A17 Pro)" → "ipad-mini-a17-pro".
    private static func deviceFolder(_ name: String) -> String {
        name.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: "-")
    }
}

/// A made-up customer. The UID is not a real account.
private enum DemoData {
    static let uid = "Qm3xT8vLr2WdK9pZ4aYc7NfE1sH6"
    static let email = "ana@example.com"
    static let stamps = 6
    static let favorites = ["flw", "kul"]

    /// The tasting diary as the app stores it: `[beanID: {entries: [...]}]`,
    /// dates as seconds since 2001-01-01 (JSONEncoder's default).
    static var journalJSON: Data {
        func cup(_ day: String, rating: Int, method: String, place: String,
                 grind: String = "", note: String = "") -> [String: Any] {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withFullDate]
            let date = formatter.date(from: day)!
            return ["id": UUID().uuidString, "date": date.timeIntervalSinceReferenceDate,
                    "rating": rating, "method": method, "place": place,
                    "grind": grind, "note": note]
        }
        let journal: [String: Any] = [
            "kul": ["entries": [
                cup("2026-09-10", rating: 5, method: "flatWhite", place: "bugCoffee",
                    note: "Chocolate all the way through the milk."),
                cup("2026-09-06", rating: 4, method: "mokaPot", place: "home",
                    grind: "medium-fine", note: "A bit bitter — pull it off the heat sooner."),
                cup("2026-08-30", rating: 4, method: "espresso", place: "bugCoffee"),
            ]],
            "sir": ["entries": [
                cup("2026-09-02", rating: 4, method: "v60", place: "home",
                    grind: "22 clicks", note: "Bright, red apple."),
            ]],
        ]
        return try! JSONSerialization.data(withJSONObject: journal)
    }
}

private extension Data {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
