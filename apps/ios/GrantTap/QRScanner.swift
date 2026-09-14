import SwiftUI
import AVFoundation

protocol QRScannerCameraAuthorizing {
    var videoStatus: AVAuthorizationStatus { get }
    func requestVideoAccess(_ completion: @escaping (Bool) -> Void)
}

struct SystemQRScannerCameraAuthorization: QRScannerCameraAuthorizing {
    var videoStatus: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    func requestVideoAccess(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
    }
}

/// Camera QR scanner used for one-time machine pairing.
/// The MCP `connect` tool returns the pairing QR in the agent chat; pointing the
/// phone at it is the whole setup — no terminal or copied JSON required.

struct QRScanView: View {
    let onCode: (String) -> Void
    let onCancel: () -> Void
    let cameraAuthorization: QRScannerCameraAuthorizing

    /// A viewfinder drawn over an explanation of why there is no viewfinder only
    /// confuses, so the frame and caption drop away with the camera.
    @State private var cameraUnavailable = false

    init(
        onCode: @escaping (String) -> Void,
        onCancel: @escaping () -> Void,
        cameraAuthorization: QRScannerCameraAuthorizing = SystemQRScannerCameraAuthorization()
    ) {
        self.onCode = onCode
        self.onCancel = onCancel
        self.cameraAuthorization = cameraAuthorization
    }

    var body: some View {
        ZStack {
            QRScannerRepresentable(
                onFound: onCode,
                onCameraUnavailable: { cameraUnavailable = true },
                cameraAuthorization: cameraAuthorization
            )
            .ignoresSafeArea()

            if !cameraUnavailable {
                VStack {
                    Spacer()
                    Text(L("Point the camera at the one-time GrantTap QR"))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(.black.opacity(0.55), in: Capsule())
                        .padding(.bottom, 28)
                }

                // viewfinder frame
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 240, height: 240)
                    .shadow(radius: 8)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(.black.opacity(0.5), in: Circle())
            }
            .padding(.top, 12).padding(.trailing, 16)
        }
    }
}

struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onFound: (String) -> Void
    let onCameraUnavailable: () -> Void
    let cameraAuthorization: QRScannerCameraAuthorizing

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }
    func makeUIViewController(context: Context) -> ScannerViewController {
        let vc = ScannerViewController(cameraAuthorization: cameraAuthorization)
        vc.onFound = { code in context.coordinator.deliver(code) }
        // viewDidLoad runs while SwiftUI is still building this view; hop a
        // runloop so the @State write is not made during an update.
        vc.onCameraUnavailable = { DispatchQueue.main.async(execute: onCameraUnavailable) }
        return vc
    }
    func updateUIViewController(_ vc: ScannerViewController, context: Context) {}

    final class Coordinator {
        private let onFound: (String) -> Void
        private var delivered = false
        init(onFound: @escaping (String) -> Void) { self.onFound = onFound }
        /// Fire once — a QR in view produces a stream of identical readings.
        func deliver(_ code: String) {
            guard !delivered else { return }
            delivered = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onFound(code)
        }
    }
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onFound: ((String) -> Void)?
    var onCameraUnavailable: (() -> Void)?

    /// Why the preview is not running. The two cases need different wording, and
    /// only one of them has anything to change in Settings.
    private enum Unavailable {
        case denied
        case noCamera
    }

    private let session = AVCaptureSession()
    private let cameraAuthorization: QRScannerCameraAuthorizing
    private var preview: AVCaptureVideoPreviewLayer?
    private var hasAppeared = false

    init(cameraAuthorization: QRScannerCameraAuthorizing = SystemQRScannerCameraAuthorization()) {
        self.cameraAuthorization = cameraAuthorization
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        cameraAuthorization = SystemQRScannerCameraAuthorization()
        super.init(coder: coder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestAccess()
    }

    /// Access is asked for here rather than at launch: pairing is the only place
    /// the camera is used. A refusal has to land on an explanation — returning
    /// silently leaves the user staring at a black rectangle.
    private func requestAccess() {
        switch cameraAuthorization.videoStatus {
        case .authorized:
            configure()
        case .notDetermined:
            cameraAuthorization.requestVideoAccess { [weak self] granted in
                // The callback arrives on an AVFoundation queue, not the main one.
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted { self.configure() } else { self.showUnavailable(.denied) }
                }
            }
        case .restricted:
            // Screen Time or an MDM profile blocks the camera: Settings has no
            // toggle to offer, so send them to the one-time code instead.
            showUnavailable(.noCamera)
        default:
            // .denied, .restricted, and anything Apple adds later.
            showUnavailable(.denied)
        }
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            // Simulator, or hardware the system will not hand over.
            showUnavailable(.noCamera)
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            showUnavailable(.noCamera)
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        preview = layer
        // Permission can land after the last layout pass, so size it now.
        layer.frame = view.bounds
        startSession()
    }

    /// Replaces the black preview with something a person can act on.
    private func showUnavailable(_ reason: Unavailable) {
        onCameraUnavailable?()

        let icon = UIImageView(image: UIImage(systemName: "video.slash"))
        icon.tintColor = .white
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 38)

        let title = UILabel()
        title.text = reason == .denied ? L("Camera access is off") : L("No camera available")
        title.font = .preferredFont(forTextStyle: .title3)
        title.adjustsFontForContentSizeCategory = true
        title.textColor = .white
        title.textAlignment = .center
        title.numberOfLines = 0

        let body = UILabel()
        body.text = reason == .denied
            ? L("GrantTap uses the camera only to read a computer-pairing QR code. Turn it on in Settings, or close this screen and paste the one-time pairing link instead.")
            : L("This device has no camera GrantTap can use. Close this screen and enter the one-time code shown in your agent chat instead.")
        body.font = .preferredFont(forTextStyle: .callout)
        body.adjustsFontForContentSizeCategory = true
        body.textColor = UIColor.white.withAlphaComponent(0.75)
        body.textAlignment = .center
        body.numberOfLines = 0

        // .fill, not .center: a centred label keeps its single-line intrinsic
        // width and never wraps. The text is centred by textAlignment instead.
        let stack = UIStackView(arrangedSubviews: [icon, title, body])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        stack.setCustomSpacing(20, after: icon)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // Nothing to fix in Settings when the device simply has no camera.
        if reason == .denied {
            var config = UIButton.Configuration.filled()
            config.title = L("Open Settings")
            config.baseBackgroundColor = .white
            config.baseForegroundColor = .black
            config.cornerStyle = .medium
            config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 20, bottom: 12, trailing: 20)
            let button = UIButton(configuration: config, primaryAction: UIAction { _ in
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            })
            stack.setCustomSpacing(22, after: body)
            stack.addArrangedSubview(button)
        }

        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28)
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hasAppeared = true
        startSession()
    }

    /// Called from both viewDidAppear and configure(): access can be granted after
    /// the view is already on screen, so whichever finishes last starts the session.
    private func startSession() {
        guard hasAppeared, preview != nil, !session.isRunning else { return }
        // startRunning blocks; keep it off the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              obj.type == .qr,
              let value = obj.stringValue else { return }
        onFound?(value)
    }
}
