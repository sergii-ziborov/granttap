import SwiftUI

/// The same request state appears in Graph and Health, with one progress indicator.
struct ProjectGraphBuildCard: View {
    let request: ProjectGraphRequest?
    let reports: [ProjectRepositoryGraph]
    let needsAnalysis: Bool
    var actionIdentifier = "project.graph.analyze"
    let rebuild: () -> Void
    @State private var showInformation = false

    private var pending: Bool { request?.pending == true }
    private var received: [ProjectRepositoryGraph] {
        reports.filter { $0.analysisStatus == "COMPLETE" || $0.analysisStatus == "INCOMPLETE" }
    }
    private var needsAttention: Bool {
        request?.result == .failed || request?.result == .noRoute || request?.result == .partial
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: needsAttention ? "exclamationmark.triangle" : "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(needsAttention ? Theme.riskMed : Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(.headline).foregroundStyle(Theme.ink)
                    Text(detail).font(.subheadline).foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Button { showInformation = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 18))
                        .frame(width: 32, height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
                .accessibilityLabel(L("How architecture updates"))
                .accessibilityIdentifier("project.graph.build-info")
            }
            if pending {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.ink)
                        .accessibilityLabel(L("Waiting for computer reports"))
                        .accessibilityIdentifier("project.graph.progress")
                    Text(L("Waiting for computer reports"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.ink)
                        .accessibilityHidden(true)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
            } else {
                Button(action: rebuild) {
                    Label(actionTitle, systemImage: "arrow.clockwise")
                }
                .buttonStyle(FilledButton(tint: Theme.actionFill))
                .accessibilityIdentifier(actionIdentifier)
            }
            if !received.isEmpty {
                Label(reportSummary, systemImage: pending || needsAttention || needsAnalysis
                      ? "clock" : "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .accessibilityIdentifier("project.graph.saved-report")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("project.graph.status")
        .sheet(isPresented: $showInformation) { ProjectGraphBuildInformation() }
    }

    private var title: String {
        if pending { return L(received.isEmpty ? "Building architecture…" : "Refreshing architecture…") }
        switch request?.result {
        case .failed: return L("Architecture could not refresh")
        case .noRoute: return L("Computer connection needed")
        case .partial: return L("Architecture needs attention")
        default:
            if received.isEmpty { return L("Architecture is not built yet") }
            return L(needsAnalysis ? "Architecture needs refresh" : "Repository architecture")
        }
    }

    private var detail: String {
        if pending, request?.result == .requested {
            return L("Analysis requested from this Mesh's computers.")
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
        if needsAttention { return L("Retry architecture build") }
        return L(received.isEmpty ? "Build architecture now" : "Refresh architecture")
    }

    private var reportSummary: String {
        let counts = [
            LPlural(received.count, one: "%d report", many: "%d reports"),
            LPlural(received.reduce(0) { $0 + $1.totalNodes }, one: "%d component", many: "%d components"),
            LPlural(received.reduce(0) { $0 + $1.totalRelations }, one: "%d relation", many: "%d relations"),
        ].joined(separator: " · ")
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
