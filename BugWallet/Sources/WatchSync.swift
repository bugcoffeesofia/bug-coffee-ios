import Foundation
import WatchConnectivity

/// Pushes the logged-in UID to the Watch app via WatchConnectivity.
///
/// `updateApplicationContext` delivers the latest value even if the watch is
/// asleep or the Watch app is closed — it's queued and handed over on the next
/// activation, which is exactly what we want for a rarely-changing UID.
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()
    private override init() { super.init() }

    private var activated = false
    // The latest full application context. `updateApplicationContext` replaces
    // the whole dictionary on each call, so we keep it here and merge partial
    // updates (e.g. a new stamp count) into it before resending.
    private var context: [String: Any] = [:]

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func sync(uid: String, email: String) {
        guard WCSession.isSupported() else { return }
        context[SharedKeys.uid] = uid
        context[SharedKeys.email] = email
        // The watch can't render QR (no CoreImage), so ship it the rendered PNG.
        if let png = QRGenerator.pngData(from: uid) {
            context[SharedKeys.qr] = png
        }
        // Carry the current stamp count so the watch's stamp card is up to date.
        context[SharedKeys.stamps] = StampStore.count
        flush()
    }

    /// Pushes an updated stamp count to the watch, keeping the rest of the
    /// context (uid/qr) intact. Called when the user taps +/- on the card.
    func syncStamps(_ count: Int) {
        guard WCSession.isSupported() else { return }
        context[SharedKeys.stamps] = count
        flush()
    }

    private func flush() {
        guard activated, context[SharedKeys.uid] != nil else { return }
        do {
            try WCSession.default.updateApplicationContext(context)
        } catch {
            // Leave `context` as-is; it retries on the next activation/flush.
        }
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        activated = (activationState == .activated)
        if activated { flush() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate for a newly paired watch.
        WCSession.default.activate()
    }
}
