import SwiftUI

/// Brand palette, same values as the main app's CardView.
enum Brand {
    static let dark = Color(red: 31/255, green: 4/255, blue: 9/255)
    static let accent = Color(red: 204/255, green: 30/255, blue: 65/255)
}

struct OrderRootView: View {
    @ObservedObject var store: OrderStore

    var body: some View {
        if store.isExpanded {
            ExpandedOrderView(store: store)
        } else {
            CompactOrderView(store: store)
        }
    }
}

/// What shows in the small drawer under the keyboard — just a call to action.
struct CompactOrderView: View {
    @ObservedObject var store: OrderStore

    var body: some View {
        ZStack {
            Brand.dark.ignoresSafeArea()
            VStack(spacing: 12) {
                Text("☕️ Bug Coffee")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                Text(store.isJoiningExistingOrder
                     ? "There's a coffee run going — add your drinks!"
                     : "Start a group coffee order for this chat.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                Button {
                    store.onRequestExpand?()
                } label: {
                    Text(store.isJoiningExistingOrder ? "Add my order" : "Start a coffee run")
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Brand.accent, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding()
        }
    }
}

struct ExpandedOrderView: View {
    @ObservedObject var store: OrderStore

    var body: some View {
        VStack(spacing: 0) {
            header
            List {
                if !store.othersLines.isEmpty {
                    Section {
                        ForEach(store.othersLines) { line in
                            HStack {
                                Text("\(line.qty)× \(line.title)")
                                Spacer()
                                Text(store.label(for: line.participant))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } header: {
                        Text("Order so far")
                    } footer: {
                        Text(Price.dual(store.othersLines.reduce(0) { $0 + $1.totalCents }))
                    }
                }

                Section("Your drinks") {
                    if store.myLines.isEmpty {
                        Text("Pick something from the menu below")
                            .foregroundStyle(.secondary)
                    }
                    ForEach($store.myLines) { $line in
                        MyDrinkRow(line: $line)
                    }
                    .onDelete { store.myLines.remove(atOffsets: $0) }
                }

                menuSection("Menu", items: store.menuDrinks)
                menuSection("Coffee beans", items: store.menuBeans)
            }

            submitBar
        }
        .background(Color(.systemGroupedBackground))
    }

    /// One menu section, favorites already sorted to the top by the store.
    private func menuSection(_ title: String, items: [MenuItem]) -> some View {
        Section(title) {
            ForEach(items) { item in
                MenuRow(item: item,
                        isFavorite: store.favorites.contains(item.id),
                        toggleFavorite: { store.toggleFavorite(item) },
                        add: { store.add(item) })
            }
        }
    }

    private var header: some View {
        HStack {
            Text("Bug Coffee — group order")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
        }
        .padding()
        .background(Brand.dark)
    }

    private var submitBar: some View {
        VStack(spacing: 8) {
            if store.canSubmit {
                HStack {
                    Text("Your drinks")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Price.dual(store.myTotalCents))
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
            }
            Button {
                store.onSubmit?()
            } label: {
                Text(store.isJoiningExistingOrder ? "Add my drinks to the order" : "Send order to the chat")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(store.canSubmit ? Brand.accent : Color.gray.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: 14))
                    .foregroundStyle(.white)
            }
            .disabled(!store.canSubmit)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

/// A drink already in "your drinks": quantity stepper plus decaf / alternative
/// milk toggles where the drink supports them (both change the price), and the
/// bean picker on coffee-based drinks.
struct MyDrinkRow: View {
    @Binding var line: OrderLine
    @State private var showBlendFinder = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(line.title)
                Spacer()
                Stepper("\(line.qty)", value: $line.qty, in: 1...9)
                    .fixedSize()
            }
            HStack(spacing: 8) {
                if line.drink?.allowsDecaf == true {
                    Button {
                        line.decaf.toggle()
                    } label: {
                        chip("Decaf", active: line.decaf)
                    }
                    .buttonStyle(.borderless)
                }
                if line.drink?.allowsMilk == true {
                    Menu {
                        Button("Regular milk") { line.milk = "" }
                        ForEach(CoffeeMenu.milks) { milk in
                            Button("\(milk.name) (+\(Price.euro(CoffeeMenu.milkSurchargeCents)))") {
                                line.milk = milk.id
                            }
                        }
                    } label: {
                        chip(CoffeeMenu.milkByID[line.milk]?.name.appending(" milk") ?? "Regular milk",
                             active: !line.milk.isEmpty, chevron: true)
                    }
                }
                Spacer()
                Text(Price.euro(line.totalCents))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            // Which bean the coffee is brewed from — its own row, the origin
            // names are long. Journal ratings from the main app show up next
            // to the beans; the finder is the guided quiz for the undecided.
            if line.drink?.isCoffee == true {
                Menu {
                    Button {
                        showBlendFinder = true
                    } label: {
                        Label("Find my blend…", systemImage: "wand.and.stars")
                    }
                    Divider()
                    Button("House blend") { line.blend = "" }
                    ForEach(CoffeeMenu.beans) { bean in
                        Button(beanMenuTitle(bean)) { line.blend = bean.id }
                    }
                } label: {
                    chip("🫘 \(CoffeeMenu.byID[line.blend]?.name ?? "House blend")",
                         active: !line.blend.isEmpty, chevron: true)
                }
                .sheet(isPresented: $showBlendFinder) {
                    BlendFinderView(pickLabel: "Use this blend") { line.blend = $0.id }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func beanMenuTitle(_ bean: MenuItem) -> String {
        let rating = BlendJournal.entry(for: bean.id).rating
        return rating > 0 ? "\(bean.name) · \(String(repeating: "★", count: rating))" : bean.name
    }

    private func chip(_ text: String, active: Bool, chevron: Bool = false) -> some View {
        HStack(spacing: 3) {
            Text(text)
            if chevron { Image(systemName: "chevron.down").font(.system(size: 9)) }
        }
        .font(.footnote.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(active ? Brand.accent : Brand.accent.opacity(0.12), in: Capsule())
        .foregroundStyle(active ? .white : Brand.accent)
    }
}

/// A menu entry: name, size, dual price, a favorite star and an add button.
struct MenuRow: View {
    let item: MenuItem
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    let add: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(item.emoji)  \(item.name)")
                Text("\(item.size) · \(Price.dual(item.cents))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.title3)
                    .foregroundStyle(isFavorite ? Brand.accent : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isFavorite ? "Remove \(item.name) from favorites"
                                           : "Add \(item.name) to favorites")
            Button(action: add) {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Brand.accent)
            }
            .buttonStyle(.borderless)
        }
    }
}
