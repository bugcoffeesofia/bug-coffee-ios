import Foundation
import WebKit

/// **Variant 3 — WebView App Check token vendor.**
///
/// The live stamp count lives in Firestore behind Firebase **App Check**, whose
/// only provider for this project is reCAPTCHA v3 — a web-origin provider we
/// cannot reproduce natively (doc §7). This class works around that *without*
/// defeating App Check: it runs the **real web app** (`app.bugcoffee.com`) in an
/// off-screen `WKWebView`, lets that page perform its own legitimate reCAPTCHA
/// attestation, and lifts the resulting `X-Firebase-AppCheck` token (plus the
/// account's `Authorization: Bearer <idToken>`) off the page's own Firestore
/// requests. Native code then makes a plain Firestore REST read carrying those
/// two headers — the App Check token is bound to the Firebase app/project, not
/// to the transport, so a native request presenting it satisfies the
/// `request.app != null` rule the same way the web SDK's request does.
///
/// The scraped `stamps_count` (read straight out of the web app's own Firestore
/// response) is kept as a fallback: if the native read is refused for any
/// reason, the count the page already fetched still updates the card/widget.
///
/// The WebView is seeded to be logged in from the account we already hold
/// natively (Firebase persists auth in IndexedDB), so there is no second login.
@MainActor
final class StampWebSync: NSObject, ObservableObject {
    static let shared = StampWebSync()

    /// The most recent count read from the backend (native read, else scraped).
    /// `CardView` observes this to reflect the live count in the UI.
    @Published private(set) var backendCount: Int?
    /// Human-readable last-sync status, for a small diagnostics line in the UI.
    @Published private(set) var status: String = "idle"

    private let projectId = "bug-coffee"
    private let apiKey = FirebaseAuth.apiKey
    private let origin: String
    private let urlSession: URLSession
    /// Last word on the WebView configuration (after the defaults are set).
    private let configure: ((WKWebViewConfiguration) -> Void)?

    private var webView: WKWebView?
    private var account: Account?
    // The seed writes the auth record to IndexedDB async; we reload `/app` once
    // after it commits so the SDK reads the now-persisted login. This guards
    // that reload against firing more than once.
    private var didReloadForSeed = false

    // The captured credentials from the web app's own traffic. Both are needed
    // for a native Firestore read; the App Check token is short-lived (reCAPTCHA
    // tokens typically last ~30 min), the ID token ~1 h.
    private var appCheckToken: String?
    private var capturedIDToken: String?

    /// The parameters are seams for unit tests (a local page, a stubbed
    /// Firestore, a throwaway data store); the app uses `shared`.
    init(origin: String = "https://app.bugcoffee.com",
         urlSession: URLSession = .shared,
         configure: ((WKWebViewConfiguration) -> Void)? = nil) {
        self.origin = origin
        self.urlSession = urlSession
        self.configure = configure
        super.init()
    }

    // MARK: - Public API

    /// Start (or refresh) a backend sync for `account`. Safe to call on every
    /// login and on launch-with-saved-account. If we have no refresh token we
    /// cannot seed the WebView login, so we simply do nothing (the manual +/-
    /// count remains the source of truth).
    func start(account: Account) {
        self.account = account
        guard !account.refreshToken.isEmpty else {
            status = "no token — manual count only"
            return
        }
        appCheckToken = nil
        capturedIDToken = account.idToken.isEmpty ? nil : account.idToken
        didReloadForSeed = false
        status = "loading web app…"
        loadWebView(for: account)
    }

    /// Tear down the WebView (e.g. on sign-out).
    func stop() {
        webView?.stopLoading()
        webView?.removeFromSuperview()
        webView = nil
        account = nil
        appCheckToken = nil
        capturedIDToken = nil
        status = "idle"
    }

    // MARK: - WebView setup

    private func loadWebView(for account: Account) {
        let controller = WKUserContentController()
        controller.add(Bridge(owner: self), name: "stampsync")
        controller.addUserScript(
            WKUserScript(source: seedAndHookScript(for: account),
                         injectionTime: .atDocumentStart,
                         forMainFrameOnly: false)
        )

        let config = WKWebViewConfiguration()
        config.userContentController = controller
        // Persistent data store so the seeded login (and App Check debug/session
        // state) survive across launches; after the first run the page comes up
        // already authenticated.
        config.websiteDataStore = .default()
        configure?(config)

        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1),
                            configuration: config)
        web.navigationDelegate = self
        // Attach off-screen but *in the window* — a fully detached or hidden
        // WebView gets its timers/JS throttled, which would stall the App Check
        // exchange. 1×1 and nearly transparent keeps it live without being seen.
        web.alpha = 0.01
        web.isUserInteractionEnabled = false
        Self.keyWindow?.addSubview(web)
        self.webView = web

        // Load /app directly. The documentStart script seeds the auth record
        // into IndexedDB (posting `seeded` once the write commits); because the
        // SPA reads its auth persistence asynchronously too, that first load may
        // still come up logged-out. So on the first `seeded` we reload /app once
        // — by then the record is committed to disk, the SDK reads it, the web
        // app boots authenticated, its stamp listener fires, and its Firestore
        // request carries the App Check header we capture.
        web.load(URLRequest(url: URL(string: "\(origin)/app")!))
    }

    func onSeeded() {
        guard !didReloadForSeed else { return }
        didReloadForSeed = true
        status = "seeded — opening card…"
        webView?.load(URLRequest(url: URL(string: "\(origin)/app")!))
    }

    // MARK: - Message handling from the page

    func onMessage(_ body: [String: Any]) {
        switch body["type"] as? String {
        case "seeded":
            onSeeded()

        case "appcheck":
            if let tok = body["token"] as? String, !tok.isEmpty {
                appCheckToken = tok
            }
            if let idt = body["idToken"] as? String, !idt.isEmpty {
                capturedIDToken = idt
            }
            status = "captured App Check token"
            Task { await nativeReadStampCount() }

        case "count":
            // Fallback: the count read straight out of the web app's response.
            if let n = body["count"] as? Int {
                apply(count: n, source: "web")
            }

        case "log":
            #if DEBUG
            print("[StampWebSync] page:", body["msg"] ?? "")
            #endif

        default:
            break
        }
    }

    // MARK: - Native Firestore read (the point of variant 3)

    private func nativeReadStampCount() async {
        guard let account,
              let appCheck = appCheckToken,
              let idToken = capturedIDToken ?? (account.idToken.isEmpty ? nil : account.idToken)
        else { return }

        let path = "projects/\(projectId)/databases/(default)/documents/user-stamps/\(account.uid)"
        guard let url = URL(string: "https://firestore.googleapis.com/v1/\(path)") else { return }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        req.setValue(appCheck, forHTTPHeaderField: "X-Firebase-AppCheck")

        do {
            let (data, resp) = try await urlSession.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            guard code == 200 else {
                status = "native read \(code) — using web fallback"
                return
            }
            if let count = Self.parseStampCount(data) {
                apply(count: count, source: "native")
            } else {
                status = "native read: no stamps_count field"
            }
        } catch {
            status = "native read failed — using web fallback"
        }
    }

    /// Firestore REST returns `{ fields: { stamps_count: { integerValue: "3" } } }`.
    static func parseStampCount(_ data: Data) -> Int? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let fields = json["fields"] as? [String: Any],
            let field = fields["stamps_count"] as? [String: Any]
        else { return nil }
        if let s = field["integerValue"] as? String { return Int(s) }
        if let i = field["integerValue"] as? Int { return i }
        if let d = field["doubleValue"] as? Double { return Int(d) }
        return nil
    }

    // MARK: - Applying a fetched count

    private func apply(count raw: Int, source: String) {
        let count = min(max(raw, 0), StampStore.maxStamps)
        backendCount = count
        status = "\(source): \(count)/\(StampStore.maxStamps)"
        // Feed the existing plumbing: App Group store (→ widget) + watch.
        StampStore.setCount(count)
        WatchSync.shared.syncStamps(count)
    }

    // MARK: - Injected page script (seed login + capture App Check header)

    private func seedAndHookScript(for account: Account) -> String {
        // The account's own values, substituted into the page-world script.
        // These are the user's own credentials for their own account; the web
        // app already stores them in this same IndexedDB.
        let api = jsString(apiKey)
        let uid = jsString(account.uid)
        let email = jsString(account.email)
        let refresh = jsString(account.refreshToken)
        let idtok = jsString(account.idToken)

        return """
        (function () {
          var API_KEY = \(api), UID = \(uid), EMAIL = \(email),
              RT = \(refresh), AT = \(idtok);
          var post = function (m) {
            try { window.webkit.messageHandlers.stampsync.postMessage(m); } catch (e) {}
          };

          // --- 1. Seed Firebase Auth into IndexedDB ---
          // Firebase JS persists the signed-in user in db `firebaseLocalStorageDb`,
          // store `firebaseLocalStorage`, keyed by fbase_key. Writing that record
          // makes the web app come up authenticated. The put is idempotent, so
          // re-running it on the reload is harmless. `seeded` is posted once the
          // transaction commits, which drives Swift's single reload of /app.
          if (RT) {
            var rec = {
              fbase_key: 'firebase:authUser:' + API_KEY + ':[DEFAULT]',
              value: {
                uid: UID, email: EMAIL, emailVerified: true, isAnonymous: false,
                providerData: [{ providerId: 'password', uid: EMAIL,
                  displayName: null, email: EMAIL, phoneNumber: null, photoURL: null }],
                stsTokenManager: {
                  refreshToken: RT,
                  accessToken: AT || '',
                  // Mark the access token as already expired so the SDK refreshes
                  // it from RT on boot (works even when AT is empty/stale).
                  expirationTime: Date.now() - 1000
                },
                createdAt: String(Date.now()), lastLoginAt: String(Date.now()),
                apiKey: API_KEY, appName: '[DEFAULT]'
              }
            };
            var open = indexedDB.open('firebaseLocalStorageDb');
            open.onupgradeneeded = function (e) {
              try { e.target.result.createObjectStore('firebaseLocalStorage', { keyPath: 'fbase_key' }); } catch (x) {}
            };
            open.onsuccess = function (e) {
              var db = e.target.result;
              try {
                var tx = db.transaction('firebaseLocalStorage', 'readwrite');
                tx.objectStore('firebaseLocalStorage').put(rec);
                tx.oncomplete = function () { post({ type: 'seeded' }); };
                tx.onerror = function () { post({ type: 'seeded' }); };
              } catch (x) { post({ type: 'seeded' }); }
            };
            open.onerror = function () { post({ type: 'seeded' }); };
            // Fall through: install the capture hooks synchronously below while
            // the seed write proceeds in the background.
          }

          // --- 2. Capture the App Check token off Firestore traffic ---
          var sent = false;
          var grab = function (headers, url) {
            try {
              if (!headers) return;
              var get = function (k) {
                if (headers.get) return headers.get(k);
                return headers[k] || headers[k.toLowerCase()];
              };
              var ac = get('X-Firebase-AppCheck');
              var auth = get('Authorization');
              var idt = auth && auth.indexOf('Bearer ') === 0 ? auth.slice(7) : null;
              if (ac && !sent) {
                sent = true;
                post({ type: 'appcheck', token: ac, idToken: idt || '' });
              }
            } catch (e) {}
          };

          // Read stamps_count out of a Firestore response body (fallback path).
          var scan = function (text) {
            try {
              if (!text || text.indexOf('stamps_count') === -1) return;
              // WebChannel responses are chunked JSON arrays; a regex is robust
              // to the framing. `stamps_count` is followed by its integerValue.
              var m = text.match(/stamps_count[\\s\\S]*?integerValue[":\\s]*"?(\\d+)/);
              if (m) post({ type: 'count', count: parseInt(m[1], 10) });
            } catch (e) {}
          };

          // Hook fetch.
          var of = window.fetch;
          window.fetch = function (input, init) {
            try {
              var url = (typeof input === 'string') ? input : (input && input.url);
              var h = (init && init.headers) || (input && input.headers);
              grab(h, url);
            } catch (e) {}
            var p = of.apply(this, arguments);
            try {
              p.then(function (r) {
                if (r && /firestore/.test(r.url)) r.clone().text().then(scan).catch(function(){});
              });
            } catch (e) {}
            return p;
          };

          // Hook XHR (Firestore's WebChannel uses XHR — this is the reliable
          // capture point for the App Check header on Listen/Write channels).
          var XO = XMLHttpRequest.prototype.open,
              XS = XMLHttpRequest.prototype.setRequestHeader,
              XSN = XMLHttpRequest.prototype.send;
          XMLHttpRequest.prototype.open = function (m, u) { this.__u = u; return XO.apply(this, arguments); };
          XMLHttpRequest.prototype.setRequestHeader = function (k, v) {
            try {
              if (/^x-firebase-appcheck$/i.test(k) && v && !sent) {
                sent = true; post({ type: 'appcheck', token: v, idToken: '' });
              }
              if (/^authorization$/i.test(k) && /^Bearer /.test(v)) {
                post({ type: 'appcheck', token: '', idToken: v.slice(7) });
              }
            } catch (e) {}
            return XS.apply(this, arguments);
          };
          XMLHttpRequest.prototype.send = function () {
            var self = this;
            try {
              this.addEventListener('load', function () {
                try {
                  if (self.__u && /firestore/.test(self.__u)) scan(self.responseText);
                } catch (e) {}
              });
            } catch (e) {}
            return XSN.apply(this, arguments);
          };

          post({ type: 'log', msg: 'hooks installed on ' + location.pathname });
        })();
        """
    }

    /// JSON-encode a Swift string into a JS string literal (safe substitution).
    private func jsString(_ s: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [s])
        // ["value"] → drop the array brackets to get the bare quoted literal.
        if let data, var str = String(data: data, encoding: .utf8) {
            str.removeFirst(); str.removeLast()
            return str
        }
        return "\"\""
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }.first
    }

    /// Thin message-handler shim so `StampWebSync` needn't inherit NSObject's
    /// script-message conformance directly (keeps the retain graph obvious).
    private final class Bridge: NSObject, WKScriptMessageHandler {
        weak var owner: StampWebSync?
        init(owner: StampWebSync) { self.owner = owner }
        func userContentController(_ controller: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            Task { @MainActor in self.owner?.onMessage(body) }
        }
    }
}

extension StampWebSync: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        status = "web load failed: \(error.localizedDescription)"
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        status = "web load failed: \(error.localizedDescription)"
    }
}
