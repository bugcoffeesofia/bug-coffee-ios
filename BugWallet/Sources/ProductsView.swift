import SwiftUI

/// The Products tab: the shop menu with drinks first and the webshop beans
/// below. Tapping the star marks a favorite; favorites float to the top of
/// their section and, through the App Group, also on top of the iMessage
/// app's menu.
struct ProductsView: View {
    /// The pushed bean pages, by bean id. Owned by RootView so an incoming
    /// `bugcoffee://bean/<id>` link can open one directly.
    @Binding var beanPath: [String]

    @State private var favorites = FavoritesStore.ids
    @State private var showBlendFinder = false
    /// Diary averages for the bean rows, refreshed whenever a cup is logged.
    @State private var journal = BlendJournal.all

    private let brand = Color(red: 31/255, green: 4/255, blue: 9/255)
    private let accent = Color(red: 204/255, green: 30/255, blue: 65/255)

    var body: some View {
        NavigationStack(path: $beanPath) {
            List {
                section("Drinks", items: CoffeeMenu.drinks)
                section("Coffee beans", items: CoffeeMenu.beans)
            }
            .navigationDestination(for: String.self) { id in
                if let item = CoffeeMenu.byID[id] {
                    BeanDetailView(item: item,
                                   isFavorite: favoriteBinding(item),
                                   accent: accent) {
                        // A cup was logged or removed — the row's average moved.
                        journal = BlendJournal.all
                    }
                }
            }
            .navigationTitle("Products")
            .toolbar {
                Button {
                    showBlendFinder = true
                } label: {
                    Label("Find my blend", systemImage: "wand.and.stars")
                }
                .tint(accent)
            }
            .sheet(isPresented: $showBlendFinder) {
                BlendFinderView(pickLabel: "Add to favorites") { bean in
                    if !favorites.contains(bean.id) {
                        favorites = FavoritesStore.toggle(bean.id)
                    }
                }
            }
        }
        // Pick up stars toggled elsewhere (e.g. in the iMessage app) whenever
        // the tab comes back on screen.
        .onAppear { favorites = FavoritesStore.ids }
    }

    private func section(_ title: String, items: [MenuItem]) -> some View {
        Section(title) {
            ForEach(CoffeeMenu.favoritesFirst(items, favorites: favorites)) { item in
                // Beans open their tasting page (shop notes + your journal).
                if item.category == .beans {
                    NavigationLink(value: item.id) {
                        row(item)
                    }
                } else {
                    row(item)
                }
            }
        }
    }

    private func row(_ item: MenuItem) -> some View {
        ProductRow(item: item,
                   isFavorite: favorites.contains(item.id),
                   diary: journal[item.id] ?? BlendEntry(),
                   accent: accent) {
            favorites = FavoritesStore.toggle(item.id)
        }
    }

    private func favoriteBinding(_ item: MenuItem) -> Binding<Bool> {
        Binding(get: { favorites.contains(item.id) },
                set: { _ in favorites = FavoritesStore.toggle(item.id) })
    }
}

/// One bean's page: the shop's tasting notes plus your diary — every cup you
/// had of it, each with its own rating, brew method, place, grind and comment.
/// The average of those ratings is what the iMessage blend picker and the
/// quiz read through the App Group.
struct BeanDetailView: View {
    let item: MenuItem
    @Binding var isFavorite: Bool
    let accent: Color
    /// Lets the products list refresh the average it shows on this bean's row.
    let onDiaryChange: () -> Void

    @State private var entry: BlendEntry
    /// Non-nil while the editor sheet is up — a new cup or one being revisited.
    @State private var editing: TastingEntry?

    init(item: MenuItem, isFavorite: Binding<Bool>, accent: Color,
         onDiaryChange: @escaping () -> Void = {}) {
        self.item = item
        self._isFavorite = isFavorite
        self.accent = accent
        self.onDiaryChange = onDiaryChange
        self._entry = State(initialValue: BlendJournal.entry(for: item.id))
    }

    /// "5 cups", or "5 cups · 4 rated" when some were logged without stars.
    private var cupCount: String {
        let total = entry.entries.count
        let label = "\(total) cup\(total == 1 ? "" : "s")"
        return entry.ratedCount == total ? label : "\(label) · \(entry.ratedCount) rated"
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(item.emoji)  \(item.name)")
                        .font(.headline)
                    if let info = BlendInfo.byID[item.id] {
                        Text(info.tastingNotes)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(accent)
                        Text(info.blurb)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text("\(item.size) · \(Price.dual(item.cents))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if entry.rating > 0 {
                Section("Your average") {
                    HStack(spacing: 8) {
                        Text(entry.averageText)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(accent)
                        StarRow(rating: entry.rating, accent: accent)
                        Spacer()
                        Text(cupCount)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Diary") {
                ForEach(entry.entries) { tasting in
                    Button {
                        editing = tasting
                    } label: {
                        TastingRow(tasting: tasting, accent: accent)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    for index in offsets {
                        BlendJournal.delete(entry.entries[index].id, for: item.id)
                    }
                    entry = BlendJournal.entry(for: item.id)
                    onDiaryChange()
                }

                Button {
                    editing = TastingEntry()
                } label: {
                    Label("Add a cup", systemImage: "plus.circle.fill")
                }
                .tint(accent)
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Hands out this bean's deep link, so a tap in Messages or Notes
            // reopens the app straight on this page.
            if let link = BeanLink.url(for: item) {
                ShareLink(item: link,
                          subject: Text(item.name),
                          message: Text(BlendInfo.byID[item.id]?.tastingNotes ?? ""))
            }
            Button {
                isFavorite.toggle()
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .foregroundStyle(isFavorite ? accent : Color.secondary)
            }
        }
        .sheet(item: $editing) { tasting in
            TastingEditor(tasting: tasting, beanName: item.name, accent: accent) { saved in
                // An entry the user opened and left blank isn't worth keeping.
                if saved.isEmpty {
                    BlendJournal.delete(saved.id, for: item.id)
                } else {
                    BlendJournal.save(saved, for: item.id)
                }
                entry = BlendJournal.entry(for: item.id)
                onDiaryChange()
            }
        }
    }
}

/// One line in a bean's diary: when, how, where, and what you thought.
private struct TastingRow: View {
    let tasting: TastingEntry
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("\(tasting.method.emoji)  \(tasting.method.name)")
                    .font(.subheadline.weight(.medium))
                Spacer()
                if tasting.rating > 0 {
                    StarRow(rating: tasting.rating, accent: accent, size: .caption)
                }
            }
            Text("\(tasting.place.emoji) \(tasting.place.name) · \(tasting.date.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !tasting.grind.isEmpty {
                Text("Grind: \(tasting.grind)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !tasting.note.isEmpty {
                Text(tasting.note)
                    .font(.footnote)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct StarRow: View {
    let rating: Int
    let accent: Color
    var size: Font = .subheadline

    var body: some View {
        Text(String(repeating: "★", count: rating))
            .font(size)
            .foregroundStyle(accent)
            .accessibilityLabel("\(rating) out of 5")
    }
}

/// The add/edit sheet for a single cup.
private struct TastingEditor: View {
    @State private var tasting: TastingEntry
    let beanName: String
    let accent: Color
    let onSave: (TastingEntry) -> Void

    @Environment(\.dismiss) private var dismiss

    init(tasting: TastingEntry, beanName: String, accent: Color,
         onSave: @escaping (TastingEntry) -> Void) {
        self._tasting = State(initialValue: tasting)
        self.beanName = beanName
        self.accent = accent
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("How was it?") {
                    HStack(spacing: 8) {
                        ForEach(1...5, id: \.self) { star in
                            Button {
                                // Tapping the current rating clears it.
                                tasting.rating = tasting.rating == star ? 0 : star
                            } label: {
                                Image(systemName: star <= tasting.rating ? "star.fill" : "star")
                                    .font(.title2)
                                    .foregroundStyle(star <= tasting.rating ? accent : Color.secondary.opacity(0.4))
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                Section("The cup") {
                    Picker("Made as", selection: $tasting.method) {
                        Section("Espresso bar") {
                            ForEach(BrewMethod.espressoBar) { method in
                                Text("\(method.emoji)  \(method.name)").tag(method)
                            }
                        }
                        Section("Brewed") {
                            ForEach(BrewMethod.brewed) { method in
                                Text("\(method.emoji)  \(method.name)").tag(method)
                            }
                        }
                    }
                    Picker("Where", selection: $tasting.place) {
                        ForEach(BrewPlace.allCases) { place in
                            Text("\(place.emoji)  \(place.name)").tag(place)
                        }
                    }
                    DatePicker("When", selection: $tasting.date, displayedComponents: .date)
                }

                Section {
                    TextField("Grind size (\"18 clicks\", \"medium-fine\"…)",
                              text: $tasting.grind)
                    TextField("What did you think? (\"syrupy\", \"sour — grind finer\"…)",
                              text: $tasting.note, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Notes")
                } footer: {
                    // Only you touched the grinder when you brewed it yourself.
                    if !tasting.place.grindsOwnBeans {
                        Text("Grind is worth noting when you ground the beans yourself.")
                    }
                }
            }
            .navigationTitle(beanName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(tasting)
                        dismiss()
                    }
                    .disabled(tasting.isEmpty)
                }
            }
        }
    }
}

private struct ProductRow: View {
    let item: MenuItem
    let isFavorite: Bool
    /// Empty for drinks and for beans you haven't logged a cup of yet.
    var diary = BlendEntry()
    let accent: Color
    let toggleFavorite: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.emoji)  \(item.name)")
                HStack(spacing: 4) {
                    Text("\(item.size) · \(Price.dual(item.cents))")
                    if diary.rating > 0 {
                        Text("· ★ \(diary.averageText)")
                            .foregroundStyle(accent)
                            .accessibilityLabel("your average \(diary.averageText) out of 5")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(isFavorite ? accent : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isFavorite ? "Remove \(item.name) from favorites"
                                           : "Add \(item.name) to favorites")
        }
        .animation(.default, value: isFavorite)
    }
}
