// Camera QR scanning + share sheet for the "scan a loyalty QR, build a signed
// pass for it, and share it" flow. This is local pass creation, so the whole
// file is compiled only into the Debug-LocalPass config (BugWallet-LocalPass
// scheme). See Config/LocalPassCreation.xcconfig.
#if LOCAL_PASS_CREATION
import SwiftUI
import AVFoundation

/// A file to hand to the iOS share sheet. `Identifiable` so it can drive a
/// `.sheet(item:)`.
struct SharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

/// Wraps `UIActivityViewController` so a built `.pkpass` file can be shared
/// (AirDrop, Messages, Save to Files, …). The recipient taps it to add the pass.
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Full-screen camera QR scanner. Reports the first decoded string via `onScan`,
/// or `onCancel` if the user backs out / the camera is unavailable.
struct QRScannerView: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onScan = onScan
        controller.onCancel = onCancel
        return controller
    }
    func updateUIViewController(_ controller: QRScannerController, context: Context) {}
}

/// Sets up an `AVCaptureSession` for QR metadata, shows a live preview, and
/// fires `onScan` once. Handles the camera-permission prompt and the no-camera
/// case (e.g. Simulator) by surfacing a message instead of a black screen.
final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.zerogravityroom.bugwallet.scanner")
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var didScan = false
    // Keeps the preview upright (iOS 17+). An AVCaptureDevice.RotationCoordinator,
    // typed as NSObject because a stored property can't be iOS 17-only.
    private var rotationCoordinator: NSObject?
    private var rotationObservation: NSKeyValueObservation?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        addCloseButton()
        addHint()

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.configureAndStart() : self?.showMessage("Camera access denied.")
                }
            }
        default:
            showMessage("Camera access denied. Enable it in Settings to scan.")
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
        // TODO(iPhone Duo, iOS 27.1 SDK): the close button and hint are placed by
        // hand. The safe area should keep them clear of the outer display's
        // corner camera, but once `reservedRegions(kind:)` ships (it's not in the
        // iOS 27.0 SDK), check against the camera itself and, on the inner
        // display, the fold:
        //
        //     let camera = view.reservedRegions(kind: .occlusion).map(\.frame)
        //     let fold = view.reservedRegions(kind: .division).map(\.frame)
        //     // …then move the close button and hint off anything in camera + fold.
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func configureAndStart() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            showMessage("No camera available on this device.")
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            showMessage("Couldn't start the scanner.")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.layer.bounds
        view.layer.insertSublayer(preview, at: 0)
        previewLayer = preview
        if #available(iOS 17, *) {
            keepUpright(preview, for: device)
        }

        // startRunning blocks; keep it off the main thread.
        sessionQueue.async { [session] in session.startRunning() }
    }

    /// The app is portrait-only, but iPhone Duo's inner display ignores that
    /// and can show the scanner in landscape. The rotation coordinator reports
    /// the angle that keeps the preview level with the horizon — and follows
    /// the app between the two displays — so apply each new angle.
    @available(iOS 17, *)
    private func keepUpright(_ preview: AVCaptureVideoPreviewLayer, for device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: preview)
        rotationCoordinator = coordinator
        rotationObservation = coordinator.observe(
            \.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]
        ) { [weak preview] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            DispatchQueue.main.async {
                guard let connection = preview?.connection,
                      connection.isVideoRotationAngleSupported(angle) else { return }
                connection.videoRotationAngle = angle
            }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !didScan,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue, !value.isEmpty else { return }
        didScan = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        onScan?(value)
    }

    // MARK: - Chrome
    // Every edge is pinned to the safe area on its own: iPhone Duo's insets are
    // often uneven (a side camera, a vertical bar, Split View).

    private func addCloseButton() {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        button.tintColor = .white
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            button.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36)
        ])
    }

    private func addHint() {
        let label = UILabel()
        label.text = "Scan a Bug Coffee loyalty QR"
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            label.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -32)
        ])
    }

    private func showMessage(_ text: String) {
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .body)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -32)
        ])
    }
}
#endif
