import SwiftUI

/// Settings → Security. Kept out of ContentView to avoid merge thrash with
/// Connection / background-delivery agents.
@MainActor
struct SettingsSecuritySection: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var security: SecurityGate
    @ObservedObject var audit: AuditStore
    @AppStorage(NotificationPrivacy.hideDetailsKey) private var hideNotificationDetails = false

    init(security: SecurityGate? = nil, audit: AuditStore? = nil) {
        self.security = security ?? .shared
        self.audit = audit ?? .shared
    }

    var body: some View {
        Section {
            Toggle(isOn: Binding(
                get: { security.enabled },
                set: { desired in
                    // Face ID / PIN chrome sits under this sheet — dismiss first
                    // so evaluatePolicy and pinSetup are actually reachable.
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        security.setEnabled(desired)
                    }
                }
            )) {
                Label(String(format: L("App lock · %@"), security.biometryName),
                      systemImage: "faceid")
            }
            .tint(Theme.claude)
            .disabled(security.authenticating)

            if security.enabled {
                Button {
                    dismiss()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        security.beginChangePin()
                    }
                } label: {
                    Label(L("Change GrantTap PIN"), systemImage: "number")
                }
                .disabled(security.authenticating)
            }

            if let error = security.errorText {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Theme.riskHigh)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Picker(L("Lock after leaving"), selection: Binding(
                get: { security.lockDelay },
                set: { security.setLockDelay($0) }
            )) {
                Text(L("Immediately")).tag(TimeInterval(0))
                Text(L("30 seconds")).tag(TimeInterval(30))
                Text(L("1 minute")).tag(TimeInterval(60))
            }
            .disabled(!security.enabled)

            Toggle(isOn: $hideNotificationDetails) {
                Label(L("Hide task details in notifications"), systemImage: "eye.slash")
            }
            .tint(Theme.claude)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(L("Authenticate approval actions"))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Label(L("Always"), systemImage: "checkmark.shield.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ok)
                    .fixedSize()
            }
            .accessibilityElement(children: .combine)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(L("Independent per-task encryption"))
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                Label(L("Always on"), systemImage: "lock.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ok)
                    .fixedSize()
            }
            .accessibilityElement(children: .combine)

            NavigationLink {
                AuditLogView()
            } label: {
                HStack {
                    Label(L("Log"), systemImage: "list.bullet.clipboard")
                    Spacer()
                    Text("\(audit.events.count)")
                        .foregroundStyle(Theme.muted)
                }
            }
        } header: {
            Text(L("Notifications & Privacy"))
        } footer: {
            Text(L("App lock, notification visibility, relock timing and the local audit stay on this device."))
        }
    }
}

/// Shared with Settings Security (was private inside ContentView).
@MainActor
struct AuditLogView: View {
    @ObservedObject var audit: AuditStore
    @State private var search = ""
    @State var filter: AuditLogFilter = .all
    @State private var confirmClear = false

    init(audit: AuditStore? = nil, filter: AuditLogFilter = .all) {
        self.audit = audit ?? .shared
        _filter = State(initialValue: filter)
    }

    var filtered: [AuditEvent] {
        filter.apply(audit.events, search: search)
    }

    var body: some View {
        List {
            Picker(L("Log"), selection: $filter) {
                ForEach(AuditLogFilter.allCases, id: \.self) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            if filtered.isEmpty {
                CompatEmptyState(title: "No audit events",
                                 systemImage: "list.bullet.clipboard")
            } else {
                ForEach(filtered) { event in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(event.action.uppercased())
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(event.outcome == "failed" ? Theme.riskHigh : Theme.claude)
                            Spacer()
                            Text(Self.formatDate(event.createdAt))
                                .font(.system(size: 10.5))
                                .foregroundStyle(Theme.muted)
                        }
                        Text(event.detail)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .background(Theme.bg)
        .navigationTitle(L("Log"))
        .searchable(text: $search, prompt: L("Search audit log"))
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(L("Clear"), role: .destructive) { confirmClear = true }
                    .disabled(audit.events.isEmpty)
            }
        }
        .confirmationDialog(
            L("Clear the local audit log?"),
            isPresented: $confirmClear,
            titleVisibility: .visible
        ) {
            Button(L("Clear log"), role: .destructive) { audit.clear() }
            Button(L("Cancel"), role: .cancel) {}
        }
    }

    static func formatDate(_ milliseconds: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1000))
    }
}
