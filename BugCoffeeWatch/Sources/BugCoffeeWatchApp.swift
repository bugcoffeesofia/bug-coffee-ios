import SwiftUI

@main
struct BugCoffeeWatchApp: App {
    @StateObject private var model = WatchModel()

    var body: some Scene {
        WindowGroup {
            WatchRootView(model: model)
        }
    }
}

/// The watch home screen: a short list into the loyalty card, the stamp card,
/// caffeine logging and the beans wizard. The card and stamps need the phone to
/// have synced an account; logging and the wizard work standalone.
struct WatchRootView: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    WatchCardView(model: model)
                } label: {
                    Label("Loyalty card", systemImage: "qrcode")
                }
                NavigationLink {
                    WatchStampsView(model: model)
                } label: {
                    Label("Stamps", systemImage: "cup.and.saucer.fill")
                }
                NavigationLink {
                    WatchLogView()
                } label: {
                    Label("Log caffeine", systemImage: "drop.fill")
                }
                NavigationLink {
                    WatchBlendView()
                } label: {
                    Label("Find my blend", systemImage: "leaf.fill")
                }
            }
            .navigationTitle("Bug Coffee")
        }
    }
}

/// The loyalty QR, rendered from the PNG the phone synced over.
struct WatchCardView: View {
    @ObservedObject var model: WatchModel

    var body: some View {
        if let png = model.qr, let cg = ImageDecode.cgImage(fromPNG: png) {
            VStack(spacing: 6) {
                Image(decorative: cg, scale: 1)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .padding(6)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                Text("Bug Coffee")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .navigationTitle("Card")
        } else {
            WatchSignInPrompt()
                .navigationTitle("Card")
        }
    }
}

/// Shown on the card/stamps screens when the phone hasn't synced an account yet.
struct WatchSignInPrompt: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "iphone.and.arrow.forward")
                .font(.title2)
            Text("Sign in on your iPhone to show your loyalty card")
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
