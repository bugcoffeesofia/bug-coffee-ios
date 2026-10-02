import XCTest

/// Screenshots of the Stamp Card home-screen widget, the real thing: it sets
/// the stamp count in the app, then drives SpringBoard to add the small and
/// medium widgets and captures the widget gallery and the home screen.
///
/// Unlike `ScreenshotTests` this *does* change the simulator — the App Group
/// stamp count and the home screen layout — so it only runs when
/// `SCREENSHOTS_WIDGETS=1` is set. `Scripts/take_screenshots.sh` sets it and
/// runs this on a throwaway simulator that it deletes afterwards; anywhere else
/// (⌘U) the tests are skipped.
@MainActor
final class WidgetScreenshotTests: XCTestCase {
    private let app = XCUIApplication()
    private let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

    private static let stamps = 6

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SCREENSHOTS_WIDGETS"] == "1",
                          "Changes the home screen; run via Scripts/take_screenshots.sh")
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "Widget shots are iPhone only")
    }

    func test07Widgets() async throws {
        try setStampCount(Self.stamps)

        XCUIDevice.shared.press(.home)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try enterEditMode()

        // Small first, then medium: each new widget goes to the top of the
        // page, so the medium one ends up above the small one.
        try await openGallery()
        try await capture("07-widget-gallery")
        try addWidget(size: "Small")

        try await Task.sleep(nanoseconds: 1_500_000_000)
        try await openGallery()
        springboard.swipeLeft()   // size pages: small → medium
        try await Task.sleep(nanoseconds: 1_000_000_000)
        try addWidget(size: "Medium")

        try await Task.sleep(nanoseconds: 1_500_000_000)
        let done = springboard.buttons["Done"]
        if done.exists { done.tap() }
        try await capture("08-widgets-home")
        try cropWidgets()
    }

    // MARK: - Steps

    /// Signs in with the demo account (argument domain) and taps +/- on the
    /// card until it shows `count` — that writes it to the App Group and
    /// reloads the widget. Stamps are *not* passed as an argument here: that
    /// would only shadow the value the widget reads.
    private func setStampCount(_ count: Int) throws {
        app.launchArguments = ["-bug-coffee.uid", "Qm3xT8vLr2WdK9pZ4aYc7NfE1sH6",
                               "-bug-coffee.email", "ana@example.com",
                               "-bug-coffee.refresh", "\"\""]
        app.launch()
        let counter = app.staticTexts.matching(NSPredicate(format: "label ENDSWITH ' / 9'")).firstMatch
        try require(counter.waitForExistence(timeout: 10), "No stamp counter on the card")
        for _ in 0..<20 {
            guard let shown = Int(counter.label.prefix { $0.isNumber }), shown != count else { break }
            app.buttons[shown < count ? "Add" : "Remove"].tap()
        }
        try require(counter.label == "\(count) / 9", "Stamp count stuck at \(counter.label)")
    }

    /// Jiggle mode. A long press on the home screen's empty space does it
    /// directly; on an icon it opens a menu with "Edit Home Screen" instead.
    private func enterEditMode() throws {
        springboard.icons["Bug Coffee"].firstMatch.press(forDuration: 1.5)
        let editHomeScreen = springboard.buttons["Edit Home Screen"]
        if editHomeScreen.waitForExistence(timeout: 3) { editHomeScreen.tap() }
        try require(springboard.buttons["Edit"].waitForExistence(timeout: 5), "No jiggle mode")
    }

    /// Edit → Add Widget → search "Bug Coffee" → the Stamp Card size pages.
    private func openGallery() async throws {
        springboard.buttons["Edit"].tap()
        let addWidget = springboard.buttons["Add Widget"].firstMatch
        try require(addWidget.waitForExistence(timeout: 5), "No Add Widget menu item")
        addWidget.tap()
        let search = springboard.searchFields["Search Widgets"]
        try require(search.waitForExistence(timeout: 5), "No widget gallery")
        search.tap()
        search.typeText("Bug Coffee")
        let result = springboard.cells["Bug Coffee"].firstMatch
        try require(result.waitForExistence(timeout: 5), "Bug Coffee isn't in the widget gallery")
        result.tap()
        try require(springboard.staticTexts["Stamp Card"].waitForExistence(timeout: 5))
        try await Task.sleep(nanoseconds: 1_000_000_000)
    }

    /// Taps the gallery's "Add Widget" button once the given size page is up.
    /// The button's label starts with an invisible glyph (" Add Widget"), and
    /// each size page is a button whose value is "Widget, Small" / "…, Medium".
    private func addWidget(size: String) throws {
        let page = springboard.buttons.matching(NSPredicate(format: "value == %@", "Widget, \(size)")).firstMatch
        try require(page.waitForExistence(timeout: 5), "No \(size) widget page")
        let add = springboard.buttons.matching(NSPredicate(format: "label ENDSWITH 'Add Widget'")).firstMatch
        try require(add.waitForExistence(timeout: 5), "No Add Widget button")
        add.tap()
    }

    // MARK: - Capture

    private func capture(_ name: String) async throws {
        try await Task.sleep(nanoseconds: 1_500_000_000)
        let png = ScreenshotTests.upright(XCUIScreen.main.screenshot().image)

        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let directory = ScreenshotTests.outputDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// Also saves each widget on its own — cut out of a fresh screenshot, with
    /// a margin of wallpaper around it — as `09-widget-small` and
    /// `10-widget-medium`. The widgets are the "Bug Coffee" elements bigger
    /// than an app icon; their frames include the name label underneath.
    private func cropWidgets() throws {
        // One snapshot of the tree — querying element by element races the
        // home screen settling and fails on elements that went stale.
        func frames(_ node: XCUIElementSnapshot) -> [CGRect] {
            let own = node.label == "Bug Coffee" && node.frame.width > 120 ? [node.frame] : []
            return own + node.children.flatMap(frames)
        }
        let widgets = frames(try springboard.snapshot())
        let small = widgets.first { $0.width < $0.height * 1.5 }
        let medium = widgets.first { $0.width >= $0.height * 1.5 }
        try require(small != nil && medium != nil, "Widgets not found on the home screen: \(widgets)")

        let image = XCUIScreen.main.screenshot().image
        for (name, frame) in [("09-widget-small", small!), ("10-widget-medium", medium!)] {
            // 16 pt of wallpaper around it, less below: the frame already
            // ends with the name label, and the next row's icons start there.
            let rect = CGRect(x: frame.minX - 16, y: frame.minY - 16,
                              width: frame.width + 32, height: frame.height + 22)
                .intersection(CGRect(origin: .zero, size: image.size))
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            let png = UIGraphicsImageRenderer(size: rect.size, format: format).pngData { _ in
                image.draw(at: CGPoint(x: -rect.minX, y: -rect.minY))
            }
            let directory = ScreenshotTests.outputDirectory
            try png.write(to: directory.appendingPathComponent("\(name).png"))
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func require(_ condition: Bool, _ message: String = "Requirement failed",
                         file: StaticString = #filePath, line: UInt = #line) throws {
        guard condition else {
            print(springboard.debugDescription)
            XCTFail(message, file: file, line: line)
            throw RequirementFailed(message: message)
        }
    }

    private struct RequirementFailed: Error { let message: String }
}
