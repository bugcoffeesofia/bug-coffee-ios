import SwiftUI
import PassKit

/// The clip's card: the loyalty QR, the stamp count and "Add to Apple Wallet".
/// A cut-down `CardView` — one column, no Health logging, no scan-and-share.
struct ClipCardView: View {
    let account: Account
    @EnvironmentObject private var session: Session
    @Environment(\.scenePhase) private var scenePhase
    // Observed for the live count and its status line.
    @ObservedObject private var webSync = StampWebSync.shared

    // The App Group count, so a stamp tapped here shows up in the full app and
    // its widget once that's installed.
    @State private var stamps = StampStore.count

    // Local (on-device) pass creation — only compiled into the Debug-LocalPass
    // config. See Config/LocalPassCreation.xcconfig.
    #if LOCAL_PASS_CREATION
    private enum WalletStatus { case checking, inWallet, notInWallet }
    @State private var walletStatus: WalletStatus = .checking
    @State private var signedPassData: Data?
    @State private var addPassesDelegate: AddPassesDelegate?
    @State private var isAdding = false
    @State private var addResult: String?
    #endif

    var body: some View {
        ZStack {
            BugBrand.brown.ignoresSafeArea()
            FittingScrollView { _ in
                VStack(spacing: 20) {
                    header
                    Spacer()
                    qrSection
                    Spacer()
                    stampsSection
                    Spacer()
                    walletSection
                    footer
                }
                .frame(maxWidth: 440)
            }
        }
        .onChange(of: stamps) { StampStore.setCount($0) }
        // The backend is authoritative — adopt the live count when it arrives.
        .onReceive(webSync.$backendCount.compactMap { $0 }) { stamps = $0 }
        .task {
            #if LOCAL_PASS_CREATION
            await refreshWalletStatus()
            #endif
        }
        // Re-check when coming back from the background — the user may have
        // removed (or added) the pass in the Wallet app meanwhile.
        .onChange(of: scenePhase) { phase in
            #if LOCAL_PASS_CREATION
            if phase == .active { Task { await refreshWalletStatus() } }
            #endif
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Bug Coffee")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text(account.email)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer()
            Button("Sign out") { session.signOut() }
                .font(.caption)
                .foregroundStyle(BugBrand.accent)
        }
        .padding(.horizontal)
        .padding(.top)
    }

    private var qrSection: some View {
        VStack(spacing: 20) {
            // The loyalty QR — the raw Firebase UID, level H.
            if let qr = QRGenerator.image(from: account.uid) {
                Image(uiImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
            }

            Text("Show this to the barista")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
        }
    }

    // The live count is App Check-gated, so +/- stays as the manual fallback
    // for when the web sync can't read it.
    private var stampsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Stamps")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer()
                Text("\(stamps) / \(StampStore.maxStamps)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(BugBrand.accent)
                stepButton("minus.circle.fill") { stamps = max(0, stamps - 1) }
                stepButton("plus.circle.fill") { stamps = min(StampStore.maxStamps, stamps + 1) }
            }
            StampCardView(count: stamps, slotSize: 34, spacing: 8)
            Text("Backend: \(webSync.status)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var walletSection: some View {
        #if LOCAL_PASS_CREATION
        VStack(spacing: 12) {
            switch walletStatus {
            case .checking:
                Color.clear.frame(height: 48)
            case .inWallet:
                Label("In Apple Wallet", systemImage: "checkmark.seal.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(height: 48)
            case .notInWallet:
                AddToWalletButton(action: handleAddToWallet)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .opacity(isAdding ? 0.5 : 1)
                    .disabled(isAdding)
            }
            if let addResult {
                Text(addResult)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .padding(.horizontal)
        #endif
    }

    private var footer: some View {
        Text("UID: \(account.uid)")
            .font(.caption2.monospaced())
            .foregroundStyle(.white.opacity(0.4))
            .textSelection(.enabled)
            .padding(.bottom)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(BugBrand.accent)
        }
    }

    // MARK: - Local pass creation (Debug-LocalPass config only)
    #if LOCAL_PASS_CREATION
    /// Builds (or reuses) the signed pass and asks Wallet whether it's already added.
    private func refreshWalletStatus() async {
        guard PKPassLibrary.isPassLibraryAvailable() else {
            walletStatus = .notInWallet
            return
        }
        do {
            let pass = try PKPass(data: try await signedPass())
            walletStatus = PKPassLibrary().containsPass(pass) ? .inWallet : .notInWallet
        } catch {
            // Can't build the pass here — keep the button so the add flow
            // can surface the error to the user.
            walletStatus = .notInWallet
        }
    }

    /// The signed .pkpass for this account, built on first use and cached.
    private func signedPass() async throws -> Data {
        if let cached = signedPassData { return cached }
        // Signing does RSA + zip work; keep it off the main thread.
        let data = try await Task.detached(priority: .userInitiated) {
            try PassBuilder.buildSignedPass(for: account)
        }.value
        signedPassData = data
        return data
    }

    private func handleAddToWallet() {
        guard !isAdding else { return }
        isAdding = true
        addResult = nil
        Task {
            defer { isAdding = false }
            do {
                let pass = try PKPass(data: try await signedPass())
                guard let vc = PKAddPassesViewController(pass: pass) else {
                    addResult = "Wallet couldn't open this pass."
                    return
                }
                // Re-check once the Wallet sheet closes so the button hides
                // immediately after a successful add.
                let delegate = AddPassesDelegate {
                    Task { await refreshWalletStatus() }
                }
                addPassesDelegate = delegate
                vc.delegate = delegate
                WalletPresenter.topViewController()?.present(vc, animated: true)
            } catch {
                addResult = "Couldn't build pass: \(error.localizedDescription)"
            }
        }
    }
    #endif
}
