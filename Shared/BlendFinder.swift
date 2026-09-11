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
    }

    @State private var caffeine = Caffeine.regular
    @State private var serving = Serving.black
    @State private var flavor = Flavor.surprise

    private let accent = Color(red: 204/255, green: 30/255, blue: 65/255)

    var body: some View {
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
        // TODO(iPhone Duo, iOS 27.1 SDK): a sheet whose only control is Close is
        // one of the two cases the HIG lets opt out of the vertical bar. Try it in
        // Device Hub; if a horizontal bar reads better on the outer display, opt
        // out once the modifier ships (it's not in the iOS 27.0 SDK):
        //
        //     .toolbarVerticalBehavior(.disabled)
    }

    private var matches: [MenuItem] {
        BlendMatcher.matches(
            wantsDecaf: caffeine == .decaf,
            wantsMilk: serving == .milk,
            flavor: {
                switch flavor {
                case .chocolatey: return .chocolatey
                case .fruity:     return .fruity
                case .surprise:   return .surprise
                }
            }()
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
