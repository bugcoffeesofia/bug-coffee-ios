import Foundation
import Testing
import WatchConnectivity
import WebKit
@testable import BugWallet

extension AppStateTests {
    @MainActor @Suite struct FirebaseAuthTests {
        private func signIn(_ reply: @escaping (URLRequest) -> StubURLProtocol.Reply) async throws -> (Account, [URLRequest]) {
            let (session, id) = StubURLProtocol.session(reply)
            let account = try await FirebaseAuth.signIn(email: "bug@example.com", password: "pw", session: session)
            return (account, StubURLProtocol.recorded(id))
        }

        private func failure(_ reply: @escaping (URLRequest) -> StubURLProtocol.Reply) async -> Error? {
            do {
                _ = try await signIn(reply)
                return nil
            } catch {
                return error
            }
        }

        @Test func postsCredentialsToIdentityToolkit() async throws {
            let (account, requests) = try await signIn { _ in
                .http(status: 200, body: json(["localId": "uid-1", "email": "Bug@Example.com",
                                               "idToken": "id-1", "refreshToken": "rt-1"]))
            }
            #expect(account == Account(uid: "uid-1", email: "Bug@Example.com", idToken: "id-1", refreshToken: "rt-1"))

            let request = try #require(requests.first)
            #expect(request.httpMethod == "POST")
            #expect(request.url?.host == "identitytoolkit.googleapis.com")
            #expect(request.url?.query == "key=\(FirebaseAuth.apiKey)")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let bodyData = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            #expect(body["email"] as? String == "bug@example.com")
            #expect(body["password"] as? String == "pw")
            #expect(body["returnSecureToken"] as? Bool == true)
        }

        @Test func missingEmailAndRefreshTokenFallBack() async throws {
            let (account, _) = try await signIn { _ in .http(status: 200, body: json(["localId": "u", "idToken": "t"])) }
            #expect(account.email == "bug@example.com")
            #expect(account.refreshToken == "")
        }

        @Test func firebaseErrorCodeIsTrimmedOfDetails() async {
            let error = await failure { _ in
                .http(status: 400, body: json(["error": ["message": "INVALID_PASSWORD : The password is invalid."]]))
            }
            guard case .firebase("INVALID_PASSWORD")? = error as? AuthError else {
                Issue.record("unexpected \(String(describing: error))")
                return
            }
        }

        @Test func errorWithoutMessageIsUnknown() async {
            let error = await failure { _ in .http(status: 500, body: json(["error": [:]])) }
            guard case .firebase("UNKNOWN_ERROR")? = error as? AuthError else {
                Issue.record("unexpected \(String(describing: error))")
                return
            }
        }

        @Test(arguments: [
            StubURLProtocol.Reply.http(status: 200, body: Data("<html>".utf8)),
            .http(status: 200, body: json(["localId": "u"])),
            .http(status: 200, body: json(["idToken": "t"])),
            .nonHTTP(body: json(["localId": "u", "idToken": "t"])),
        ])
        func unusableResponsesAreBadResponse(_ reply: StubURLProtocol.Reply) async {
            let error = await failure { _ in reply }
            guard case .badResponse? = error as? AuthError else {
                Issue.record("unexpected \(String(describing: error))")
                return
            }
        }

        @Test func transportFailuresAreNetworkErrors() async {
            let error = await failure { _ in .failure(URLError(.notConnectedToInternet)) }
            guard case .network? = error as? AuthError else {
                Issue.record("unexpected \(String(describing: error))")
                return
            }
        }
    }

    @MainActor @Suite struct WatchSyncTests {
        init() { ScratchDefaults.install() }

        @Test func syncMergesIdentityQRAndStamps() throws {
            StampStore.setCount(5)
            let sync = WatchSync.shared
            sync.sync(uid: "uid-w", email: "w@example.com")
            #expect(sync.context[SharedKeys.uid] as? String == "uid-w")
            #expect(sync.context[SharedKeys.email] as? String == "w@example.com")
            #expect(sync.context[SharedKeys.stamps] as? Int == 5)
            let png = try #require(sync.context[SharedKeys.qr] as? Data)
            #expect(ImageDecode.cgImage(fromPNG: png) != nil)

            // A stamp update keeps the rest of the payload.
            sync.syncStamps(2)
            #expect(sync.context[SharedKeys.stamps] as? Int == 2)
            #expect(sync.context[SharedKeys.uid] as? String == "uid-w")
        }

        @Test func activationStateDrivesFlushing() {
            let sync = WatchSync.shared
            sync.sync(uid: "uid-a", email: "")
            sync.session(WCSession.default, activationDidCompleteWith: .activated, error: nil)
            #expect(sync.activated)
            // With no paired watch the update throws; the context stays for a retry.
            sync.syncStamps(3)
            #expect(sync.context[SharedKeys.stamps] as? Int == 3)
            sync.session(WCSession.default, activationDidCompleteWith: .notActivated, error: nil)
            #expect(!sync.activated)
            sync.sessionDidBecomeInactive(WCSession.default)
            sync.sessionDidDeactivate(WCSession.default)
        }
    }

    @MainActor @Suite struct StampWebSyncTests {
        private let tokenAccount = Account(uid: "uid-web", email: "web@example.com", idToken: "id-0", refreshToken: "rt-0")

        init() { ScratchDefaults.install() }

        @Test(arguments: [
            (#"{"fields":{"stamps_count":{"integerValue":"3"}}}"#, 3),
            (#"{"fields":{"stamps_count":{"integerValue":4}}}"#, 4),
            (#"{"fields":{"stamps_count":{"doubleValue":5.0}}}"#, 5),
        ])
        func parsesFirestoreIntegers(body: String, expected: Int) {
            #expect(StampWebSync.parseStampCount(Data(body.utf8)) == expected)
        }

        @Test(arguments: [
            "not json", #"{}"#, #"{"fields":{}}"#, #"{"fields":{"stamps_count":{"stringValue":"3"}}}"#,
            #"{"fields":{"stamps_count":{"integerValue":"three"}}}"#,
        ])
        func rejectsAnythingElse(_ body: String) {
            #expect(StampWebSync.parseStampCount(Data(body.utf8)) == nil)
        }

        @Test func withoutARefreshTokenItStaysManual() {
            let sync = Fixtures.webSync()
            sync.start(account: Fixtures.account)
            #expect(sync.status == "no token — manual count only")
            #expect(sync.backendCount == nil)
        }

        @Test func countMessagesAreClampedAndApplied() {
            let sync = Fixtures.webSync()
            sync.onMessage(["type": "count", "count": 12])
            #expect(sync.backendCount == 9)
            #expect(sync.status == "web: 9/9")
            #expect(StampStore.count == 9)
            #expect(WatchSync.shared.context[SharedKeys.stamps] as? Int == 9)
            sync.onMessage(["type": "count", "count": -2])
            #expect(sync.backendCount == 0)
            // Malformed or unknown messages change nothing.
            sync.onMessage(["type": "count", "count": "7"])
            sync.onMessage(["type": "log", "msg": "hello"])
            sync.onMessage(["type": "mystery"])
            sync.onMessage([:])
            #expect(sync.backendCount == 0)
        }

        @Test func seededReloadsOnlyOnce() {
            let sync = Fixtures.webSync(handler: TestSchemeHandler(pages: ["/app": "<p>hi</p>"]))
            sync.start(account: tokenAccount)
            #expect(sync.status == "loading web app…")
            sync.onMessage(["type": "seeded"])
            #expect(sync.status == "seeded — opening card…")
            sync.onMessage(["type": "count", "count": 1])
            sync.onMessage(["type": "seeded"])
            #expect(sync.status == "web: 1/9")
            sync.stop()
            #expect(sync.status == "idle")
        }

        private func firestore(_ reply: @escaping (URLRequest) -> StubURLProtocol.Reply) -> (StampWebSync, String) {
            let (session, id) = StubURLProtocol.session(reply)
            let sync = Fixtures.webSync(urlSession: session, handler: TestSchemeHandler(pages: ["/app": "<p>hi</p>"]))
            sync.start(account: tokenAccount)
            return (sync, id)
        }

        @Test func appCheckTokenTriggersANativeRead() async throws {
            let (sync, id) = firestore { _ in
                .http(status: 200, body: json(["fields": ["stamps_count": ["integerValue": "6"]]]))
            }
            sync.onMessage(["type": "appcheck", "token": "ac-1", "idToken": "id-1"])
            #expect(await eventually { sync.status == "native: 6/9" })
            #expect(sync.backendCount == 6)

            let request = try #require(StubURLProtocol.recorded(id).first)
            #expect(request.url?.absoluteString ==
                    "https://firestore.googleapis.com/v1/projects/bug-coffee/databases/(default)/documents/user-stamps/uid-web")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer id-1")
            #expect(request.value(forHTTPHeaderField: "X-Firebase-AppCheck") == "ac-1")
            sync.stop()
        }

        @Test func nativeReadFallsBackToTheAccountsIDToken() async throws {
            let (sync, id) = firestore { _ in .http(status: 200, body: json(["fields": [:]])) }
            sync.onMessage(["type": "appcheck", "token": "ac-2", "idToken": ""])
            #expect(await eventually { sync.status == "native read: no stamps_count field" })
            #expect(StubURLProtocol.recorded(id).first?.value(forHTTPHeaderField: "Authorization") == "Bearer id-0")
            sync.stop()
        }

        @Test func nativeReadRefusedKeepsTheWebFallback() async {
            let (sync, _) = firestore { _ in .http(status: 403, body: Data()) }
            sync.onMessage(["type": "appcheck", "token": "ac-3"])
            #expect(await eventually { sync.status == "native read 403 — using web fallback" })
            sync.stop()
        }

        @Test func nativeReadTransportFailure() async {
            let (sync, _) = firestore { _ in .failure(URLError(.timedOut)) }
            sync.onMessage(["type": "appcheck", "token": "ac-4"])
            #expect(await eventually { sync.status == "native read failed — using web fallback" })
            sync.stop()
        }

        @Test func noAppCheckTokenMeansNoRead() async {
            let (sync, id) = firestore { _ in .http(status: 200, body: Data()) }
            sync.onMessage(["type": "appcheck", "token": "", "idToken": "id-9"])
            #expect(sync.status == "captured App Check token")
            try? await Task.sleep(nanoseconds: 200_000_000)
            #expect(StubURLProtocol.recorded(id).isEmpty)
            sync.stop()
        }

        @Test func noIDTokenAnywhereMeansNoRead() async {
            let (session, id) = StubURLProtocol.session { _ in .http(status: 200, body: Data()) }
            let sync = Fixtures.webSync(urlSession: session, handler: TestSchemeHandler(pages: ["/app": ""]))
            sync.start(account: Account(uid: "u", email: "", idToken: "", refreshToken: "rt"))
            sync.onMessage(["type": "appcheck", "token": "ac-5"])
            try? await Task.sleep(nanoseconds: 200_000_000)
            #expect(StubURLProtocol.recorded(id).isEmpty)
            sync.stop()
        }

        @Test func nothingToReadWithoutAnAccount() async {
            let (session, id) = StubURLProtocol.session { _ in .http(status: 200, body: Data()) }
            let sync = Fixtures.webSync(urlSession: session)
            sync.onMessage(["type": "appcheck", "token": "ac-6", "idToken": "id-6"])
            try? await Task.sleep(nanoseconds: 200_000_000)
            #expect(StubURLProtocol.recorded(id).isEmpty)
        }

        /// End to end through the injected page script: the page's own Firestore
        /// traffic carries the App Check header, which the hooks lift and post back.
        @Test func pageScriptCapturesTheAppCheckHeader() async throws {
            let page = """
            <html><body><script>
              window.webkit.messageHandlers.stampsync.postMessage('not a dictionary');
              fetch('bugtest://app/firestore/listen.json', {
                headers: { 'X-Firebase-AppCheck': 'ac-page', 'Authorization': 'Bearer id-page' }
              });
            </script></body></html>
            """
            let handler = TestSchemeHandler(pages: [
                "/app": page,
                "/firestore/listen.json": #"{"documentChange":{"fields":{"stamps_count":{"integerValue":"2"}}}}"#,
            ])
            let (session, id) = StubURLProtocol.session { _ in
                .http(status: 200, body: json(["fields": ["stamps_count": ["integerValue": "8"]]]))
            }
            let sync = Fixtures.webSync(urlSession: session, handler: handler)
            sync.start(account: tokenAccount)
            #expect(await eventually { !StubURLProtocol.recorded(id).isEmpty })
            let request = try #require(StubURLProtocol.recorded(id).first)
            #expect(request.value(forHTTPHeaderField: "X-Firebase-AppCheck") == "ac-page")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer id-page")
            // The scraped count from the page's own response arrives too.
            #expect(await eventually { sync.status.hasPrefix("native:") || sync.status.hasPrefix("web:") })
            sync.stop()
        }

        @Test func pageLoadFailureIsReported() async {
            let sync = Fixtures.webSync(handler: TestSchemeHandler(pages: [:]))
            sync.start(account: tokenAccount)
            #expect(await eventually { sync.status.hasPrefix("web load failed") })
            sync.stop()
        }

        @Test func navigationFailureAfterCommitIsReported() {
            let sync = Fixtures.webSync()
            sync.webView(WKWebView(), didFail: nil, withError: URLError(.cancelled))
            #expect(sync.status.hasPrefix("web load failed: "))
        }
    }
}
