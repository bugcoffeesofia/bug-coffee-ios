import Foundation

/// A product on the Bug Coffee menu, shared by the main app's Products tab and
/// the iMessage group order. Drinks are transcribed from the board in the shop;
/// beans come from the webshop (bugcoffee.com/en/kategoriya/kafe/).
struct MenuItem: Identifiable, Hashable {
    enum Category {
        case drink
        case beans
    }

    /// Short stable code — this is what goes into the message URL.
    let id: String
    let name: String
    let emoji: String
    /// Base price in euro cents. For beans this is the 250 g bag.
    let cents: Int
    /// Serving size as shown under the name ("220 мл", "250 г").
    let size: String
    let category: Category
    /// Can be made with alternative milk (oat/almond/coconut/pea).
    let allowsMilk: Bool
    /// Can be made decaf (espresso-based drinks).
    let allowsDecaf: Bool

    /// Brewed from coffee, so the drinker can pick which bean it's made from.
    /// Exactly the decaf-able drinks — both mean "espresso or filter based".
    var isCoffee: Bool { category == .drink && allowsDecaf }
}

struct MilkOption: Identifiable, Hashable {
    let id: String
    let name: String
}

enum CoffeeMenu {
    /// Алтернативно мляко — +0.60 € / 1.17 лв.
    static let milkSurchargeCents = 60
    /// Switching to decaf is free.
    static let decafSurchargeCents = 0

    static let milks: [MilkOption] = [
        .init(id: "oat", name: "Oat"),
        .init(id: "alm", name: "Almond"),
        .init(id: "coc", name: "Coconut"),
        .init(id: "pea", name: "Pea"),
    ]
    static let milkByID = Dictionary(uniqueKeysWithValues: milks.map { ($0.id, $0) })

    static let drinks: [MenuItem] = [
        .init(id: "esp", name: "Espresso",        emoji: "☕️", cents: 190, size: "25 мл",  category: .drink, allowsMilk: false, allowsDecaf: true),
        .init(id: "dsp", name: "Double Espresso", emoji: "☕️", cents: 260, size: "50 мл",  category: .drink, allowsMilk: false, allowsDecaf: true),
        .init(id: "ame", name: "Americano",       emoji: "☕️", cents: 260, size: "200 мл", category: .drink, allowsMilk: false, allowsDecaf: true),
        .init(id: "mac", name: "Macchiato",       emoji: "🥛", cents: 260, size: "50 мл",  category: .drink, allowsMilk: true,  allowsDecaf: true),
        .init(id: "cor", name: "Cortado",         emoji: "🥛", cents: 310, size: "100 мл", category: .drink, allowsMilk: true,  allowsDecaf: true),
        .init(id: "flw", name: "Flat White",      emoji: "☕️", cents: 330, size: "150 мл", category: .drink, allowsMilk: true,  allowsDecaf: true),
        .init(id: "cap", name: "Cappuccino",      emoji: "☕️", cents: 310, size: "220 мл", category: .drink, allowsMilk: true,  allowsDecaf: true),
        .init(id: "lat", name: "Latte",           emoji: "🥛", cents: 330, size: "290 мл", category: .drink, allowsMilk: true,  allowsDecaf: true),
        .init(id: "v60", name: "V60",             emoji: "🫖", cents: 330, size: "220 мл", category: .drink, allowsMilk: false, allowsDecaf: true),
        .init(id: "ton", name: "Espresso Tonic",  emoji: "🍹", cents: 330, size: "150 мл", category: .drink, allowsMilk: false, allowsDecaf: true),
        .init(id: "tea", name: "Tea",             emoji: "🍵", cents: 180, size: "260 мл", category: .drink, allowsMilk: false, allowsDecaf: false),
        .init(id: "cha", name: "Chai Latte",      emoji: "🍵", cents: 310, size: "290 мл", category: .drink, allowsMilk: true,  allowsDecaf: false),
        .init(id: "mtt", name: "Matcha Tea",      emoji: "🍵", cents: 310, size: "260 мл", category: .drink, allowsMilk: false, allowsDecaf: false),
        .init(id: "mtl", name: "Matcha Latte",    emoji: "🍵", cents: 330, size: "290 мл", category: .drink, allowsMilk: true,  allowsDecaf: false),
        .init(id: "cho", name: "Hot Chocolate",   emoji: "🍫", cents: 310, size: "220 мл", category: .drink, allowsMilk: true,  allowsDecaf: false),
    ]

    /// Whole-bean bags from the webshop coffee category; prices are the 250 g
    /// variant (blends also come in 1 kg, not sold through the app).
    static let beans: [MenuItem] = [
        .init(id: "bbe", name: "Decaf Bette Buna · Ethiopia", emoji: "🫘", cents: 1530, size: "250 г", category: .beans, allowsMilk: false, allowsDecaf: false),
        .init(id: "bmb", name: "Bombe · Ethiopia",            emoji: "🫘", cents: 1390, size: "250 г", category: .beans, allowsMilk: false, allowsDecaf: false),
        .init(id: "sjp", name: "San Jose · Peru",             emoji: "🫘", cents: 1320, size: "250 г", category: .beans, allowsMilk: false, allowsDecaf: false),
        .init(id: "mkw", name: "Mukuru West · Uganda",        emoji: "🫘", cents: 1430, size: "250 г", category: .beans, allowsMilk: false, allowsDecaf: false),
        .init(id: "sir", name: "Siracusa · Colombia",         emoji: "🫘", cents: 1530, size: "250 г", category: .beans, allowsMilk: false, allowsDecaf: false),
        .init(id: "kal", name: "Kalinka Blend",               emoji: "🫘", cents: 1170, size: "250 г", category: .beans, allowsMilk: false, allowsDecaf: false),
        .init(id: "ban", name: "Bandit Blend",                emoji: "🫘", cents: 1170, size: "250 г", category: .beans, allowsMilk: false, allowsDecaf: false),
        .init(id: "kul", name: "Kultura House Blend",         emoji: "🫘", cents: 1170, size: "250 г", category: .beans, allowsMilk: false, allowsDecaf: false),
    ]

    static let all: [MenuItem] = drinks + beans

    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Favorites first (in menu order), the rest below — used by both product
    /// lists so a starred drink floats to the top of its section.
    static func favoritesFirst(_ items: [MenuItem], favorites: Set<String>) -> [MenuItem] {
        items.filter { favorites.contains($0.id) } + items.filter { !favorites.contains($0.id) }
    }
}

/// Price formatting. Bulgaria displays dual €/лв.; the лв. side is derived at
/// the fixed conversion rate, which reproduces the board's printed values.
enum Price {
    static let bgnPerEur = 1.95583

    static func euro(_ cents: Int) -> String {
        String(format: "%.2f €", Double(cents) / 100)
    }

    static func dual(_ cents: Int) -> String {
        let eur = Double(cents) / 100
        return String(format: "%.2f € / %.2f лв.", eur, eur * bgnPerEur)
    }
}

/// Favorite product IDs, stored in the App Group so the main app and the
/// iMessage extension always see the same set (favorites starred in one show
/// up in the other on next launch). Purely local — nothing about favorites
/// travels in the message.
enum FavoritesStore {
    private static var defaults: UserDefaults { SharedKeys.groupDefaults }

    static var ids: Set<String> {
        Set(defaults.stringArray(forKey: SharedKeys.defaultsFavorites) ?? [])
    }

    static func toggle(_ id: String) -> Set<String> {
        var current = ids
        if !current.insert(id).inserted { current.remove(id) }
        defaults.set(Array(current).sorted(), forKey: SharedKeys.defaultsFavorites)
        return current
    }

    /// Stars `id` if it isn't starred yet; never un-stars.
    static func add(_ id: String) -> Set<String> {
        ids.contains(id) ? ids : toggle(id)
    }
}
