import SwiftUI

/// The App Clip: the loyalty card on its own — sign in, show the QR and the
/// stamp count, add the card to Apple Wallet. Everything else (products, the
/// tasting diary, Health logging, the Watch link) stays in the full app.
@main
struct BugWalletClipApp: App {
    @StateObject private var session = Session()

    var body: some Scene {
        WindowGroup {
            Group {
                if let account = session.account {
                    ClipCardView(account: account)
                } else {
                    LoginView()
                }
            }
            .environmentObject(session)
            .preferredColorScheme(.light)
        }
    }
}

/// The clip's counterpart of the app's `Session` (BugWalletApp.swift), without
/// the Watch link. It carries the same name so `LoginView` compiles unchanged
/// into both targets.
@MainActor
final class Session: ObservableObject {
    @Published var account: Account? {
        didSet { persistAndSync() }
    }

    private let defaults: UserDefaults
    private let webSync: StampWebSync

    init(defaults: UserDefaults = .standard, webSync: StampWebSync? = nil) {
        self.defaults = defaults
        self.webSync = webSync ?? .shared
        // A clip's defaults outlive a single launch (until the system evicts
        // the clip), so a returning user lands straight on the card. Setting
        // `account` inside init does not trigger `didSet`, hence the manual
        // web-sync start.
        if let uid = defaults.string(forKey: SharedKeys.defaultsUID), !uid.isEmpty {
            let restored = Account(uid: uid,
                                   email: defaults.string(forKey: SharedKeys.defaultsEmail) ?? "",
                                   idToken: "",
                                   refreshToken: defaults.string(forKey: SharedKeys.defaultsRefresh) ?? "")
            account = restored
            self.webSync.start(account: restored)
        }
    }

    func signOut() {
        account = nil
        webSync.stop()
        defaults.removeObject(forKey: SharedKeys.defaultsUID)
        defaults.removeObject(forKey: SharedKeys.defaultsEmail)
        defaults.removeObject(forKey: SharedKeys.defaultsRefresh)
    }

    private func persistAndSync() {
        guard let account else { return }
        defaults.set(account.uid, forKey: SharedKeys.defaultsUID)
        defaults.set(account.email, forKey: SharedKeys.defaultsEmail)
        defaults.set(account.refreshToken, forKey: SharedKeys.defaultsRefresh)
        // Kick off the App Check WebView to read the live stamp count.
        webSync.start(account: account)
    }
}
