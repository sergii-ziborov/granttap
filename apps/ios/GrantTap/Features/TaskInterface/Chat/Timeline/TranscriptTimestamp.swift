import SwiftUI

/// Provider timestamps are milliseconds since Unix epoch, shown in the device’s local time.
struct TranscriptTimestamp: View {
    let entry: ActivityEntry

    var body: some View {
        if entry.createdAt > 0 && entry.createdAt.isFinite {
            Text(Date(timeIntervalSince1970: entry.createdAt / 1000),
                 format: .dateTime.day().month().year().hour().minute())
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(Theme.muted)
                .accessibilityIdentifier("chat.time.\(entry.id)")
        }
    }
}
