import SwiftUI

/// A vertical scroll view that lays its content out at least as tall as the
/// visible area, so a screen built from a `VStack` and `Spacer`s looks exactly
/// as before while it fits — and scrolls instead of clipping when it doesn't.
///
/// iPhone Duo can hand the app far less height than an iPhone screen: Split
/// View and the video stacking layout on the inner display, the keyboard, the
/// largest Dynamic Type sizes. Every control has to stay reachable in all of
/// them, which a fixed-height stack can't promise.
///
/// The content gets the visible size, so a screen can pick its arrangement
/// from the space it actually has (see `CardView.regularLayout`).
struct FittingScrollView<Content: View>: View {
    @ViewBuilder let content: (CGSize) -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content(proxy.size)
                    .frame(minHeight: proxy.size.height)
            }
            .scrollBouncesOnlyWhenNeeded()
        }
    }
}

extension View {
    /// Keeps a scroll view still while everything fits (iOS 16.4+).
    @ViewBuilder
    func scrollBouncesOnlyWhenNeeded() -> some View {
        if #available(iOS 16.4, *) {
            scrollBounceBehavior(.basedOnSize)
        } else {
            self
        }
    }
}
