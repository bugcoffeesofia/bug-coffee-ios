import UIKit
import SwiftUI
import Messages

/// The iMessage app: a shared Bug Coffee order for a group chat.
///
/// The whole order lives in the message itself (MSSession + URL query items),
/// so there is no server: each participant taps the bubble, adds their drinks,
/// and sends the updated order back. Reusing the session keeps every update in
/// one bubble instead of spamming the chat.
final class MessagesViewController: MSMessagesAppViewController {

    private let store = OrderStore()

    override func viewDidLoad() {
        super.viewDidLoad()

        store.onRequestExpand = { [weak self] in
            self?.requestPresentationStyle(.expanded)
        }
        store.onSubmit = { [weak self] in
            self?.insertOrder()
        }

        let host = UIHostingController(rootView: OrderRootView(store: store))
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        host.didMove(toParent: self)
    }

    // MARK: - Conversation lifecycle

    override func willBecomeActive(with conversation: MSConversation) {
        super.willBecomeActive(with: conversation)
        store.isExpanded = presentationStyle == .expanded
        store.load(from: conversation)
    }

    /// The user tapped a group-order bubble while the extension was open.
    override func didSelect(_ message: MSMessage, conversation: MSConversation) {
        store.load(from: conversation, message: message)
    }

    /// Someone else's update arrived while the extension is on screen.
    override func didReceive(_ message: MSMessage, conversation: MSConversation) {
        store.load(from: conversation, message: message)
    }

    override func didTransition(to presentationStyle: MSMessagesAppPresentationStyle) {
        store.isExpanded = presentationStyle == .expanded
    }

    // MARK: - Sending

    private func insertOrder() {
        guard let conversation = activeConversation else { return }
        let order = store.combinedOrder()

        let session = conversation.selectedMessage?.session ?? MSSession()
        let message = MSMessage(session: session)
        message.url = order.url

        let layout = MSMessageTemplateLayout()
        layout.image = OrderCardRenderer.render(order)
        layout.caption = "Bug Coffee group order"
        layout.subcaption = order.oneLineSummary
        message.layout = layout
        message.summaryText = "Bug Coffee group order — \(order.oneLineSummary)"

        // Puts the bubble in the input field; the user hits send themselves.
        conversation.insert(message) { error in
            if let error {
                NSLog("Failed to insert group order message: \(error)")
            }
        }
        dismiss()
    }
}
