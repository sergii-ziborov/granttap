import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct PairingSheet: View {
    typealias SecurePairingFetcher = (Pairing.SecureLink) async
        -> Result<Pairing, PairingError>

    let purpose: PairingPurpose

    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var json = ""
    @State private var error: String?
    @State private var scanning = false
    @State private var showingAccount = false
    @State private var secureToken = ""
    private let relayBase = Pairing.currentRelayHTTP
    @State private var busy = false
    private let cameraAuthorization: QRScannerCameraAuthorizing
    private let modelOverride: AppModel?
    private let securePairingFetcher: SecurePairingFetcher
    private let pairingConsumer: ((Pairing) -> Bool)?
    private let onPaired: (() -> Void)?

    init(
        purpose: PairingPurpose = .computer,
        json: String = "", error: String? = nil, scanning: Bool = false,
        secureToken: String = "", busy: Bool = false,
        cameraAuthorization: QRScannerCameraAuthorizing = SystemQRScannerCameraAuthorization(),
        modelOverride: AppModel? = nil,
        securePairingFetcher: @escaping SecurePairingFetcher = { link in
            await Pairing.fetchSecurePairing(
                relayBase: link.relayBase, mailboxId: link.mailboxId,
                transferKey: link.transferKey
            )
        },
        pairingConsumer: ((Pairing) -> Bool)? = nil,
        onPaired: (() -> Void)? = nil
    ) {
        self.purpose = purpose
        _json = State(initialValue: json)
        _error = State(initialValue: error)
        _scanning = State(initialValue: scanning)
        _secureToken = State(initialValue: secureToken)
        _busy = State(initialValue: busy)
        self.cameraAuthorization = cameraAuthorization
        self.modelOverride = modelOverride
        self.securePairingFetcher = securePairingFetcher
        self.pairingConsumer = pairingConsumer
        self.onPaired = onPaired
    }

    var body: some View {
        CompatNavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        scanCard
                        codeCard
                        manualCard
                        if let error {
                            Text(error)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.riskHigh)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle(purpose.title)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $scanning) {
                QRScanView(
                    onCode: { scanned in
                        scanning = false
                        // Fetch may still fail (single-use mailbox) — keep sheet + show error.
                        apply(scanned)
                    },
                    onCancel: { scanning = false },
                    cameraAuthorization: cameraAuthorization
                )
            }
            .sheet(isPresented: $showingAccount) {
                AccountConnectionView { pairing in
                    guard consume(pairing) else { return false }
                    finishPairing()
                    return true
                }
            }
            .overlay {
                if busy {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        VStack(spacing: 10) {
                            ProgressView()
                            Text(L("Connecting…"))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.ink)
                        }
                        .padding(20)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
    }

    private var scanCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: L("Fastest method"))
            Button {
                error = nil
                scanning = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "qrcode.viewfinder")
                    Text(L("Scan QR"))
                }
            }
            .buttonStyle(FilledButton(tint: Theme.claude))
            .disabled(busy)

            if purpose == .computer {
                Button(L("Connect with passkey")) { showingAccount = true }
                    .buttonStyle(OutlineButton())
                    .disabled(busy)
            }

            Text(purpose.scanExplanation)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
        }
        .card()
    }

    private var codeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow(text: "Secure token")
            Text(L("Use this high-entropy fallback when the camera is unavailable, including Simulator."))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)

            TextField(L("Paste mailbox.key token"), text: $secureToken)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(Theme.mono(12, .semibold))
                .foregroundStyle(Theme.ink)
                .padding(12)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))

            Button {
                connectByToken()
            } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white) }
                    Text(busy ? L("Connecting…") : L("Connect securely"))
                }
            }
            .buttonStyle(FilledButton(tint: Theme.ink, textColor: Theme.bg))
            .disabled(busy || Pairing.secureLink(relayBase: relayBase, manualToken: secureToken) == nil)
            .opacity(Pairing.secureLink(relayBase: relayBase, manualToken: secureToken) == nil ? 0.5 : 1)

            Text(L("The mailbox is single-use and expires after 15 minutes. Its 256-bit key never reaches the relay."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        }
        .card()
    }

    private var manualCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Paste manually")
            TextEditor(text: $json)
                .frame(minHeight: 80)
                .font(Theme.mono(11))
                .padding(8)
                .background(Theme.bg, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))

            Button(L("Connect from text")) { apply(json) }
                .buttonStyle(OutlineButton())
                .disabled(json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Text(purpose == .joinProject
                 ? L("Paste the Mesh invite from its owner. Computer and controller codes belong in Settings → Connections.")
                 : L("Paste a granttap://controllers link from another trusted phone, a granttap://pair-v2 computer link, or phone.pairing.json."))
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        }
        .card()
    }

    func connect(_ link: Pairing.SecureLink) {
        busy = true
        error = nil
        Task {
            let result = await securePairingFetcher(link)
            await MainActor.run {
                busy = false
                switch result {
                case .success(let pairing):
                    // Keys must be complete before we claim Linked — camera beep ≠ connected.
                    guard Pairing.isValid(pairing) else {
                        error = L("Pairing keys were incomplete. Ask the agent for a fresh QR — other links were not changed.")
                        return
                    }
                    guard purpose.accepts(pairing) else {
                        error = purpose.rejectionMessage(for: pairing)
                        return
                    }
                    guard consume(pairing) else {
                        error = AppModel.pairingStorageFailureMessage
                        return
                    }
                    finishPairing()
                case .failure(let err):
                    // Keep the sheet open with an honest error (common: mailbox already used).
                    error = err.message
                }
            }
        }
    }

    func connectByToken() {
        guard let link = Pairing.secureLink(relayBase: relayBase, manualToken: secureToken) else {
            error = L("This secure token is incomplete or invalid.")
            return
        }
        connect(link)
    }

    /// Accepts a pairing QR/deep-link or pasted pairing file.
    func apply(_ text: String) {
        error = nil
        if purpose == .computer, let bundle = ControllerNetworkTransfer.bundleLink(from: text) {
            connectControllerNetwork(bundle)
        } else if let link = Pairing.secureLink(fromURI: text) {
            // Stay on sheet with Connecting… — do not treat QR decode as success.
            connect(link)
        } else if let p = Pairing.fromURI(text) ?? Pairing.fromJSON(text) {
            guard Pairing.isValid(p) else {
                error = L("Pairing keys were incomplete. Ask the agent for a fresh QR — other links were not changed.")
                return
            }
            guard purpose.accepts(p) else {
                error = purpose.rejectionMessage(for: p)
                return
            }
            guard consume(p) else {
                error = AppModel.pairingStorageFailureMessage
                return
            }
            finishPairing()
        } else {
            error = L("This does not look like a GrantTap pairing. Ask the agent to connect GrantTap and scan the QR shown in the chat.")
        }
    }

    private func connectControllerNetwork(_ link: Pairing.SecureLink) {
        busy = true
        Task {
            do {
                let pairings = try await ControllerNetworkTransfer.fetch(link)
                await MainActor.run {
                    busy = false
                    guard (modelOverride ?? model).addControllerConnections(pairings) else {
                        error = AppModel.pairingStorageFailureMessage
                        return
                    }
                    finishPairing()
                }
            } catch {
                await MainActor.run {
                    busy = false
                    self.error = L("The controller code expired or one computer could not be linked. Create a fresh QR on the trusted phone.")
                }
            }
        }
    }

    private func consume(_ pairing: Pairing) -> Bool {
        pairingConsumer?(pairing) ?? (modelOverride ?? model).setPairing(pairing)
    }

    private func finishPairing() {
        if let onPaired { onPaired() } else { dismiss() }
    }
}

// MARK: - settings and trust links
