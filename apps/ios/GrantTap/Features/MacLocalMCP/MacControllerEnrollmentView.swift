#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

struct MacControllerEnrollmentView: View {
    @EnvironmentObject private var reader: MacLocalMCPModel
    @StateObject private var enrollment = ControllerEnrollment()

    var body: some View {
        List {
            Section {
                Text(L("On your iPhone or iPad, open GrantTap → Settings → Connections → Add a device (Scan QR)."))
                if enrollment.code?.status == .connected {
                    Label(L("Device connected"), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.ok)
                        .accessibilityIdentifier("settings.controller-connected")
                } else if let code = enrollment.code, code.status == .pending,
                          let uri = code.uri, let expiry = code.expires_at {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if context.date.timeIntervalSince1970 * 1_000 < expiry {
                            VStack(spacing: 12) {
                                QRCodeImage(text: uri, size: 260)
                                Text(code.computer).font(.headline)
                                Text(L("Expires") + " " + Date(timeIntervalSince1970: expiry / 1_000)
                                    .formatted(date: .omitted, time: .shortened))
                                    .foregroundStyle(Theme.muted)
                                Button(L("Copy connection link")) { UIPasteboard.general.string = uri }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .accessibilityIdentifier("settings.controller-code")
                        } else { Text(L("This connection code expired. Generate a new one.")) }
                    }
                } else if enrollment.code?.status == .expired {
                    Text(L("This connection code expired. Generate a new one."))
                }
                if enrollment.busy { ProgressView(L("Preparing connection…")) }
                if enrollment.failed {
                    Text(L("Could not create a connection code. Check the local MCP and network, then retry."))
                        .foregroundStyle(Theme.riskHigh)
                }
                if enrollment.code?.status != .pending {
                    Button(L("Show connection QR")) { Task { await enrollment.create(read: read) } }
                        .disabled(enrollment.busy)
                        .accessibilityIdentifier("settings.create-controller-code")
                }
            } footer: {
                Text(L("Each device gets its own connection. Existing devices stay connected."))
            }
        }
        .pageNavigationTitle(L("Connect iPhone or iPad"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await enrollment.create(read: read)
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 3_000_000_000) } catch { break }
                if enrollment.code?.status == .pending { await enrollment.refresh(read: read) }
            }
        }
        .onDisappear { enrollment.clear() }
    }

    private func read(_ action: String) async throws -> Data {
        guard let socket = reader.status?.desktopEngineSocket else { throw MacLocalMCPError.unavailable }
        return try await MacLocalMCPClient.read(socketPath: socket,
            operation: "desktop.controller_enrollment",
            input: action == "create" ? ["action": action, "confirmed": "true"] : ["action": action])
    }
}
#endif
