import Foundation
import WatchConnectivity

/// Receives the UID from the iPhone and persists it so the Watch app can show
/// the loyalty QR on its own, even without the phone nearby.
final class WatchModel: NSObject, ObservableObject, WCSessionDelegate {
    @Published var uid: String?
    @Published var email: String?
    @Published var qr: Data?
    @Published var stamps: Int = 0

    override init() {
        super.init()
        let defaults = UserDefaults.standard
        uid = defaults.string(forKey: SharedKeys.defaultsUID)
        email = defaults.string(forKey: SharedKeys.defaultsEmail)
        qr = defaults.data(forKey: SharedKeys.defaultsQR)
        stamps = defaults.integer(forKey: SharedKeys.defaultsStamps)

        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    private func apply(_ context: [String: Any]) {
        guard let uid = context[SharedKeys.uid] as? String, !uid.isEmpty else { return }
        let email = context[SharedKeys.email] as? String
        let qr = context[SharedKeys.qr] as? Data
        let stamps = context[SharedKeys.stamps] as? Int
        DispatchQueue.main.async {
            self.uid = uid
            self.email = email
            self.qr = qr
            let defaults = UserDefaults.standard
            defaults.set(uid, forKey: SharedKeys.defaultsUID)
            defaults.set(email, forKey: SharedKeys.defaultsEmail)
            defaults.set(qr, forKey: SharedKeys.defaultsQR)
            if let stamps {
                self.stamps = stamps
                defaults.set(stamps, forKey: SharedKeys.defaultsStamps)
            }
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        // Pick up a context the phone may have sent while this app was closed.
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    // Note: sessionDidBecomeInactive/sessionDidDeactivate exist only on iOS;
    // they're unavailable on watchOS, so this delegate must not implement them.
}
