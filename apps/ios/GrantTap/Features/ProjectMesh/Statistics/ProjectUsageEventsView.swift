import SwiftUI

/// A bounded, already scoped view of observed invocations. Project statistics
/// must retain the authenticated room and provider filters in drilldowns.
struct ProjectUsageEventsView: View {
    let events: [CapabilityUsageEvent]
    let title: String

    var body: some View {
        List {
            if let totals = ProjectUsageStats.totals(events) {
                Section(L("Observed usage")) {
                    CompatLabeledContent(L("Calls"), value: "\(totals.calls)")
                    if totals.failures > 0 {
                        CompatLabeledContent(L("Failed"), value: "\(totals.failures)")
                    }
                    CompatLabeledContent(L("CPU time"), value: totals.cpuTimeMs.map {
                        CapabilityResourceFormat.duration($0)
                    } ?? L("Not reported"))
                    CompatLabeledContent(L("Peak memory"), value: totals.peakMemoryBytes.map {
                        CapabilityResourceFormat.bytes($0)
                    } ?? L("Not reported"))
                }
            }
            Section(L("Call history")) {
                if events.isEmpty {
                    Text(L("No invocations were attributed to this execution."))
                        .foregroundStyle(Theme.muted)
                }
                ForEach(events.sorted { $0.createdAt > $1.createdAt }.prefix(60)) { event in
                    UsageCallLink(event: event)
                }
            }
        }
        .pageNavigationTitle(title)
    }
}
