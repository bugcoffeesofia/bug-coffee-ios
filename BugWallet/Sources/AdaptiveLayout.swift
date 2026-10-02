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
                    // The width keeps narrow content centered: a GeometryReader
                    // leaves it against the leading edge otherwise, which shows
                    // up the moment this holds one half of an arrangement.
                    .frame(width: proxy.size.width)
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

// MARK: - iPhone Duo reserved regions
//
// The fold and the camera cut-outs are "reserved regions": areas that
// hand-placed content should stay out of. They arrived in the iOS 27.1 SDK, so
// every call below is gated twice — `canImport(_version:)` so Xcode 26 and 27.0
// still build the project, and `#available` because the app runs back to iOS 16.
// (SwiftUI's module version is 8.0.84 in the 27.0 SDK and 8.0.85 in 27.1.)

extension View {
    /// Reports how far a camera cut-out reaches into the top of this view, so a
    /// row along the top edge can pad itself clear of it. Reports 0 when the
    /// safe area already clears the camera — the usual case — on a device
    /// without one, and before iOS 27.1.
    ///
    /// Measure this on a view that doesn't move in response: measuring the
    /// padded row itself would feed its own padding back into the next reading.
    @ViewBuilder
    func onCameraOcclusionChange(perform action: @escaping (CGFloat) -> Void) -> some View {
        #if canImport(SwiftUI, _version: 8.0.85) // iOS 27.1 SDK (Xcode 27.1)
        if #available(iOS 27.1, *) {
            onGeometryChange(for: CGFloat.self) { proxy in
                proxy.reservedRegions(kind: .occlusion)
                    .map(\.frame.maxY)
                    .max() ?? 0
            } action: { action(max(0, $0)) }
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// Reports the trailing edge of a *vertical* fold crossing this view — the
    /// book pose, where anything centered on screen would sit on the crease.
    /// Reports 0 when the device is flat, when the fold is horizontal (propped
    /// on a table, where a centered row is fine), and before iOS 27.1.
    @ViewBuilder
    func onVerticalFoldChange(perform action: @escaping (CGFloat) -> Void) -> some View {
        #if canImport(SwiftUI, _version: 8.0.85) // iOS 27.1 SDK (Xcode 27.1)
        if #available(iOS 27.1, *) {
            onGeometryChange(for: CGFloat.self) { proxy in
                proxy.reservedRegions(kind: .division)
                    .map(\.frame)
                    .filter { $0.height > $0.width } // a vertical crease only
                    .map(\.maxX)
                    .max() ?? 0
            } action: { action(max(0, $0)) }
        } else {
            self
        }
        #else
        self
        #endif
    }
}
