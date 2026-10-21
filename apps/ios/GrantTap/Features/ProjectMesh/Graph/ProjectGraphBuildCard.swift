import SwiftUI

/// The same request state appears in Graph and Health, with one progress indicator.
struct ProjectGraphBuildCard: View {
    let request: ProjectGraphRequest?
    let reports: [ProjectRepositoryGraph]
    let needsAnalysis: Bool
    var actionIdentifier = "project.graph.analyze"
    var compact = false
    let rebuild: () -> Void
    @State private var showInformation = false

    private var pending: Bool { request?.pending == true }
    private var received: [ProjectRepositoryGraph] {
        reports.filter { $0.analysisStatus == "COMPLETE" || $0.analysisStatus == "INCOMPLETE" }
    }
    private var needsAttention: Bool {
        request?.result == .failed || request?.result == .noRoute || request?.result == .partial
    }
    private var needsDetail: Bool {
        !compact || pending || received.isEmpty || needsAnalysis
            || request?.result == .failed || request?.result == .noRoute
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if needsDetail { HStack(alignment: .center, spacing: 10) {
                if pending {
                    ProgressView().tint(Theme.ink)
                        .accessibilityLabel(L("Waiting for computer reports"))
                        .accessibilityIdentifier("project.graph.progress")
                } else {
                    Image(systemName: needsAttention && received.isEmpty ? "exclamationmark.circle" : "point.3.connected.trianglepath.dotted")
                        .foregroundStyle(needsAttention && received.isEmpty ? Theme.riskMed : Theme.muted)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Text(detail).font(.caption).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                informationButton
            } }
            HStack(alignment: .center, spacing: 12) {
                if compact && !needsDetail { informationButton }
                if !compact && !received.isEmpty {
                    Text(reportSummary).font(.caption).foregroundStyle(Theme.muted)
                        .accessibilityIdentifier("project.graph.saved-report")
                }
                Spacer(minLength: 0)
                if !pending {
                    Button(action: rebuild) { Label(received.isEmpty ? actionTitle : L("Refresh"), systemImage: "arrow.clockwise").font(.caption.weight(.semibold)) }
                        .buttonStyle(.bordered).accessibilityLabel(actionTitle).accessibilityIdentifier(actionIdentifier)
                }
            }
        }
        .padding(compact ? 0 : 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface.opacity(compact ? 0 : 1), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line.opacity(compact ? 0 : 1), lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.graph.status")
        .sheet(isPresented: $showInformation) { ProjectGraphBuildInformation() }
    }

    private var informationButton: some View {
        Button { showInformation = true } label: { Image(systemName: "info.circle").frame(width: 44, height: 44) }
            .buttonStyle(.plain).foregroundStyle(Theme.muted)
            .accessibilityLabel(L("How architecture updates"))
            .accessibilityIdentifier("project.graph.build-info")
    }

    private var title: String {
        if pending { return L(received.isEmpty ? "Building architecture…" : "Refreshing architecture…") }
        switch request?.result {
        case .failed: return L("Architecture could not refresh")
        case .noRoute: return L("Computer connection needed")
        case .partial: return L(received.isEmpty ? "Architecture needs attention" : "Reports available")
        default:
            if received.isEmpty { return L("Architecture is not built yet") }
            return L(needsAnalysis ? "Architecture needs refresh" : "Repository architecture")
        }
    }

    private var detail: String {
        if pending, request?.result == .requested {
            return L("Analysis requested from this Mesh's computers.")
        }
        if request?.result == .partial && !received.isEmpty {
            return L("Available reports can be explored. Repository rows show what still needs attention.")
        }
        if pending || needsAttention, let request { return request.result.message }
        if received.isEmpty {
            return L("Build a report to explore components, dependencies and code towers in this Mesh.")
        }
        if needsAnalysis {
            return L("A repository changed or is missing analysis. Refresh to inspect its current architecture.")
        }
        return L("Explore the reports received from this Mesh's computers.")
    }

    private var actionTitle: String {
        if needsAttention && received.isEmpty { return L("Retry architecture build") }
        return L(received.isEmpty ? "Build architecture now" : "Refresh architecture")
    }

    private var reportSummary: String {
        let counts = LPlural(received.count, one: "%d report", many: "%d reports")
        if pending || needsAttention || needsAnalysis { return L("Last received report") + " · " + counts }
        return counts
    }
}

private struct ProjectGraphBuildInformation: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                Section(L("On your computers")) {
                    Label(L("Weavatrix reads the repository on its linked computer and reports components, evidenced relations and code towers."),
                          systemImage: "desktopcomputer")
                }
                Section(L("Keeping the report current")) {
                    Label(L("GrantTap checks repository revisions and requests missing or stale architecture. Refresh requests a new analysis from this Mesh's computers."),
                          systemImage: "arrow.clockwise")
                    Text(L("A request is complete only when a computer sends its analysis report. If it cannot finish, the build shows an error and can be retried."))
                        .foregroundStyle(Theme.muted)
                }
                Section(L("Available offline")) {
                    Label(L("Received reports stay on this device. You can inspect the last report during a rebuild or without a network connection."),
                          systemImage: "internaldrive")
                    Text(L("The graph shows reported evidence. Missing architecture is not treated as verified context."))
                        .foregroundStyle(Theme.muted)
                }
            }
            .foregroundStyle(Theme.ink)
            .pageNavigationTitle(L("How architecture updates"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                }
            }
        }
        .navigationViewStyle(.stack)
    }
}
