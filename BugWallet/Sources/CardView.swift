import SwiftUI
import PassKit
import Combine

/// The card's stamp counter and "Log a coffee" state, kept out of the view so
/// it can be unit tested.
@MainActor
final class CardModel: ObservableObject {
    /// The manually tracked count. Every change is written to the App Group
    /// (→ widget) and pushed to the watch.
    @Published var stamps: Int {
        didSet {
            guard stamps != oldValue else { return }
            StampStore.setCount(stamps)
            WatchSync.shared.syncStamps(stamps)
        }
    }
    @Published private(set) var logResult: String?
    @Published private(set) var isLogging = false

    private let logDrink: (CoffeeDrink) async throws -> Void
    private var liveCount: AnyCancellable?

    init(stamps: Int? = nil,
         webSync: StampWebSync? = nil,
         logDrink: @escaping (CoffeeDrink) async throws -> Void = { try await HealthLogger.log($0) }) {
        let webSync = webSync ?? .shared
        self.stamps = stamps ?? StampStore.count
        self.logDrink = logDrink
        // The App Check WebView reads the live count from the backend.
        // The backend is authoritative — adopt the live count when
        // it arrives (this also overrides a stale manual value).
        liveCount = webSync.$backendCount
            .compactMap { $0 }
            .sink { [weak self] live in self?.stamps = live }
    }

    func increment() { stamps = min(StampStore.maxStamps, stamps + 1) }
    func decrement() { stamps = max(0, stamps - 1) }

    /// Logs one drink to Apple Health as dietary caffeine.
    func log(_ drink: CoffeeDrink) async {
        guard !isLogging else { return }
        isLogging = true
        logResult = nil
        defer { isLogging = false }
        do {
            try await logDrink(drink)
            logResult = "\(drink.name) logged to Health ☕️"
        } catch {
            logResult = error.localizedDescription
        }
    }
}

struct CardView: View {
    let account: Account
    @EnvironmentObject private var session: Session
    @Environment(\.scenePhase) private var scenePhase
    // Compact on iPhones, iPhone Duo's outer display and a narrow Split View;
    // regular on the Duo's inner display (and iPad), which gets the two-half
    // layout.
    @Environment(\.horizontalSizeClass) private var widthClass
    /// How far the outer display's front camera reaches into the top edge.
    /// Stays 0 unless the safe area leaves it in the header's way (iOS 27.1+).
    @State private var cameraInset: CGFloat = 0

    // Local (on-device) pass creation state — only compiled into the
    // Debug-LocalPass config (BugWallet-LocalPass scheme). See
    // Config/LocalPassCreation.xcconfig.
    #if LOCAL_PASS_CREATION
    @State private var addResult: String?
    @State private var isAdding = false

    // Whether this account's pass is already in Apple Wallet. Checked with
    // PKPassLibrary.containsPass, which needs no pass-type entitlement.
    private enum WalletStatus { case checking, inWallet, notInWallet }
    @State private var walletStatus: WalletStatus = .checking
    // The signed .pkpass, built once and reused for both the check and the add.
    @State private var signedPassData: Data?
    @State private var addPassesDelegate: AddPassesDelegate?

    // Scan-a-QR-and-share flow.
    @State private var isScanning = false
    @State private var isSharing = false
    @State private var shareResult: String?
    @State private var sharePayload: SharePayload?
    // After scanning, we ask for a name to print on the pass.
    @State private var scannedUID: String?
    @State private var nameInput = ""
    @State private var isNamePromptPresented = false
    #endif

    @StateObject private var model: CardModel
    // Observed for the live-sync status line; CardModel folds the backend
    // count itself into the displayed stamps.
    @ObservedObject private var webSync: StampWebSync

    /// `webSync` and `model` are seams for tests; the app uses the shared
    /// web sync and lets the view make its own model.
    init(account: Account, webSync: StampWebSync? = nil, model: CardModel? = nil) {
        let webSync = webSync ?? .shared
        self.account = account
        self.webSync = webSync
        _model = StateObject(wrappedValue: model ?? CardModel(webSync: webSync))
    }

    private let brand = Color(red: 31/255, green: 4/255, blue: 9/255)
    private let accent = Color(red: 204/255, green: 30/255, blue: 65/255)

    var body: some View {
        ZStack {
            brand.ignoresSafeArea()
            layoutRoot
        }
        // The front camera sits in a corner of the outer display. Measured on
        // the root, which — unlike the header itself — doesn't move once the
        // header pads itself clear of it.
        .onCameraOcclusionChange { cameraInset = $0 }
        // Everything from here down hangs off the root rather than one of the
        // sections, so it survives the compact ⇄ regular switch when iPhone Duo
        // opens or closes: a scanner, alert or share sheet that's up stays up.
        #if LOCAL_PASS_CREATION
        .fullScreenCover(isPresented: $isScanning, onDismiss: {
            // Once the camera is gone, ask for the name to print on the pass.
            if scannedUID != nil { isNamePromptPresented = true }
        }) {
            QRScannerView(
                onScan: { code in
                    scannedUID = code.trimmingCharacters(in: .whitespacesAndNewlines)
                    isScanning = false
                },
                onCancel: { isScanning = false }
            )
            .ignoresSafeArea()
        }
        .alert("Name for the pass", isPresented: $isNamePromptPresented) {
            TextField("Name", text: $nameInput)
            Button("Cancel", role: .cancel) { scannedUID = nil; nameInput = "" }
            Button("Create pass") {
                if let uid = scannedUID {
                    handleScannedPass(uid: uid, name: nameInput)
                }
                scannedUID = nil; nameInput = ""
            }
        } message: {
            Text("This name will appear on the shared Wallet pass.")
        }
        .sheet(item: $sharePayload) { payload in
            ActivityView(items: [payload.url])
        }
        #endif
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

    // MARK: - Layouts

    /// iOS 27.1 splits the inner display with an arrangement view; every
    /// compact width, and every older release, uses the scrolling stack.
    @ViewBuilder
    private var layoutRoot: some View {
        #if canImport(SwiftUI, _version: 8.0.85) // iOS 27.1 SDK (Xcode 27.1)
        if #available(iOS 27.1, *), widthClass == .regular {
            arrangedLayout
        } else {
            fittingLayout
        }
        #else
        fittingLayout
        #endif
    }

    private var fittingLayout: some View {
        FittingScrollView { size in
            if widthClass == .regular {
                regularLayout(isWide: size.width > size.height)
            } else {
                compactLayout
            }
        }
    }

    #if canImport(SwiftUI, _version: 8.0.85) // iOS 27.1 SDK (Xcode 27.1)
    /// The inner display: the QR in one half, the stamps and buttons in the
    /// other. The arrangement splits at the fold itself — side by side when the
    /// device is folded like a book, stacked when it's propped on a table — so
    /// neither half lands on the crease. Each half scrolls on its own when it
    /// has to; the arrangement itself must never sit inside a scroll view.
    @available(iOS 27.1, *)
    private var arrangedLayout: some View {
        VStack(spacing: 20) {
            header
            ArrangementView {
                FittingScrollView { _ in qrSection }
            } secondary: {
                FittingScrollView { _ in controlsSection }
            }
            .arrangementViewStyle(.split)
            footer
        }
    }
    #endif

    /// iPhones and the outer display: one column, spread out by spacers.
    private var compactLayout: some View {
        VStack(spacing: 20) {
            header
            Spacer()
            qrSection
            Spacer()
            stampsSection
            Spacer()
            actionsSection
            footer
        }
    }

    /// The inner display before iOS 27.1, and iPad: the QR gets one half and
    /// the stamps and buttons the other — side by side when the space is wide,
    /// stacked when it's tall, the same rule the arrangement view applies. This
    /// one splits the safe area rather than the fold, so it sits slightly off
    /// the crease when the insets are uneven; `arrangedLayout` is exact.
    private func regularLayout(isWide: Bool) -> some View {
        let halves = isWide ? AnyLayout(HStackLayout(spacing: 0))
                            : AnyLayout(VStackLayout(spacing: 0))
        return VStack(spacing: 20) {
            header
            halves {
                qrSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                controlsSection
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            footer
        }
    }

    // MARK: - Sections

    private var header: some View {
        // Hand-placed along the top edge, where the outer display's front
        // camera sits in a corner and grows into the Dynamic Island for Live
        // Activities. `cameraInset` pads the row past it on the rare layout
        // where the safe area doesn't already.
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
                .foregroundStyle(accent)
        }
        .padding(.horizontal)
        .padding(.top)
        .padding(.top, cameraInset)
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

    // Manually tracked stamps — the live count is App Check-gated,
    // so tap + whenever the barista stamps you. The same
    // count feeds the home-screen widget through the App Group.
    private var stampsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Stamps")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Spacer()
                Text("\(model.stamps) / \(StampStore.maxStamps)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(accent)
                stepButton("minus.circle.fill", action: model.decrement)
                stepButton("plus.circle.fill", action: model.increment)
            }
            StampCardView(count: model.stamps, slotSize: 34, spacing: 8)
            // Live-sync status (App Check WebView).
            Text("Backend: \(webSync.status)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(.horizontal)
    }

    /// The stamps and buttons as one half of the regular layout, held to a
    /// readable width — a whole half of a wide display stretches the rows.
    private var controlsSection: some View {
        VStack(spacing: 20) {
            stampsSection
            actionsSection
        }
        .frame(maxWidth: 440)
    }

    private var actionsSection: some View {
        VStack(spacing: 20) {
            // Log a coffee to Apple Health as dietary caffeine.
            Menu {
                ForEach(CoffeeDrink.allCases) { drink in
                    Button("\(drink.name) · \(Int(drink.caffeineMilligrams)) mg") {
                        Task { await model.log(drink) }
                    }
                }
            } label: {
                Label(model.isLogging ? "Logging…" : "Log a coffee",
                      systemImage: "cup.and.saucer.fill")
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(accent, in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .disabled(model.isLogging)

            if let logResult = model.logResult {
                Text(logResult)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }

            // Local pass creation (Debug-LocalPass config only): the official
            // "Add to Apple Wallet" button plus a button that scans another
            // loyalty QR, signs a pass for it on-device, and shares it.
            #if LOCAL_PASS_CREATION
            HStack(spacing: 12) {
                // Add-to-Wallet builds & signs this account's pass, then hands
                // it to Wallet. Swapped for a status label once it's added.
                switch walletStatus {
                case .checking:
                    Color.clear.frame(maxWidth: .infinity, minHeight: 48)
                case .inWallet:
                    Label("In Apple Wallet", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white.opacity(0.8))
                        .frame(maxWidth: .infinity, minHeight: 48)
                case .notInWallet:
                    AddToWalletButton(action: handleAddToWallet)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .opacity(isAdding ? 0.5 : 1)
                        .disabled(isAdding)
                }

                // Scan a loyalty QR → build & sign a pass for that UID → share.
                Button { isScanning = true } label: {
                    Image(systemName: isSharing ? "hourglass" : "qrcode.viewfinder")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 48, height: 48)
                        .background(accent, in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isSharing)
                .accessibilityLabel("Scan and share a pass")
            }
            .padding(.horizontal)

            if let addResult {
                Text(addResult)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
            if let shareResult {
                Text(shareResult)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.8))
            }
            #endif
        }
    }

    private var footer: some View {
        Text("UID: \(account.uid)")
            .font(.caption2.monospaced())
            .foregroundStyle(.white.opacity(0.4))
            .textSelection(.enabled)
            .padding(.bottom)
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
    #endif

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(accent)
        }
    }

    #if LOCAL_PASS_CREATION
    private func handleAddToWallet() {
        guard !isAdding else { return }

        // Build and sign a fresh pass on-device for the logged-in account.
        isAdding = true
        addResult = nil
        Task {
            defer { isAdding = false }
            do {
                addToWallet(try await signedPass())
            } catch {
                addResult = "Couldn't build pass: \(error.localizedDescription)"
            }
        }
    }

    private func addToWallet(_ data: Data) {
        do {
            let pass = try PKPass(data: data)
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
            addResult = "Invalid pass: \(error.localizedDescription)"
        }
    }

    /// Builds and signs a pass for a *scanned* UID (someone else's loyalty QR)
    /// with the entered holder name, writes it to a temp `.pkpass`, and offers it
    /// via the share sheet.
    private func handleScannedPass(uid: String, name: String) {
        let uid = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSharing else { return }
        guard !uid.isEmpty else {
            shareResult = "That QR didn't contain a UID."
            return
        }
        isSharing = true
        shareResult = nil
        Task {
            defer { isSharing = false }
            do {
                // The scanned code is a raw UID; the name goes on the pass.
                let scanned = Account(uid: uid, email: "", idToken: "", refreshToken: "")
                let data = try await Task.detached(priority: .userInitiated) {
                    try PassBuilder.buildSignedPass(for: scanned, memberName: name)
                }.value
                let url = try writePassFile(data, uid: uid)
                sharePayload = SharePayload(url: url)
            } catch {
                shareResult = "Couldn't build pass: \(error.localizedDescription)"
            }
        }
    }

    /// Writes signed `.pkpass` data to a uniquely-named temp file to share.
    private func writePassFile(_ data: Data, uid: String) throws -> URL {
        let safe = uid.prefix(8).filter { $0.isLetter || $0.isNumber }
        let name = "BugCoffee-\(safe.isEmpty ? "pass" : String(safe)).pkpass"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        try data.write(to: url)
        return url
    }
    #endif
}
