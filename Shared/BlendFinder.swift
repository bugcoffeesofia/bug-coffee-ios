import SwiftUI

/// The guided "which blend is mine?" quiz: three taste questions matched
/// against the shop's tasting profiles (see `BlendMatcher`), boosted by the
/// user's own journal ratings so it learns what they actually liked. The caller
/// decides what picking a match means — "Use this blend" on a group-order line,
/// "Add to favorites" in the Products tab.
struct BlendFinderView: View {
    let pickLabel: String
    let onPick: (MenuItem) -> Void
    @Environment(\.dismiss) private var dismiss

    enum Caffeine: String, CaseIterable, Identifiable {
        case regular = "Regular", decaf = "Decaf"
        var id: String { rawValue }
    }
    enum Serving: String, CaseIterable, Identifiable {
        case black = "Black", milk = "With milk"
        var id: String { rawValue }
    }
    enum Flavor: String, CaseIterable, Identifiable {
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

    @State private var caffeine: Caffeine
    @State private var serving: Serving
    @State private var flavor: Flavor

    /// The answers start at regular, black, surprise me; tests pass others.
    init(pickLabel: String, caffeine: Caffeine = .regular, serving: Serving = .black,
         flavor: Flavor = .surprise, onPick: @escaping (MenuItem) -> Void) {
        self.pickLabel = pickLabel
        self.onPick = onPick
        _caffeine = State(initialValue: caffeine)
        _serving = State(initialValue: serving)
        _flavor = State(initialValue: flavor)
    }

    private let accent = Color(red: 204/255, green: 30/255, blue: 65/255)

    @ViewBuilder
    var body: some View {
        // The bar here holds nothing but Close, which is one of the two cases
        // the HIG lets opt out of iPhone Duo's vertical bar — a vertical bar
        // would take width from a form of segmented pickers to show one button.
        // Re-check in Device Hub if this sheet ever gains other bar buttons.
        #if canImport(SwiftUI, _version: 8.0.85) // iOS 27.1 SDK (Xcode 27.1)
        if #available(iOS 27.1, *) {
            finder.toolbarVerticalBehavior(.disabled)
        } else {
            finder
        }
        #else
        finder
        #endif
    }

    private var finder: some View {
        NavigationStack {
            Form {
                Section("How do you drink it?") {
                    Picker("Serving", selection: $serving) {
                        ForEach(Serving.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Caffeine", selection: $caffeine) {
                        ForEach(Caffeine.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Which direction?") {
                    Picker("Flavor", selection: $flavor) {
                        ForEach(Flavor.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Your matches") {
                    ForEach(matches) { bean in
                        matchRow(bean)
                    }
                }
            }
            .navigationTitle("Find my blend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Titled and drawn: a vertical bar shows the symbol.
                    Button {
                        dismiss()
                    } label: {
                        Label("Close", systemImage: "xmark")
                    }
                }
            }
        }
    }

    private var matches: [MenuItem] {
        BlendMatcher.matches(
            wantsDecaf: caffeine == .decaf,
            wantsMilk: serving == .milk,
            flavor: flavor.matcher
        )
    }

    private func matchRow(_ bean: MenuItem) -> some View {
        let info = BlendInfo.byID[bean.id]
        let rating = BlendJournal.entry(for: bean.id).rating
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(bean.emoji)  \(bean.name)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if rating > 0 {
                    Text(String(repeating: "★", count: rating))
                        .font(.caption)
                        .foregroundStyle(accent)
                }
            }
            if let info {
                Text(info.tastingNotes)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(accent)
                Text(info.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                onPick(bean)
                dismiss()
            } label: {
                Text(pickLabel)
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(accent, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }
}
