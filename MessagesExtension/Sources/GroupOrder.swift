import Foundation
import Messages

// The menu itself (MenuItem / CoffeeMenu / Price) lives in Shared/CoffeeMenu.swift,
// shared with the main app's Products tab.

/// One participant's drink in the group order.
struct OrderLine: Identifiable, Hashable {
    let id: UUID
    var participant: UUID
    var drinkID: String
    var decaf: Bool
    /// MilkOption id, or "" for regular milk.
    var milk: String
    /// Bean id the coffee is brewed from, or "" for the house blend.
    var blend: String
    var qty: Int

    var drink: MenuItem? { CoffeeMenu.byID[drinkID] }

    /// "Cappuccino · decaf · oat milk · Kalinka Blend"
    var title: String {
        var parts = [drink?.name ?? drinkID]
        if decaf { parts.append("decaf") }
        if let m = CoffeeMenu.milkByID[milk] { parts.append("\(m.name.lowercased()) milk") }
        if let b = CoffeeMenu.byID[blend] { parts.append(b.name) }
        return parts.joined(separator: " · ")
    }

    /// Price of one drink, including modifiers, in euro cents.
    var unitCents: Int {
        var cents = drink?.cents ?? 0
        if decaf { cents += CoffeeMenu.decafSurchargeCents }
        if !milk.isEmpty { cents += CoffeeMenu.milkSurchargeCents }
        return cents
    }

    var totalCents: Int { unitCents * qty }
}

/// The whole group order. It lives entirely inside the MSMessage URL, so the
/// message bubble *is* the shared state — no server involved. Participants are
/// the opaque per-device UUIDs Messages gives us; real names are never visible
/// to extensions.
struct GroupOrder {
    var lines: [OrderLine]

    init(lines: [OrderLine] = []) { self.lines = lines }

    // MARK: - URL round-trip
    // ?v=3&o=<participantUUID>~<drinkID>~<decaf 0/1>~<milkID or ->~<qty>~<blendID or ->&o=…
    // The blend is the appended sixth field; v2 bubbles (five fields) still
    // decode with the house blend.

    var url: URL {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = "bugcoffee.example"
        comps.path = "/group-order"
        comps.queryItems = [URLQueryItem(name: "v", value: "3")] + lines.map {
            let milk = $0.milk.isEmpty ? "-" : $0.milk
            let blend = $0.blend.isEmpty ? "-" : $0.blend
            return URLQueryItem(
                name: "o",
                value: "\($0.participant.uuidString)~\($0.drinkID)~\($0.decaf ? 1 : 0)~\(milk)~\($0.qty)~\(blend)")
        }
        return comps.url!
    }

    init?(message: MSMessage?) {
        guard let url = message?.url,
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        var lines: [OrderLine] = []
        for item in comps.queryItems ?? [] where item.name == "o" {
            let parts = (item.value ?? "").components(separatedBy: "~")
            guard parts.count == 5 || parts.count == 6,
                  let participant = UUID(uuidString: parts[0]),
                  let qty = Int(parts[4]), qty > 0
            else { continue }
            let blend = parts.count == 6 ? parts[5] : "-"
            lines.append(OrderLine(id: UUID(), participant: participant,
                                   drinkID: parts[1],
                                   decaf: parts[2] == "1",
                                   milk: parts[3] == "-" ? "" : parts[3],
                                   blend: blend == "-" ? "" : blend,
                                   qty: qty))
        }
        self.lines = lines
    }

    // MARK: - Summaries

    var totalDrinks: Int { lines.reduce(0) { $0 + $1.qty } }
    var totalCents: Int { lines.reduce(0) { $0 + $1.totalCents } }

    /// Participants in order of first appearance.
    var participants: [UUID] {
        var seen: Set<UUID> = []
        return lines.compactMap { seen.insert($0.participant).inserted ? $0.participant : nil }
    }

    var oneLineSummary: String {
        let d = totalDrinks, p = participants.count
        return "\(d) \(d == 1 ? "drink" : "drinks") · \(p) \(p == 1 ? "person" : "people") · \(Price.euro(totalCents))"
    }

    /// Lines merged across participants ("2× Cappuccino · oat milk") for the
    /// bubble image.
    var aggregated: [(title: String, qty: Int)] {
        var totals: [String: Int] = [:]
        var order: [String] = []
        for line in lines {
            if totals[line.title] == nil { order.append(line.title) }
            totals[line.title, default: 0] += line.qty
        }
        return order.map { ($0, totals[$0]!) }
    }
}
