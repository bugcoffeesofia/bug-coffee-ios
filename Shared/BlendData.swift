import Foundation

/// Everything the "find your blend" flow knows about a bean: the shop's
/// published tasting notes (bugcoffee.com product pages) plus the axes the
/// quiz matches on. Pure data (no SwiftUI), so the iPhone app, the iMessage
/// order and the Watch wizard all share it.
struct BlendInfo {
    let tastingNotes: String
    let blurb: String
    /// Fruit-forward (naturals, bright singles) vs chocolate/nuts/caramel.
    let fruity: Bool
    /// Dense/sweet enough to shine in milk drinks.
    let lovesMilk: Bool
    let decaf: Bool

    static let byID: [String: BlendInfo] = [
        "bbe": .init(tastingNotes: "forest fruit · caramel · nuts",
                     blurb: "Sugarcane-process Ethiopian decaf that keeps the bean's character.",
                     fruity: false, lovesMilk: true, decaf: true),
        "bmb": .init(tastingNotes: "peach · chocolate · berry",
                     blurb: "Natural Sidamo heirloom — stone fruit and berries.",
                     fruity: true, lovesMilk: false, decaf: false),
        "sjp": .init(tastingNotes: "apricot · caramel · black tea",
                     blurb: "Smooth washed Peruvian, sweet and clean.",
                     fruity: false, lovesMilk: true, decaf: false),
        "mkw": .init(tastingNotes: "kiwi · blackberry · toffee",
                     blurb: "Natural from the Rwenzori mountains, wild and bright.",
                     fruity: true, lovesMilk: false, decaf: false),
        "sir": .init(tastingNotes: "nectarine · melon · blood orange",
                     blurb: "Balanced natural Colombian — neither too acidic nor too bitter.",
                     fruity: true, lovesMilk: true, decaf: false),
        "kal": .init(tastingNotes: "chocolate · honey · apple",
                     blurb: "The approachable intro blend, balanced for espresso and filter.",
                     fruity: false, lovesMilk: true, decaf: false),
        "ban": .init(tastingNotes: "dark chocolate · nuts",
                     blurb: "Darker espresso blend, full-bodied and forgiving.",
                     fruity: false, lovesMilk: true, decaf: false),
        "kul": .init(tastingNotes: "dense body · natural sweetness",
                     blurb: "The house blend — Brazilian base, Central American aromatics.",
                     fruity: false, lovesMilk: true, decaf: false),
    ]
}

/// How the cup was made. The same bean tastes like a different coffee as a
/// cortado and as a moka pot, so every diary entry records its own method.
enum BrewMethod: String, Codable, CaseIterable, Identifiable {
    // Pulled on an espresso machine — the shop's board, and home machines.
    case espresso, doubleEspresso, americano, macchiato, cortado
    case flatWhite, cappuccino, latte, espressoTonic
    // Everything else: pour-over, immersion, stovetop.
    case v60, chemex, aeropress, frenchPress, mokaPot, cuban, turkish
    case coldBrew, drip, other

    var id: String { rawValue }

    /// Espresso-machine drinks come first in the picker, brewed ones after.
    var isEspressoBased: Bool {
        switch self {
        case .espresso, .doubleEspresso, .americano, .macchiato, .cortado,
             .flatWhite, .cappuccino, .latte, .espressoTonic: return true
        default: return false
        }
    }

    var name: String {
        switch self {
        case .espresso:       return "Espresso"
        case .doubleEspresso: return "Double espresso"
        case .americano:      return "Americano"
        case .macchiato:      return "Macchiato"
        case .cortado:        return "Cortado"
        case .flatWhite:      return "Flat white"
        case .cappuccino:     return "Cappuccino"
        case .latte:          return "Latte"
        case .espressoTonic:  return "Espresso tonic"
        case .v60:            return "V60 / pour-over"
        case .chemex:         return "Chemex"
        case .aeropress:      return "AeroPress"
        case .frenchPress:    return "French press"
        case .mokaPot:        return "Moka pot"
        case .cuban:          return "Cuban (cafecito)"
        case .turkish:        return "Turkish"
        case .coldBrew:       return "Cold brew"
        case .drip:           return "Filter / drip"
        case .other:          return "Other"
        }
    }

    var emoji: String {
        switch self {
        case .latte, .macchiato, .cortado, .flatWhite, .cappuccino: return "🥛"
        case .espressoTonic, .coldBrew: return "🍹"
        case .v60, .chemex, .drip: return "🫖"
        case .frenchPress, .aeropress: return "⏳"
        case .mokaPot, .cuban, .turkish: return "🔥"
        default: return "☕️"
        }
    }

    /// Grind hints only make sense when you ground the beans yourself, which
    /// in practice means anything you didn't order over a counter.
    static let espressoBar = allCases.filter(\.isEspressoBased)
    static let brewed = allCases.filter { !$0.isEspressoBased }
}

/// Where the cup happened — a shop pull and a home pull of the same bean are
/// worth telling apart when you look back.
enum BrewPlace: String, Codable, CaseIterable, Identifiable {
    case bugCoffee, otherCafe, home, work, other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .bugCoffee: return "Bug Coffee"
        case .otherCafe: return "Another café"
        case .home:      return "Home"
        case .work:      return "Work"
        case .other:     return "Elsewhere"
        }
    }

    var emoji: String {
        switch self {
        case .bugCoffee: return "🐞"
        case .otherCafe: return "🏠"
        case .home:      return "🏡"
        case .work:      return "💼"
        case .other:     return "📍"
        }
    }

    /// You control the grinder everywhere except behind someone else's bar.
    var grindsOwnBeans: Bool { self == .home || self == .work }
}

/// One cup, one moment: the diary entry. Several of these stack up per bean.
struct TastingEntry: Codable, Equatable, Identifiable {
    var id = UUID()
    var date = Date()
    /// 0 = unrated, otherwise 1...5.
    var rating = 0
    var method = BrewMethod.espresso
    var place = BrewPlace.bugCoffee
    /// Free text on purpose — "18 clicks", "medium-fine", "Niche 15" all mean
    /// something to their owner and nothing to anyone else's grinder.
    var grind = ""
    var note = ""

    /// True once the entry carries anything worth keeping.
    var isEmpty: Bool { rating == 0 && grind.isEmpty && note.isEmpty }

    /// Sets the rating to `star`; tapping the current rating clears it.
    mutating func tapStar(_ star: Int) {
        rating = rating == star ? 0 : star
    }
}

/// The tasting diary for one bean. Lives in the App Group like favorites:
/// written on the bean pages in the main app, read wherever a blend is being
/// chosen (and its average boosts the quiz's matches).
struct BlendEntry: Codable, Equatable {
    /// Newest first — the order the diary is displayed in.
    var entries: [TastingEntry] = []

    init(entries: [TastingEntry] = []) { self.entries = entries }

    /// The rated cups only — an entry can carry just a note or a grind.
    var ratedCount: Int { entries.filter { $0.rating > 0 }.count }

    /// Exact mean of the rated cups, 0 when none are rated. This is what gets
    /// shown to the user ("3.8"); `rating` is its rounded form.
    var averageRating: Double {
        let rated = entries.map(\.rating).filter { $0 > 0 }
        guard !rated.isEmpty else { return 0 }
        return Double(rated.reduce(0, +)) / Double(rated.count)
    }

    /// Rounded average, 0 when nothing is rated. The single star count the quiz
    /// and the iMessage bean picker read.
    var rating: Int { Int(averageRating.rounded()) }

    /// "3.8", or "" when there is nothing to average.
    var averageText: String {
        averageRating == 0 ? "" : String(format: "%.1f", averageRating)
    }

    /// The most recent note, for one-line summaries.
    var latestNote: String {
        entries.first { !$0.note.isEmpty }?.note ?? ""
    }

    // The diary replaced a flat `{ rating, note }` per bean; decode those into
    // a single first entry so nobody loses what they already wrote.
    private enum CodingKeys: String, CodingKey { case entries, rating, note }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let entries = try container.decodeIfPresent([TastingEntry].self, forKey: .entries) {
            self.entries = entries
            return
        }
        let rating = try container.decodeIfPresent(Int.self, forKey: .rating) ?? 0
        let note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        self.entries = rating == 0 && note.isEmpty
            ? []
            : [TastingEntry(rating: rating, note: note)]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entries, forKey: .entries)
    }
}

enum BlendJournal {
    private static var defaults: UserDefaults { SharedKeys.groupDefaults }

    static var all: [String: BlendEntry] {
        guard let data = defaults.data(forKey: SharedKeys.defaultsBlendJournal),
              let entries = try? JSONDecoder().decode([String: BlendEntry].self, from: data)
        else { return [:] }
        return entries
    }

    static func entry(for id: String) -> BlendEntry { all[id] ?? BlendEntry() }

    static func set(_ entry: BlendEntry, for id: String) {
        var entries = all
        entries[id] = entry
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: SharedKeys.defaultsBlendJournal)
        }
    }

    /// Inserts a new cup or updates the existing one with the same id, keeping
    /// the diary newest-first.
    static func save(_ tasting: TastingEntry, for id: String) {
        var entry = entry(for: id)
        if let index = entry.entries.firstIndex(where: { $0.id == tasting.id }) {
            entry.entries[index] = tasting
        } else {
            entry.entries.append(tasting)
        }
        entry.entries.sort { $0.date > $1.date }
        set(entry, for: id)
    }

    static func delete(_ tastingID: UUID, for id: String) {
        var entry = entry(for: id)
        entry.entries.removeAll { $0.id == tastingID }
        set(entry, for: id)
    }
}

/// The blend-quiz scoring, shared by every platform's picker UI. Beans matching
/// the caffeine choice, best fit first: flavor agreement weighs most, then milk
/// fit, and the user's own journal rating tips the scale towards blends they
/// already liked.
enum BlendMatcher {
    enum Flavor { case chocolatey, fruity, surprise }

    static func matches(wantsDecaf: Bool, wantsMilk: Bool, flavor: Flavor,
                        limit: Int = 3) -> [MenuItem] {
        let journal = BlendJournal.all
        let scored = CoffeeMenu.beans.compactMap { bean -> (bean: MenuItem, score: Int)? in
            guard let info = BlendInfo.byID[bean.id], info.decaf == wantsDecaf else { return nil }
            var score = 0
            switch flavor {
            case .chocolatey where !info.fruity: score += 2
            case .fruity where info.fruity: score += 2
            default: break
            }
            if wantsMilk == info.lovesMilk { score += 1 }
            score += journal[bean.id]?.rating ?? 0
            return (bean, score)
        }
        return scored.sorted { $0.score > $1.score }.prefix(limit).map(\.bean)
    }
}
