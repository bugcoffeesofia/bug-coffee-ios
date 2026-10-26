import SwiftUI

/// The 3×3 loyalty stamp card, mirroring the count the phone tracks. The count
/// is App Check-gated on the backend, so it's still maintained by tapping +/-
/// on the phone; the watch is read-only.
struct WatchStampsView: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        ScrollView {
            if model.uid == nil {
                WatchSignInPrompt()
            } else {
                VStack(spacing: 12) {
                    StampCardView(count: model.stamps, slotSize: 34, spacing: 8)
                        .padding(.top, 4)
                    Text("\(model.stamps) / \(StampStore.maxStamps)")
                        .font(.headline)
                        .foregroundStyle(BugBrand.accent)
                    Text(model.stamps >= StampStore.maxStamps
                         ? "Free drink ready! 🎉"
                         : "\(StampStore.maxStamps - model.stamps) to go for a free drink")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 4)
            }
        }
        .navigationTitle("Stamps")
    }
}
