import SwiftUI
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Brand colors, shared by the app views and the widget.
enum BugBrand {
    static let brown = Color(red: 31/255, green: 4/255, blue: 9/255)
    static let accent = Color(red: 204/255, green: 30/255, blue: 65/255)
    static let cream = Color(red: 246/255, green: 238/255, blue: 227/255)
}

/// The manually tracked stamp count (0...9), stored in the App Group so the
/// home-screen widget can read it. The live count is App Check-gated on the
/// backend, so the user taps + in the app whenever the barista adds
/// a stamp.
enum StampStore {
    /// `maxStamps = 9` on the real card — 9 stamps means free drink.
    static let maxStamps = 9

    private static var defaults: UserDefaults { SharedKeys.groupDefaults }

    static var count: Int {
        min(max(defaults.integer(forKey: SharedKeys.defaultsStamps), 0), maxStamps)
    }

    static func setCount(_ value: Int) {
        defaults.set(min(max(value, 0), maxStamps), forKey: SharedKeys.defaultsStamps)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}

/// The 3×3 grid of stamp slots. Collected stamps sit slightly off their slot
/// with a small rotation, like real ink stamps on a paper card. The jitter is
/// seeded by the slot index, so the card renders identically every time — no
/// stamps jumping around between widget refreshes.
struct StampCardView: View {
    let count: Int
    var slotSize: CGFloat = 40
    var spacing: CGFloat = 10

    var body: some View {
        Grid(horizontalSpacing: spacing, verticalSpacing: spacing) {
            ForEach(0..<3, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        slot(row * 3 + column)
                    }
                }
            }
        }
    }

    private func slot(_ index: Int) -> some View {
        ZStack {
            Circle()
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .foregroundStyle(BugBrand.cream.opacity(0.35))
            if index < count {
                stamp(index)
            }
        }
        .frame(width: slotSize, height: slotSize)
    }

    private func stamp(_ index: Int) -> some View {
        let jitter = SlotJitter(slot: index)
        return ZStack {
            Circle()
                .strokeBorder(BugBrand.accent, lineWidth: slotSize * 0.07)
            Image(systemName: "cup.and.saucer.fill")
                .font(.system(size: slotSize * 0.4, weight: .bold))
                .foregroundStyle(BugBrand.accent)
        }
        .frame(width: slotSize, height: slotSize)
        .rotationEffect(jitter.rotation)
        .offset(jitter.offset(for: slotSize))
        .opacity(0.92)
    }
}

/// Deterministic pseudo-random placement for one stamp (splitmix64 seeded by
/// the slot index): rotation within ±20°, offset within ±12% of the slot.
struct SlotJitter {
    let rotation: Angle
    private let dx: Double
    private let dy: Double

    init(slot: Int) {
        var state = UInt64(slot &+ 1) &* 0x9E3779B97F4A7C15
        func unit() -> Double {  // 0..<1
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return Double((z ^ (z >> 31)) >> 11) / Double(1 << 53)
        }
        rotation = .degrees((unit() - 0.5) * 40)
        dx = unit() - 0.5
        dy = unit() - 0.5
    }

    func offset(for slotSize: CGFloat) -> CGSize {
        CGSize(width: dx * slotSize * 0.24, height: dy * slotSize * 0.24)
    }
}
