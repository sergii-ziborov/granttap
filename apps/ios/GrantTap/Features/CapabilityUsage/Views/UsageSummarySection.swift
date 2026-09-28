import SwiftUI

struct UsageSummarySection: View {
    let summary: OperationalToolSummary

    var body: some View {
        Section {
            CompatLabeledContent(L("Calls"), value: "\(summary.count)")
            CompatLabeledContent(L("Failed"), value: "\(summary.failures)")
            CompatLabeledContent(L("Average duration"), value: summary.averageDurationMs.map {
                CapabilityResourceFormat.duration($0)
            } ?? L("Not reported"))
            CompatLabeledContent(L("CPU time"), value: summary.cpuTimeMs.map {
                CapabilityResourceFormat.duration($0)
            } ?? L("Not reported"))
            CompatLabeledContent(L("Peak memory"), value: summary.peakMemoryBytes.map {
                CapabilityResourceFormat.bytes($0)
            } ?? L("Not reported"))
            HStack {
                Text(L("Last used"))
                Spacer()
                Text(Date(timeIntervalSince1970: summary.lastUsedAt / 1_000), style: .relative)
                    .foregroundStyle(Theme.muted)
            }
        } header: {
            Text(L("Observed usage"))
        } footer: {
            Text(L("Counts cover the selected period. Duration and resources use retained observations."))
        }
    }
}
