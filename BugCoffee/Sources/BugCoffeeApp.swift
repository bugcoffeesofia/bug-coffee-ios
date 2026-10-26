import SwiftUI

@main
struct BugCoffeeApp: App {
    @StateObject private var session = Session()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .preferredColorScheme(.light)
        }
    }
}

/// Holds the signed-in user for the lifetime of the app.
/// The whole app is "login → show loyalty card", so a single object is enough.
@MainActor
final class Session: ObservableObject {
    @Published var account: Account? {
        didSet { persistAndSync() }
    }

    private let defaults: UserDefaults
    private let webSync: StampWebSync

    /// `defaults` and `webSync` are seams for unit tests; the app uses the
    /// standard defaults and the shared App Check WebView.
    init(defaults: UserDefaults = .standard, webSync: StampWebSync? = nil) {
        self.defaults = defaults
        self.webSync = webSync ?? .shared
        // Start the watch link and re-push any saved UID so the Watch app gets it
        // even when the phone isn't freshly logged in this launch.
        WatchSync.shared.start()
        if let uid = defaults.string(
            forKey: SharedKeys.defaultsUID
        ), !uid.isEmpty {
            let email = defaults.string(forKey: SharedKeys.defaultsEmail) ?? ""
            
            // Restore the previous session so a returning user goes straight to
            // their card. The card needs the UID/email (the QR, header and
            // Wallet pass are built from those); the refresh token, if we saved
            // one, lets StampWebSync seed a logged-in web session to read the
            // live stamp count. Setting `account` inside init does not trigger
            // `didSet`, hence the manual watch sync + web-sync start below.
            let refresh = defaults.string(forKey: SharedKeys.defaultsRefresh) ?? ""
            let restored = Account(uid: uid, email: email, idToken: "", refreshToken: refresh)
            account = restored
            WatchSync.shared.sync(uid: uid, email: email)
            self.webSync.start(account: restored)
        }
    }

    var isSignedIn: Bool { account != nil }

    func signOut() {
        account = nil
        webSync.stop()
        // Forget the persisted identity so the next launch shows the login screen.
        defaults.removeObject(forKey: SharedKeys.defaultsUID)
        defaults.removeObject(forKey: SharedKeys.defaultsEmail)
        defaults.removeObject(forKey: SharedKeys.defaultsRefresh)
    }

    private func persistAndSync() {
        guard let account else { return }
        defaults.set(account.uid, forKey: SharedKeys.defaultsUID)
        defaults.set(account.email, forKey: SharedKeys.defaultsEmail)
        defaults.set(account.refreshToken, forKey: SharedKeys.defaultsRefresh)
        WatchSync.shared.sync(uid: account.uid, email: account.email)
        // Kick off the App Check WebView to read the live stamp count.
        webSync.start(account: account)
    }
}

struct RootView: View {
    @EnvironmentObject private var session: Session

    private enum Tab { case card, products }

    @State private var tab = Tab.card
    /// The bean page open on the Products tab, by bean id. Held here rather
    /// than inside ProductsView so a `bugcoffee://bean/<id>` link can open one
    /// without a tap — including while the login screen is still up, since the
    /// split view reads this selection the moment it appears.
    @State private var selectedBean: String?

    var body: some View {
        Group {
            if let account = session.account {
                // No tab sidebar on iPhone Duo's inner display
                // (`.defaultTabBarPlacement(.sidebar)`, iOS 27): two tabs don't
                // need one, and Products already has a sidebar of its own.
                TabView(selection: $tab) {
                    CardView(account: account)
                        .tabItem { Label("Card", systemImage: "qrcode") }
                        .tag(Tab.card)
                    ProductsView(selectedBean: $selectedBean)
                        .tabItem { Label("Products", systemImage: "cup.and.saucer.fill") }
                        .tag(Tab.products)
                }
            } else {
                LoginView()
            }
        }
        .onOpenURL { url in
            // Links to retired beans (or any other URL on our scheme) are
            // ignored — better to land on the card than on an empty page.
            guard let bean = BeanLink.bean(from: url) else { return }
            tab = .products
            selectedBean = bean.id
        }
    }
}
