import WidgetKit
import SwiftUI

@main
struct StampWidgetBundle: WidgetBundle {
    var body: some Widget { StampWidget() }
}

/// Home-screen widget: the Bug Coffee stamp card. Reads the manually tracked
/// count from the App Group (see StampStore).
struct StampWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BugCoffeeStampCard", provider: StampProvider()) { entry in
            StampWidgetView(entry: entry)
        }
        .configurationDisplayName("Stamp Card")
        .description("Your Bug Coffee stamps at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StampEntry: TimelineEntry {
    let date: Date
    let count: Int
}

/// The count only changes when the user updates it in the app (which calls
/// WidgetCenter.reloadAllTimelines), so a single never-expiring entry is enough.
struct StampProvider: TimelineProvider {
    func placeholder(in context: Context) -> StampEntry {
        StampEntry(date: .now, count: 4)
    }

    func getSnapshot(in context: Context, completion: @escaping (StampEntry) -> Void) {
        completion(StampEntry(date: .now, count: context.isPreview ? 4 : StampStore.count))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StampEntry>) -> Void) {
        completion(Timeline(entries: [StampEntry(date: .now, count: StampStore.count)],
                            policy: .never))
    }
}

struct StampWidgetView: View {
    let entry: StampEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium: medium
            default: small
            }
        }
        .widgetBackground(BugBrand.brown)
    }

    private var small: some View {
        VStack(spacing: 6) {
            StampCardView(count: entry.count, slotSize: 30, spacing: 7)
            counter
        }
    }

    private var medium: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Bug Coffee")
                    .font(.headline)
                    .foregroundStyle(.white)
                counter
                Spacer(minLength: 0)
                Text(entry.count >= StampStore.maxStamps
                     ? "Free drink earned! 🎉"
                     : "\(StampStore.maxStamps - entry.count) to a free drink")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
            StampCardView(count: entry.count, slotSize: 34, spacing: 8)
        }
    }

    private var counter: some View {
        Text("\(entry.count) / \(StampStore.maxStamps)")
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(BugBrand.accent)
    }
}

private extension View {
    /// iOS 17 widgets must use containerBackground; iOS 16 gets a plain
    /// background plus the margins containerBackground would have added.
    @ViewBuilder func widgetBackground(_ color: Color) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(color, for: .widget)
        } else {
            padding(12).frame(maxWidth: .infinity, maxHeight: .infinity).background(color)
        }
    }
}
