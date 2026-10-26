import SwiftUI

/// The beans wizard, watch-flavored: three taps to answer how you drink it and
/// what you're after, then the best-matching bags from the shop. Reuses the
/// shared `BlendMatcher` scoring. No segmented pickers (unavailable on watchOS)
/// — plain Pickers render as tappable navigation rows here.
struct WatchBlendView: View {
    private enum Caffeine: String, CaseIterable, Identifiable {
        case regular = "Regular", decaf = "Decaf"
        var id: String { rawValue }
    }
    private enum Serving: String, CaseIterable, Identifiable {
        case black = "Black", milk = "With milk"
        var id: String { rawValue }
    }
    private enum Flavor: String, CaseIterable, Identifiable {
        case chocolatey = "Chocolate & nuts", fruity = "Fruity & bright", surprise = "Surprise me"
        var id: String { rawValue }

        var matcher: BlendMatcher.Flavor {
            switch self {
            case .chocolatey: return .chocolatey
            case .fruity:     return .fruity
            case .surprise:   return .surprise
            }
        }
    }

    @State private var caffeine = Caffeine.regular
    @State private var serving = Serving.black
    @State private var flavor = Flavor.surprise

    var body: some View {
        List {
            Section("How do you drink it?") {
                Picker("Serving", selection: $serving) {
                    ForEach(Serving.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Caffeine", selection: $caffeine) {
                    ForEach(Caffeine.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section("Which direction?") {
                Picker("Flavor", selection: $flavor) {
                    ForEach(Flavor.allCases) { Text($0.rawValue).tag($0) }
                }
            }
            Section("Your matches") {
                ForEach(matches) { bean in
                    matchRow(bean)
                }
            }
        }
        .navigationTitle("Find my blend")
    }

    private var matches: [MenuItem] {
        BlendMatcher.matches(
            wantsDecaf: caffeine == .decaf,
            wantsMilk: serving == .milk,
            flavor: flavor.matcher
        )
    }

    private func matchRow(_ bean: MenuItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("\(bean.emoji)  \(bean.name)")
                .font(.footnote.weight(.semibold))
            if let info = BlendInfo.byID[bean.id] {
                Text(info.tastingNotes)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(BugBrand.accent)
                Text(info.blurb)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
