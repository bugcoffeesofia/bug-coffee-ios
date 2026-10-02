import Foundation
import SwiftUI
import Testing
import UIKit
import WebKit
@testable import BugWallet

/// Tests that touch process-wide state — the App Group defaults, the watch
/// link, URL stubs — nest under this suite so they run one at a time. Pure
/// value tests live outside it and run in parallel.
@MainActor
@Suite(.serialized)
struct AppStateTests {}

// MARK: - Defaults

enum ScratchDefaults {
    private static let suiteName = "BugWalletTests.scratch"

    /// A clean defaults suite installed as the App Group defaults, so the stores
    /// never read or write the simulator's real stamps, favorites or diary.
    @discardableResult
    static func install() -> UserDefaults {
        let defaults = fresh(suiteName)
        SharedKeys.groupDefaults = defaults
        return defaults
    }

    /// A second, empty suite standing in for `UserDefaults.standard`.
    static func standard() -> UserDefaults {
        fresh("BugWalletTests.standard")
    }

    private static func fresh(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}

// MARK: - Fixtures

enum Fixtures {
    /// No refresh token, so a Session built with it never starts a WebView.
    static let account = Account(uid: "uid-123", email: "bug@example.com", idToken: "", refreshToken: "")

    static func tasting(rating: Int = 0, daysAgo: Double = 0, method: BrewMethod = .espresso,
                        place: BrewPlace = .bugCoffee, grind: String = "", note: String = "") -> TastingEntry {
        TastingEntry(date: Date(timeIntervalSince1970: 1_750_000_000 - daysAgo * 86_400),
                     rating: rating, method: method, place: place, grind: grind, note: note)
    }

    /// A StampWebSync that loads nothing from the internet and keeps its web
    /// data out of the app's persistent store.
    @MainActor
    static func webSync(origin: String = "bugtest://app",
                        urlSession: URLSession = .shared,
                        handler: WKURLSchemeHandler? = nil) -> StampWebSync {
        StampWebSync(origin: origin, urlSession: urlSession) { config in
            config.websiteDataStore = .nonPersistent()
            if let handler { config.setURLSchemeHandler(handler, forURLScheme: "bugtest") }
        }
    }
}

struct TestError: LocalizedError, Equatable {
    var message = "boom"
    var errorDescription: String? { message }
}

/// Polls `condition` on the main actor until it holds or `timeout` passes.
@MainActor
func eventually(timeout: TimeInterval = 10, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return true
}

// MARK: - Network stubs

/// Answers URLSession requests from a per-session handler, so tests never hit
/// Identity Toolkit or Firestore.
final class StubURLProtocol: URLProtocol {
    enum Reply {
        case http(status: Int, body: Data)
        case nonHTTP(body: Data)
        case failure(Error)
    }

    private static let lock = NSLock()
    private static var handlers: [String: (URLRequest) -> Reply] = [:]
    private static var requests: [String: [URLRequest]] = [:]
    private static let header = "X-Stub-Session"

    /// A session whose every request is answered by `reply`.
    static func session(_ reply: @escaping (URLRequest) -> Reply) -> (URLSession, id: String) {
        let id = UUID().uuidString
        lock.withLock { handlers[id] = reply }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = [header: id]
        return (URLSession(configuration: config), id)
    }

    static func recorded(_ id: String) -> [URLRequest] {
        lock.withLock { requests[id] ?? [] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let id = request.value(forHTTPHeaderField: Self.header) ?? ""
        var recorded = request
        // URLSession moves the body into a stream before the protocol sees it.
        if recorded.httpBody == nil, let stream = request.httpBodyStream {
            recorded.httpBody = Data(reading: stream)
        }
        let handler = Self.lock.withLock { () -> ((URLRequest) -> Reply)? in
            Self.requests[id, default: []].append(recorded)
            return Self.handlers[id]
        }
        switch handler?(recorded) ?? .failure(URLError(.notConnectedToInternet)) {
        case let .http(status, body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .nonHTTP(body):
            let response = URLResponse(url: request.url!, mimeType: nil, expectedContentLength: body.count, textEncodingName: nil)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension Data {
    init(reading stream: InputStream) {
        self.init()
        stream.open()
        defer { stream.close() }
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            append(buffer, count: read)
        }
    }
}

func json(_ object: Any) -> Data {
    try! JSONSerialization.data(withJSONObject: object)
}

// MARK: - WebKit

/// Serves `bugtest://` pages to the StampWebSync WebView: a path → response
/// map, or a navigation failure for anything unmapped.
final class TestSchemeHandler: NSObject, WKURLSchemeHandler {
    private let pages: [String: String]

    init(pages: [String: String]) { self.pages = pages }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url, let page = pages[url.path] else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime = url.path.hasSuffix(".json") ? "application/json" : "text/html"
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                        headerFields: ["Content-Type": mime, "Access-Control-Allow-Origin": "*"])!)
        task.didReceive(Data(page.utf8))
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

// MARK: - Rendering

/// Puts a SwiftUI view on screen in its own window and lets it lay out, so
/// the body (and everything it builds) actually runs.
@MainActor
final class Hosted<Content: View> {
    let window: UIWindow
    let controller: UIHostingController<Content>

    init(_ view: Content, size: CGSize = CGSize(width: 390, height: 844),
         horizontalSizeClass: UIUserInterfaceSizeClass = .compact) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
        window.frame = CGRect(origin: .zero, size: size)
        controller = UIHostingController(rootView: view)
        if #available(iOS 17, *) {
            controller.traitOverrides.horizontalSizeClass = horizontalSizeClass
        }
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
    }

    /// Spins the run loop so state changes, sheets and lazy rows settle.
    func settle(_ seconds: Double = 0.4) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        controller.view.setNeedsLayout()
        controller.view.layoutIfNeeded()
    }

    func tearDown() {
        controller.presentedViewController?.dismiss(animated: false)
        window.isHidden = true
        window.rootViewController = nil
    }

    /// Every UIView of type `T` in the hosted hierarchy (presented sheets included).
    func views<T: UIView>(of type: T.Type) -> [T] {
        var found: [T] = []
        func walk(_ view: UIView) {
            if let match = view as? T { found.append(match) }
            view.subviews.forEach(walk)
        }
        walk(window)
        return found
    }
}

/// Renders `view`, waits for it to settle, and tears the window down.
@MainActor
func render<V: View>(_ view: V, size: CGSize = CGSize(width: 390, height: 844),
                     horizontalSizeClass: UIUserInterfaceSizeClass = .compact,
                     settle seconds: Double = 0.4,
                     inspect: (Hosted<V>) async throws -> Void = { _ in }) async throws {
    let hosted = Hosted(view, size: size, horizontalSizeClass: horizontalSizeClass)
    await hosted.settle(seconds)
    try await inspect(hosted)
    hosted.tearDown()
}
