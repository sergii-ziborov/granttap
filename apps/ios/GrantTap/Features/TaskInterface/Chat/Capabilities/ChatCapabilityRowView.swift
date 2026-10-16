import SwiftUI

struct ChatCapabilityRowView: View {
    let row: ChatCapabilityRow
    let accent: Color
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Image(systemName: row.kind.systemImage).foregroundStyle(Theme.muted)
                Text(row.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Spacer()
                if row.needsAuth {
                    Text(L("sign in")).font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.riskMed)
                } else if row.isControllable {
                    HStack(spacing: 6) {
                        Text(row.controlLabel ?? "")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                        Toggle("", isOn: Binding(
                            get: { row.allowed != false }, set: { _ in onToggle() }
                        ))
                        .labelsHidden()
                        .tint(Theme.ok)
                        .accessibilityValue(row.controlLabel ?? "")
                    }
                } else {
                    Text(L("Observed only")).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
            Text(row.usage ?? L("Not observed in this task"))
                .font(.system(size: 11)).foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 2)
    }
}
