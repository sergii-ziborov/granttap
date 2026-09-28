import DesktopInspectorCore
import SwiftUI

struct DesktopView: View {
    @ObservedObject var model: DesktopModel
    var body: some View {
        NavigationSplitView {
            List(selection: $model.selected) {
                SwiftUI.Section("Workspace") {
                    sidebarRow(.now)
                    sidebarRow(.tasks)
                    sidebarRow(.project)
                    sidebarRow(.usage)
                }
                SwiftUI.Section("System") {
                    sidebarRow(.engine)
                }
            }
            .navigationTitle("GrantTap")
            .scrollContentBackground(.hidden)
            .background(DesktopTheme.surface)
        } detail: {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                detail
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .background(DesktopTheme.background)
            .frame(minWidth: 800, minHeight: 560)
        }
        .task {
            while !Task.isCancelled {
                model.checkLocalMCP()
                try? await Task.sleep(for: .seconds(15))
            }
        }
    }

    private func sidebarRow(_ section: DesktopModel.Section) -> some View {
        Label(section.rawValue, systemImage: icon(section)).tag(section)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("GrantTap")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DesktopTheme.muted)
            Spacer()
            Circle().fill(model.mcpStatus == nil ? DesktopTheme.caution : DesktopTheme.positive)
                .frame(width: 7, height: 7)
            Text(model.mcpStatus == nil ? "Mac offline" : "Mac connected")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesktopTheme.muted)
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .help("Refresh Mesh")
                .disabled(model.loading)
        }
        .padding(.horizontal, 24)
        .frame(height: 62)
        .background(DesktopTheme.surface)
    }

    @ViewBuilder private var detail: some View {
        switch model.selected ?? .now {
        case .now:
            NowDashboardView(model: model)
        case .tasks:
            if model.snapshot?.project == nil && model.workspaceSummary == nil {
                ProjectRequiredView(model: model, title: "Tasks", symbol: "tray.full",
                                    explanation: "Connect this Mac to see Tasks in Mesh.")
            } else { TaskWorkspaceView(model: model) }
        case .usage:
            UsageOverviewView(snapshot: model.snapshot, workspace: model.workspaceSummary)
        case .engine:
            MCPConnectionView(model: model)
        case .project:
            ProjectDetailView(model: model)
        case .bindings:
            if model.snapshot?.project == nil {
                ProjectRequiredView(model: model, title: "Computers",
                                    symbol: "desktopcomputer",
                                    explanation: "Select a Project to see its bound computers and repositories.")
            } else if let bindings = model.snapshot?.bindings, !bindings.isEmpty {
                List(bindings) { binding in
                    VStack(alignment: .leading) {
                        Text(binding.local_alias ?? binding.repository_id).font(.headline)
                        Text("\(binding.endpoint_id) · \(binding.role)").foregroundStyle(.secondary)
                        if let revision = binding.observed_revision {
                            Text(revision).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
            } else { ContentUnavailableView("No bindings", systemImage: "desktopcomputer") }
        case .policy:
            if model.snapshot?.project == nil {
                ProjectRequiredView(model: model, title: "Governance",
                                    symbol: "checkmark.shield",
                                    explanation: "Select a Project to inspect its policy, rules, and endpoint coverage.")
            } else { GovernanceDetailView(snapshot: model.snapshot) }
        case .backbone:
            if model.snapshot?.project == nil {
                ProjectRequiredView(model: model, title: "Project graph",
                                    symbol: "point.3.connected.trianglepath.dotted",
                                    explanation: "Select a Project to explore its evidenced components and relations.")
            } else { BackboneDetailView(backbone: model.snapshot?.backbone) }
        }
    }

    private func icon(_ section: DesktopModel.Section) -> String {
        switch section {
        case .now: "bolt.fill"
        case .tasks: "tray.full"
        case .usage: "chart.bar.xaxis"
        case .engine: "network"
        case .project: "folder"
        case .bindings: "desktopcomputer"
        case .policy: "checkmark.shield"
        case .backbone: "point.3.connected.trianglepath.dotted"
        }
    }

}
