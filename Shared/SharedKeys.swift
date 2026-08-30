import Foundation

/// Keys shared between the iPhone app and the Watch app.
enum SharedKeys {
    // WatchConnectivity application-context payload keys.
    static let uid = "uid"
    static let email = "email"
    static let qr = "qr"          // PNG bytes of the loyalty QR (rendered on the phone)
    static let stamps = "stamps"  // current loyalty stamp count (0...9)

    // UserDefaults keys — the UID/QR are persisted on each device so the card
    // works offline / across launches.
    static let defaultsUID = "bug-coffee.uid"
    static let defaultsEmail = "bug-coffee.email"
    static let defaultsQR = "bug-coffee.qr"

    // App Group shared between the iPhone app, the widget extension and the
    // iMessage extension — the stamp count lives there so the home-screen
    // widget can read it, and the favorite products so the iMessage menu can
    // put them on top.
    static let appGroup = "group.com.zerogravityroom.bugwallet"
    static let defaultsStamps = "bug-coffee.stamps"
    static let defaultsFavorites = "bug-coffee.favorites"
    static let defaultsBlendJournal = "bug-coffee.blend-journal"
}
