import Foundation
import Messages
import Testing
import UIKit

private let alice = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
private let bob = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!
private let me = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!

private func line(_ participant: UUID, _ drink: String, decaf: Bool = false, milk: String = "",
                  blend: String = "", qty: Int = 1) -> OrderLine {
    OrderLine(id: UUID(), participant: participant, drinkID: drink, decaf: decaf, milk: milk, blend: blend, qty: qty)
}

private func message(_ url: String) -> MSMessage {
    let message = MSMessage()
    message.url = URL(string: url)
    return message
}

/// Compares lines without their per-decode ids.
private func same(_ a: [OrderLine], _ b: [OrderLine]) -> Bool {
    a.map { [$0.participant.uuidString, $0.drinkID, "\($0.decaf)", $0.milk, $0.blend, "\($0.qty)"] }
        == b.map { [$0.participant.uuidString, $0.drinkID, "\($0.decaf)", $0.milk, $0.blend, "\($0.qty)"] }
}

@Suite struct OrderLineTests {
    @Test func plainDrink() {
        let latte = line(alice, "lat", qty: 2)
        #expect(latte.drink?.name == "Latte")
        #expect(latte.title == "Latte")
        #expect(latte.unitCents == 330)
        #expect(latte.totalCents == 660)
    }

    @Test func modifiersShowInTitleAndPrice() {
        let cap = line(alice, "cap", decaf: true, milk: "oat", blend: "kal")
        #expect(cap.title == "Cappuccino · decaf · oat milk · Kalinka Blend")
        #expect(cap.unitCents == 310 + CoffeeMenu.decafSurchargeCents + CoffeeMenu.milkSurchargeCents)
    }

    @Test func unknownIDsDegradeGracefully() {
        let ghost = line(alice, "gone", milk: "cow", blend: "old", qty: 3)
        #expect(ghost.drink == nil)
        // Unknown milk/blend ids are left out of the title but milk still costs.
        #expect(ghost.title == "gone")
        #expect(ghost.unitCents == CoffeeMenu.milkSurchargeCents)
        #expect(ghost.totalCents == 3 * CoffeeMenu.milkSurchargeCents)
    }
}

@Suite struct GroupOrderTests {
    @Test func urlEncodesEveryLine() throws {
        let order = GroupOrder(lines: [line(alice, "cap", decaf: true, milk: "oat", blend: "kal", qty: 2), line(bob, "esp")])
        let components = try #require(URLComponents(url: order.url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.host == "bugcoffee.example")
        #expect(components.path == "/group-order")
        #expect(components.queryItems?.first == URLQueryItem(name: "v", value: "3"))
        #expect(components.queryItems?.dropFirst().map(\.value) == [
            "\(alice.uuidString)~cap~1~oat~2~kal",
            "\(bob.uuidString)~esp~0~-~1~-",
        ])
    }

    @Test func urlRoundTripsThroughAMessage() {
        let lines = [line(alice, "cap", decaf: true, milk: "oat", blend: "kal", qty: 2), line(bob, "esp"), line(alice, "tea")]
        let message = MSMessage()
        message.url = GroupOrder(lines: lines).url
        let decoded = GroupOrder(message: message)
        #expect(decoded != nil)
        #expect(same(decoded?.lines ?? [], lines))
    }

    @Test func version2BubblesDecodeWithTheHouseBlend() {
        let decoded = GroupOrder(message: message("https://bugcoffee.example/group-order?v=2&o=\(alice.uuidString)~lat~0~alm~1"))
        #expect(same(decoded?.lines ?? [], [line(alice, "lat", milk: "alm")]))
    }

    @Test func malformedLinesAreSkipped() {
        let url = "https://bugcoffee.example/group-order?v=3"
            + "&o=not-a-uuid~esp~0~-~1~-"
            + "&o=\(alice.uuidString)~esp~0~-~0~-"       // zero quantity
            + "&o=\(alice.uuidString)~esp~0~-~two~-"     // non-numeric quantity
            + "&o=\(alice.uuidString)~esp~0"             // too few fields
            + "&o=\(alice.uuidString)~esp~0~-~1~-~extra" // too many fields
            + "&o"                                        // no value
            + "&x=\(bob.uuidString)~esp~0~-~1~-"         // not an order line
            + "&o=\(bob.uuidString)~dsp~1~-~2~sjp"
        let decoded = GroupOrder(message: message(url))
        #expect(same(decoded?.lines ?? [], [line(bob, "dsp", decaf: true, blend: "sjp", qty: 2)]))
    }

    @Test func noMessageOrURLIsNoOrder() {
        #expect(GroupOrder(message: nil) == nil)
        #expect(GroupOrder(message: MSMessage()) == nil)
        #expect(GroupOrder(message: message("https://bugcoffee.example/group-order"))?.lines.isEmpty == true)
    }

    @Test func summaries() {
        let order = GroupOrder(lines: [line(alice, "cap", milk: "oat", qty: 2), line(bob, "esp"), line(alice, "cap", milk: "oat")])
        #expect(order.totalDrinks == 4)
        #expect(order.totalCents == 3 * 370 + 190)
        #expect(order.participants == [alice, bob])
        #expect(order.oneLineSummary == "4 drinks · 2 people · 13.00 €")
        #expect(order.aggregated.map(\.title) == ["Cappuccino · oat milk", "Espresso"])
        #expect(order.aggregated.map(\.qty) == [3, 1])
    }

    @Test func singularSummary() {
        #expect(GroupOrder(lines: [line(alice, "esp")]).oneLineSummary == "1 drink · 1 person · 1.90 €")
        #expect(GroupOrder().oneLineSummary == "0 drinks · 0 people · 0.00 €")
    }
}

@Suite struct OrderCardRendererTests {
    @Test(arguments: [0, 3, 8])
    func rendersTheBubbleImage(distinctDrinks: Int) {
        let lines = CoffeeMenu.drinks.prefix(distinctDrinks).map { line(alice, $0.id) }
        let image = OrderCardRenderer.render(GroupOrder(lines: Array(lines)))
        #expect(image.size == CGSize(width: 300, height: 175))
        #expect(image.scale == 3)
    }
}

// MARK: - OrderStore

/// Messages won't hand out a real conversation outside the Messages app, so
/// this one answers the two properties OrderStore reads.
private final class FakeConversation: MSConversation {
    private let local: UUID
    private let selected: MSMessage?

    init(local: UUID, selected: MSMessage? = nil) {
        self.local = local
        self.selected = selected
        super.init()
    }

    override var localParticipantIdentifier: UUID { local }
    override var selectedMessage: MSMessage? { selected }
}

@MainActor
@Suite(.serialized)
struct OrderStoreTests {
    init() {
        let defaults = UserDefaults(suiteName: "BugWalletMessagesTests")!
        defaults.removePersistentDomain(forName: "BugWalletMessagesTests")
        SharedKeys.groupDefaults = defaults
    }

    private func orderMessage(_ lines: [OrderLine]) -> MSMessage {
        let message = MSMessage()
        message.url = GroupOrder(lines: lines).url
        return message
    }

    @Test func freshStore() {
        let store = OrderStore()
        #expect(!store.canSubmit)
        #expect(!store.isJoiningExistingOrder)
        #expect(store.myTotalCents == 0)
        #expect(store.menuDrinks == CoffeeMenu.drinks)
        #expect(store.menuBeans == CoffeeMenu.beans)
        #expect(store.label(for: store.localParticipant) == "You")
        #expect(store.label(for: alice) == "Friend")
    }

    @Test func loadSplitsMyLinesFromEveryoneElses() {
        let store = OrderStore()
        let selected = orderMessage([line(alice, "esp"), line(me, "lat", qty: 2), line(bob, "cap"), line(alice, "tea")])
        store.load(from: FakeConversation(local: me, selected: selected))
        #expect(store.localParticipant == me)
        #expect(same(store.myLines, [line(me, "lat", qty: 2)]))
        #expect(store.othersLines.count == 3)
        #expect(store.isJoiningExistingOrder)
        #expect(store.canSubmit)
        #expect(store.label(for: me) == "You")
        #expect(store.label(for: alice) == "Friend 1")
        #expect(store.label(for: bob) == "Friend 2")
        #expect(store.myTotalCents == 660)
    }

    @Test func anExplicitMessageWinsOverTheSelectedOne() {
        let store = OrderStore()
        let conversation = FakeConversation(local: me, selected: orderMessage([line(alice, "esp")]))
        store.load(from: conversation, message: orderMessage([line(bob, "cap")]))
        #expect(same(store.othersLines, [line(bob, "cap")]))
    }

    @Test func loadingANewConversationResetsLabels() {
        let store = OrderStore()
        store.load(from: FakeConversation(local: me, selected: orderMessage([line(alice, "esp")])))
        store.load(from: FakeConversation(local: me))
        #expect(store.othersLines.isEmpty)
        #expect(store.myLines.isEmpty)
        #expect(store.label(for: alice) == "Friend")
    }

    @Test func addingBumpsIdenticalPlainLines() throws {
        let store = OrderStore()
        store.load(from: FakeConversation(local: me))
        let espresso = try #require(CoffeeMenu.byID["esp"])
        store.add(espresso)
        store.add(espresso)
        #expect(store.myLines.count == 1)
        #expect(store.myLines.first?.qty == 2)

        // A line with modifiers is a different drink; the next plain one starts fresh.
        store.myLines[0].milk = "oat"
        store.add(espresso)
        #expect(store.myLines.map(\.qty) == [2, 1])
        #expect(store.myLines.allSatisfy { $0.participant == me })
    }

    @Test func combinedOrderKeepsOthersAndReplacesMine() throws {
        let store = OrderStore()
        store.load(from: FakeConversation(local: me, selected: orderMessage([line(alice, "esp"), line(me, "lat")])))
        store.myLines.removeAll()
        store.add(try #require(CoffeeMenu.byID["cap"]))
        #expect(same(store.combinedOrder().lines, [line(alice, "esp"), line(me, "cap")]))
    }

    @Test func favoritesComeFromTheAppGroupAndSortFirst() throws {
        _ = FavoritesStore.toggle("tea")
        let store = OrderStore()
        store.load(from: FakeConversation(local: me))
        #expect(store.favorites == ["tea"])
        #expect(store.menuDrinks.first?.id == "tea")

        store.toggleFavorite(try #require(CoffeeMenu.byID["kul"]))
        #expect(store.favorites == ["tea", "kul"])
        #expect(store.menuBeans.first?.id == "kul")
        store.toggleFavorite(try #require(CoffeeMenu.byID["tea"]))
        #expect(FavoritesStore.ids == ["kul"])
    }

    @Test func callbacksAreJustStored() {
        let store = OrderStore()
        var expanded = false, submitted = false
        store.onRequestExpand = { expanded = true }
        store.onSubmit = { submitted = true }
        store.onRequestExpand?()
        store.onSubmit?()
        #expect(expanded && submitted)
    }
}
