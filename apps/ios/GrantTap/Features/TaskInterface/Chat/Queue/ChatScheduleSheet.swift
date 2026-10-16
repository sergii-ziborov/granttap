import SwiftUI

struct ChatScheduleSheet: View {
    let onClose: () -> Void
    let onSchedule: (Date) -> Bool
    @State private var date = Date().addingTimeInterval(3_600)
    @State private var error = false

    var body: some View {
        ChatSheetNavigation(title: L("Schedule message"), doneIdentifier: "chat.schedule.done", onClose: onClose) {
            VStack(alignment: .leading, spacing: 24) {
                Label(L("Run later"), systemImage: "clock.arrow.circlepath")
                    .font(.title2.weight(.semibold)).foregroundStyle(Theme.ink)
                DatePicker(L("Start after"), selection: $date,
                    in: Date()...Date().addingTimeInterval(29 * 86_400), displayedComponents: [.date, .hourAndMinute])
                    .accessibilityIdentifier("chat.schedule.date")
                Text(L("Runs when the computer is available, even if this phone is offline."))
                    .font(.subheadline).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if error {
                    Text(L("The message could not be queued. Your draft has been kept."))
                        .font(.caption).foregroundStyle(Theme.riskHigh)
                }
                Button {
                    if onSchedule(date) { onClose() } else { error = true }
                } label: {
                    Label(L("Schedule"), systemImage: "clock.badge.checkmark")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("chat.schedule.confirm")
                Spacer(minLength: 0)
            }
            .padding(24)
            .background(Theme.bg)
        }
        #if targetEnvironment(macCatalyst)
        .frame(width: 460, height: 370)
        #endif
    }
}
