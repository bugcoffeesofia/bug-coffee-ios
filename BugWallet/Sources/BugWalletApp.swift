import SwiftUI

@main
struct BugWalletApp: App {
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

    init() {
        // Start the watch link and re-push any saved UID so the Watch app gets it
        // even when the phone isn't freshly logged in this launch.
        WatchSync.shared.start()
        let defaults = UserDefaults.standard
        if let uid = defaults.string(
            forKey: SharedKeys.defaultsUID
        ), !uid.isEmpty {
            let email = defaults.string(forKey: SharedKeys.defaultsEmail) ?? ""
            
            // Restore the previous session so a returning user goes straight to
            // their card. The card only needs the UID/email (the QR, header and
            // Wallet pass are built from those); the auth tokens aren't used
            // anywhere, so no re-login is required. Setting `account` inside
            // init does not trigger `didSet`, hence the manual watch sync below.
            account = Account(uid: uid, email: email, idToken: "", refreshToken: "")
            WatchSync.shared.sync(uid: uid, email: email)
        }
    }

    var isSignedIn: Bool { account != nil }

    func signOut() {
        account = nil
        // Forget the persisted identity so the next launch shows the login screen.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: SharedKeys.defaultsUID)
        defaults.removeObject(forKey: SharedKeys.defaultsEmail)
    }

    private func persistAndSync() {
        guard let account else { return }
        let defaults = UserDefaults.standard
        defaults.set(account.uid, forKey: SharedKeys.defaultsUID)
        defaults.set(account.email, forKey: SharedKeys.defaultsEmail)
        WatchSync.shared.sync(uid: account.uid, email: account.email)
    }
}

struct RootView: View {
    @EnvironmentObject private var session: Session

    private enum Tab { case card, products }

    @State private var tab = Tab.card
    /// The bean pages stacked on the Products tab, by bean id. Held here rather
    /// than inside ProductsView so a `bugcoffee://bean/<id>` link can push one
    /// without a tap — including while the login screen is still up, since the
    /// stack reads this path the moment it appears.
    @State private var beanPath: [String] = []

    var body: some View {
        Group {
            if let account = session.account {
                TabView(selection: $tab) {
                    CardView(account: account)
                        .tabItem { Label("Card", systemImage: "qrcode") }
                        .tag(Tab.card)
                    ProductsView(beanPath: $beanPath)
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
            beanPath = [bean.id]
        }
    }
}
