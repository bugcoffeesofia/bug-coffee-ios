import Foundation
import Messages

/// View state for the iMessage app. The Messages controller feeds it the
/// active conversation; the SwiftUI views mutate the local selection and call
/// back through the closures.
@MainActor
final class OrderStore: ObservableObject {
    /// Everyone else's drinks, decoded from the tapped message.
    @Published var othersLines: [OrderLine] = []
    /// The local user's drinks — pre-filled from the message if they already
    /// ordered, so tapping the bubble again edits instead of duplicating.
    @Published var myLines: [OrderLine] = []
    @Published var isExpanded = false
    /// Favorite product IDs, shared with the main app through the App Group.
    /// Favorites sort to the top of their menu section.
    @Published var favorites = FavoritesStore.ids

    private(set) var localParticipant = UUID()
    /// Stable "Friend N" labels; extensions never see real contact names.
    private var labels: [UUID: String] = [:]

    var onRequestExpand: (() -> Void)?
    var onSubmit: (() -> Void)?

    var canSubmit: Bool { !myLines.isEmpty }
    var isJoiningExistingOrder: Bool { !othersLines.isEmpty }

    func load(from conversation: MSConversation, message: MSMessage? = nil) {
        localParticipant = conversation.localParticipantIdentifier
        let order = GroupOrder(message: message ?? conversation.selectedMessage) ?? GroupOrder()
        othersLines = order.lines.filter { $0.participant != localParticipant }
        myLines = order.lines.filter { $0.participant == localParticipant }
        labels = [:]
        for line in othersLines where labels[line.participant] == nil {
            labels[line.participant] = "Friend \(labels.count + 1)"
        }
        favorites = FavoritesStore.ids
    }

    /// The drinks section of the menu, favorites on top.
    var menuDrinks: [MenuItem] { CoffeeMenu.favoritesFirst(CoffeeMenu.drinks, favorites: favorites) }
    /// The beans section of the menu, favorites on top.
    var menuBeans: [MenuItem] { CoffeeMenu.favoritesFirst(CoffeeMenu.beans, favorites: favorites) }

    func toggleFavorite(_ item: MenuItem) {
        favorites = FavoritesStore.toggle(item.id)
    }

    func label(for participant: UUID) -> String {
        participant == localParticipant ? "You" : (labels[participant] ?? "Friend")
    }

    /// Adds a plain (regular, non-decaf, house-blend) drink; modifiers are
    /// tweaked on the line afterwards. Identical plain lines just bump the
    /// quantity.
    func add(_ item: MenuItem) {
        if let i = myLines.firstIndex(where: {
            $0.drinkID == item.id && !$0.decaf && $0.milk.isEmpty && $0.blend.isEmpty
        }) {
            myLines[i].qty += 1
        } else {
            myLines.append(OrderLine(id: UUID(), participant: localParticipant,
                                     drinkID: item.id, decaf: false, milk: "",
                                     blend: "", qty: 1))
        }
    }

    /// The local user's drinks total, in euro cents.
    var myTotalCents: Int { myLines.reduce(0) { $0 + $1.totalCents } }

    /// The full order to put back into the message: everyone else's drinks
    /// untouched, the local user's replaced by the current selection.
    func combinedOrder() -> GroupOrder {
        GroupOrder(lines: othersLines + myLines)
    }
}
