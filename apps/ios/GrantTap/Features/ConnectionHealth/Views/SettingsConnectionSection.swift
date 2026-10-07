import SwiftUI

struct SettingsConnectionSection: View {
    @EnvironmentObject private var model: AppModel
    var onPair: () -> Void
    var onInviteController: () -> Void
    var onForgetAll: () -> Void
    var localComputer: String?

    @State private var busyRoom: String?
    @State private var unlinkRoom: String?

    init(
        onPair: @escaping () -> Void,
        onInviteController: @escaping () -> Void = {},
        onForgetAll: @escaping () -> Void,
        localComputer: String? = nil,
        busyRoom: String? = nil,
        unlinkRoom: String? = nil
    ) {
        self.onPair = onPair
        self.onInviteController = onInviteController
        self.onForgetAll = onForgetAll
        self.localComputer = localComputer
        _busyRoom = State(initialValue: busyRoom)
        _unlinkRoom = State(initialValue: unlinkRoom)
    }

    private var links: [LinkedComputer] { model.connectionRegistry.connections }
    private var hasOwnComputer: Bool { links.contains { !$0.pairing.isHub } }

    var body: some View {
        Section {
            if model.demoMode {
                demoRow
            } else if links.isEmpty {
                if let localComputer { localRow(localComputer) }
                else { emptyRow }
            } else {
                ForEach(links) { conn in
                    connectionCard(conn)
                }
            }

            Button { onPair() } label: {
                Label(L("Add a device (Scan QR)"), systemImage: "qrcode.viewfinder")
            }
            .foregroundStyle(Theme.ink)
            .disabled(model.demoMode)

            if hasOwnComputer {
                Button { onInviteController() } label: {
                    Label(L("Add another iPhone or iPad (Show QR)"), systemImage: "qrcode")
                }
                .foregroundStyle(Theme.ink)
                .disabled(model.demoMode)
            }

            if hasOwnComputer {
                Button(L("Unlink all computers"), role: .destructive, action: onForgetAll)
            }
        } header: {
            Text(L("On this device"))
        } footer: {
            Text(L("These computers can run Tasks in your Account Mesh. Each chat and Project Mesh keeps its own computer route."))
        }
        .confirmationDialog(
            L("Unlink this computer?"),
            isPresented: Binding(
                get: { unlinkRoom != nil },
                set: { if !$0 { unlinkRoom = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L("Unlink"), role: .destructive) { unlinkSelected() }
            Button(L("Cancel"), role: .cancel) { unlinkRoom = nil }
        } message: {
            Text(L("Removes keys for this computer only. Other links stay."))
        }
    }

    private var demoRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Demo"))
                .font(.system(size: 17, weight: .semibold))
            Text(L("Sample data — nothing reaches a computer."))
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
            Button(L("Exit Demo")) { model.stopDemo() }
        }
        .padding(.vertical, 4)
    }

    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "desktopcomputer")
                    .foregroundStyle(Theme.muted)
                Text(L("No devices yet"))
                    .font(.system(size: 17, weight: .semibold))
            }
            Text(GrantTapAccountAPI.session == nil
                 ? L("Sign in to your Account Mesh or scan a computer QR.")
                 : L("Your Account Mesh is ready. Chats appear when a computer joins."))
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 4)
    }

    private func localRow(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(name, systemImage: "desktopcomputer")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.ok)
            Text(L("GrantTap MCP is running on this Mac. Mesh, Tasks and process load are available here."))
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func connectionCard(_ conn: LinkedComputer) -> some View {
        let snap = model.snapshotForConnection(conn)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Circle()
                    .fill(snap.statusColor)
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conn.displayName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(snap.statusTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(snap.statusColor)
                    if conn.pairing.isHub {
                        Text(L("Controller phone link; chat access is granted separately"))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 0)
            }

            Text(snap.detail)
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            if let room = snap.roomShort {
                Text(String(format: L("Room · %@"), room))
                    .font(Theme.mono(11))
                    .foregroundStyle(Theme.muted)
            }

            // Each control needs its own hit target: inside a list row SwiftUI
            // treats plain buttons as one row action, so a tap meant for
            // Reconnect also reached Unlink.
            HStack(spacing: 12) {
                Button {
                    Task { await runConnectionAction(conn, phase: snap.phase) }
                } label: {
                    if busyRoom == conn.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(snap.phase == .needRepair ? L("Scan QR / Pair") : L("Reconnect"))
                    }
                }
                .buttonStyle(.borderless)
                .disabled(busyRoom != nil)
                .accessibilityIdentifier("connection.reconnect.\(conn.id)")

                Spacer(minLength: 0)

                Button(L("Unlink"), role: .destructive) { requestUnlink(conn) }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("connection.unlink.\(conn.id)")
            }
            .font(.system(size: 14, weight: .semibold))
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(conn.displayName). \(snap.statusTitle)")
    }

    func unlinkSelected(using target: AppModel? = nil) {
        if let id = unlinkRoom { (target ?? model).unlinkConnection(roomId: id) }
        unlinkRoom = nil
    }

    func runConnectionAction(
        _ conn: LinkedComputer, phase: ConnectionPhase, using target: AppModel? = nil
    ) async {
        let target = target ?? model
        busyRoom = conn.id
        if phase == .needRepair {
            onPair()
        } else {
            await target.reconnectConnection(roomId: conn.id)
        }
        busyRoom = nil
    }

    func requestUnlink(_ conn: LinkedComputer) { unlinkRoom = conn.id }
}
