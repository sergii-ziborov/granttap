import SwiftUI

struct ProjectCapabilityDetailView: View {
    let info: ProjectCapabilityInfo
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @ObservedObject private var usage = CapabilityUsageStore.shared
    @ObservedObject private var recorded = CapabilityExecutionUsageStore.shared

    private var events: [CapabilityUsageEvent] {
        ProjectCapabilityUsage.events(usage.events,
            snapshot: model.meshSnapshots[snapshot.projectId] ?? snapshot,
            rooms: model.projectUsageRooms, kind: info.kind, name: info.name,
            endpointId: info.endpointId, provider: info.provider)
    }

    private var evidence: ProjectRecordedUsage? {
        ProjectCapabilityUsage.recorded(recorded.byRoom,
            snapshot: model.meshSnapshots[snapshot.projectId] ?? snapshot,
            rooms: model.projectUsageRooms, info: info)
    }

    var body: some View {
        List {
            Section(L("Details")) {
                CompatLabeledContent(L("Name"), value: info.name)
                if let provider = info.provider {
                    CompatLabeledContent(L("Agent"), value: AgentIdentity.displayName(provider))
                }
                if let endpoint = info.endpointId {
                    CompatLabeledContent(L("Computer"), value: ProjectHealthDiagnostics.computerName(
                        endpoint, connections: model.connectionRegistry.connections))
                }
                ForEach(info.fields) { field in
                    CompatLabeledContent(field.title, value: field.value)
                }
            }
            if let description = info.description, !description.isEmpty {
                Section(L("Description")) { Text(description).textSelection(.enabled) }
            }
            observedSection
            Section(L("Call history")) {
                if events.isEmpty, evidence != nil {
                    Text(L("The computer reported recorded use. Recent call details are not in this snapshot."))
                        .foregroundStyle(Theme.muted)
                }
                ForEach(events.sorted { $0.createdAt > $1.createdAt }.prefix(20)) { event in
                    UsageCallLink(event: event)
                }
                if events.count > 20 {
                    NavigationLink(L("Show all observed calls")) {
                        ProjectUsageEventsView(events: events, title: info.title)
                    }
                }
            }
        }
        .pageNavigationTitle(info.title) {
            ProjectCapabilityPolicyMenu(info: info,
                snapshot: model.meshSnapshots[snapshot.projectId] ?? snapshot, model: model)
        }
    }

    private var observedSection: some View {
        Section {
            let summary = UsageSummaries(events: events, totals: []).rows.first
            if summary != nil || evidence != nil {
                CompatLabeledContent(L("Calls"), value: "\(max(summary?.count ?? 0, evidence?.count ?? 0))")
                CompatLabeledContent(L("Failed"), value: "\(max(summary?.failures ?? 0, evidence?.failures ?? 0))")
                let unknown = events.filter { $0.effectiveOutcome == .unknown }.count
                if unknown > 0 { CompatLabeledContent(L("Outcome not reported"), value: "\(unknown)") }
                CompatLabeledContent(L("Average duration"), value: (evidence?.averageDurationMs ?? summary?.averageDurationMs).map {
                    CapabilityResourceFormat.duration($0)
                } ?? L("Not reported"))
                CompatLabeledContent(L("CPU time"), value: summary?.cpuTimeMs.map {
                    CapabilityResourceFormat.duration($0)
                } ?? L("Not reported"))
                CompatLabeledContent(L("Peak memory"), value: summary?.peakMemoryBytes.map {
                    CapabilityResourceFormat.bytes($0)
                } ?? L("Not reported"))
                HStack {
                    Text(L("Last used"))
                    Spacer()
                    Text(Date(timeIntervalSince1970: max(summary?.lastUsedAt ?? 0, evidence?.lastUsedAt ?? 0) / 1_000), style: .relative)
                        .foregroundStyle(Theme.muted)
                }
            } else {
                Text(L("No observed calls for this capability in this Mesh."))
                    .foregroundStyle(Theme.muted)
            }
        } header: {
            Text(L("Observed usage"))
        } footer: {
            Text(L("Calls are matched to this Mesh's computers and executions. This device keeps a bounded history; installation does not prove use."))
        }
    }
}

struct ProjectCapabilityRow: View {
    let info: ProjectCapabilityInfo
    let snapshot: ProjectMeshSnapshot
    @ObservedObject var model: AppModel
    @ObservedObject private var usage = CapabilityUsageStore.shared
    @ObservedObject private var recorded = CapabilityExecutionUsageStore.shared

    var body: some View {
        let events = ProjectCapabilityUsage.events(usage.events, snapshot: snapshot,
            rooms: model.projectUsageRooms, kind: info.kind, name: info.name,
            endpointId: info.endpointId, provider: info.provider)
        let evidence = ProjectCapabilityUsage.recorded(recorded.byRoom, snapshot: snapshot,
            rooms: model.projectUsageRooms, info: info)
        NavigationLink {
            ProjectCapabilityDetailView(info: info, snapshot: snapshot, model: model)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(info.title)
                if let description = info.description {
                    Text(description).font(.caption).foregroundStyle(Theme.muted).lineLimit(2)
                }
                if let provider = info.provider {
                    Text(AgentIdentity.displayName(provider)).font(.caption).foregroundStyle(Theme.muted)
                }
                if let last = ([events.map(\.createdAt).max(), evidence?.lastUsedAt].compactMap { $0 }).max() {
                    HStack(spacing: 6) {
                        Text(String(format: L("%d observed calls"), max(events.count, evidence?.count ?? 0)))
                        Text("·")
                        Text(Date(timeIntervalSince1970: last / 1_000), style: .relative)
                    }.font(.caption).foregroundStyle(Theme.muted)
                } else {
                    Text(L("No recorded calls in this snapshot")).font(.caption).foregroundStyle(Theme.muted)
                }
            }
        }
        .accessibilityIdentifier("project.capability.\(info.kind.rawValue).\(info.name)")
    }
}
