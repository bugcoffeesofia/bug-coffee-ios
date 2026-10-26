import SwiftUI
import PassKit

// The PassKit UI pieces behind "Add to Apple Wallet", shared by the app's card
// (CardView) and the App Clip's (ClipCardView).

/// Dismisses the PKAddPassesViewController and reports when it's done.
final class AddPassesDelegate: NSObject, PKAddPassesViewControllerDelegate {
    private let onFinish: () -> Void
    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

    func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
        controller.dismiss(animated: true)
        onFinish()
    }
}

/// The official Apple "Add to Apple Wallet" button (PKAddPassButton).
struct AddToWalletButton: UIViewRepresentable {
    let action: () -> Void

    func makeUIView(context: Context) -> PKAddPassButton {
        let button = PKAddPassButton(addPassButtonStyle: .black)
        button.addTarget(context.coordinator,
                         action: #selector(Coordinator.tapped),
                         for: .touchUpInside)
        return button
    }

    func updateUIView(_ uiView: PKAddPassButton, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func tapped() { action() }
    }
}

/// Finds the frontmost view controller to present PassKit UI from.
enum WalletPresenter {
    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

