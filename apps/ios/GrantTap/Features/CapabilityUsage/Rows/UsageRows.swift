import SwiftUI

/// One tool, as every usage list shows it.
///
/// Three screens listed tools with their own copies of this row. One copy
/// means one place where a count reads the same everywhere.
struct UsageToolRow: View {
    let summary: OperationalToolSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(summary.name).lineLimit(1)
                Spacer(minLength: 8)
                Text(String(format: L("%d×"), summary.count))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if let detail = summary.resourceDetail {
                Text(detail).font(.caption).foregroundStyle(Theme.muted)
            }
            if summary.failures > 0 {
                Text(String(format: L("%d failed"), summary.failures))
                    .font(.caption).foregroundStyle(Theme.riskHigh)
            }
        }
        .padding(.vertical, 2)
    }
}

/// One call, leading to the chat at the moment it happened.
///
/// A call that cannot be opened tells you it happened and nothing else. When
/// its chat is known the row is a link, and the chat scrolls to the entry the
/// call came from; a call recorded without a chat stays a plain row.
struct UsageCallLink: View {
    let event: CapabilityUsageEvent
    @ObservedObject private var model: AppModel

    /// Takes the model rather than reading it from the environment: the task
    /// history is rendered from places that do not inject one, and a row that
    /// asserts on its environment takes the whole screen down with it.
    init(event: CapabilityUsageEvent, model: AppModel? = nil) {
        self.event = event
        self.model = model ?? .shared
    }

    var body: some View {
        if let target = CapabilityChatLink.target(for: event, model: model) {
            NavigationLink {
                CapabilityChatDestination(
                    target: target, createdAt: event.createdAt,
                    focusEntryId: CapabilityTranscriptLink.entryId(
                        sourceId: event.sourceId, roomId: target.roomId
                    )
                )
                .environmentObject(model)
            } label: {
                row
            }
        } else {
            row
        }
    }

    private var row: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(event.name).lineLimit(1)
                Spacer(minLength: 8)
                Text(Date(timeIntervalSince1970: event.createdAt / 1000)
                    .formatted(date: .omitted, time: .shortened))
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            if let preview = event.commandPreview {
                Text(preview).font(Theme.mono(11))
                    .foregroundStyle(Theme.muted).lineLimit(2)
            }
            if event.effectiveOutcome == .error {
                Text(L("Failed")).font(.caption).foregroundStyle(Theme.riskHigh)
            }
        }
        .padding(.vertical, 2)
    }
}
