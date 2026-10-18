#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

extension ContentView {
    func refreshMacLocal() async {
        guard !model.demoMode else { return }
        if !desktopLicense.license.permitsLocalControl {
            await macLocalMCP.probeStatus()
            return
        }
        model.localMCPReader = macLocalMCP
        await macLocalMCP.refresh()
        guard !model.demoMode else { return }
        MacLocalProjection.apply(macLocalMCP.meshSnapshots, to: model)
    }

    var macSidebar: some View {
        VStack(alignment: .leading, spacing: 6) {
            sidebarTab(.now, L("Now"), "bolt.fill")
            sidebarTab(.tasks, L("Tasks"), "tray.full")
            sidebarTab(.projects, L("Mesh"), "point.3.connected.trianglepath.dotted")
            sidebarTab(.usage, L("Usage"), "chart.bar.xaxis")
            sidebarTab(.devices, L("Devices"), "desktopcomputer")

            Divider().padding(.vertical, 12)
            sidebarTab(.settings, L("Settings"), "gearshape")
        }
        .padding(12)
        .frame(width: 220)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.raised)
    }

    var macSelectedScreen: some View {
        VStack(spacing: 0) {
            Group {
                if selectedTab != .settings && selectedTab != .devices,
                   macLocalMCP.refreshing && model.meshSnapshots.isEmpty && model.sessions.isEmpty {
                    ProgressView(L("Loading Mesh and Tasks from this Mac…"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch selectedTab {
                    case .now:
                        tabScroll { pendingSection; nowSessionsSection }
                    case .tasks:
                        tabScroll { tasksSection }
                    case .projects:
                        ProjectsTabView(model: model, onOpenSession: { session in
                            model.sessionToOpen = session.sessionId
                        }, onCreateMesh: { showNewMesh = true })
                    case .usage:
                        CapabilityUsageView()
                    case .devices:
                        DevicesView(localComputer: macLocalMCP.status?.computer,
                                    localAccountLinked: macLocalMCP.status?.accountLinkSaved,
                                    localPaired: macLocalMCP.status?.paired,
                                    localRelayStatus: macLocalMCP.status?.relayStatus,
                                    localPhoneReachability: macLocalMCP.status?.phoneReachability)
                            .environmentObject(model)
                            .environmentObject(macLocalMCP)
                    case .settings:
                        SettingsView(
                            localComputer: macLocalMCP.status?.computer,
                            localPaired: macLocalMCP.status?.paired,
                            localRelayStatus: macLocalMCP.status?.relayStatus,
                            localPhoneReachability: macLocalMCP.status?.phoneReachability,
                            onExitDemo: { selectMacTab(.now) }
                        )
                        .environmentObject(model)
                        .environmentObject(macLocalMCP)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #if DEBUG
            .overlay(alignment: .topLeading) {
                if MacTabFrameTiming.enabled {
                    MacTabFrameProbe(tab: String(describing: selectedTab))
                        .frame(width: 1, height: 1).allowsHitTesting(false)
                }
            }
            #endif
        }
        .onAppear(perform: hideDuplicateMacWindowTitle)
        .onChange(of: selectedTab) { _ in hideDuplicateMacWindowTitle() }
        .onReceive(macLocalMCP.$sessionUsage) { usage in
            guard !model.demoMode else { return }
            MacLocalProjection.apply(macLocalMCP.meshSnapshots, to: model, sessionUsage: usage)
        }
    }

    private func hideDuplicateMacWindowTitle() {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .forEach { $0.title = "\u{200B}" }
    }

    private func sidebarTab(_ tab: PersonalTab, _ title: String, _ icon: String) -> some View {
        Button {
            selectMacTab(tab)
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .foregroundStyle(Theme.ink)
        }
        .pointerButtonStyle(selected: selectedTab == tab)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        .accessibilityIdentifier("sidebar.\(String(describing: tab))")
    }

    func selectMacTab(_ tab: PersonalTab) {
        // View-based drilldowns are not represented in the typed path. Reset
        // only when leaving one, retaining the navigation host between roots.
        let leavingDestination = !macNavigationRootVisible
        guard selectedTab != tab || leavingDestination else { return }
        #if DEBUG
        MacTabFrameTiming.begin(String(describing: tab))
        #endif
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if !macNavigationPath.isEmpty { macNavigationPath = [] }
            if openedSession != nil { openedSession = nil }
            if model.sessionToOpen != nil { model.sessionToOpen = nil }
            selectedTab = tab
            if #available(iOS 16.0, *) {
                if leavingDestination { macNavigationRevision += 1 }
            } else { macNavigationRevision += 1 }
        }
    }

}

struct MacBrandHeader: View {
    var body: some View {
        HStack(spacing: 8) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            Text("GrantTap")
                .font(.system(size: 17, weight: .semibold))
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(Theme.surface)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.line).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("mac.brand-header")
    }
}

struct MacLocalComputerDetailView: View {
    @ObservedObject var reader: MacLocalMCPModel

    var body: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let status = reader.status {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(status.computer, systemImage: "desktopcomputer")
                                .font(.title2.bold())
                            Text("GrantTap MCP \(status.version) · \(L("This Mac"))")
                                .foregroundStyle(Theme.muted)
                            if let workspace = reader.workspace {
                                Text("\(workspace.project_count) Mesh · \(workspace.task_count) Tasks")
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    Divider()
                    Text(L("Agent processes"))
                        .font(.headline)
                    if let load = reader.machineLoad {
                        Text(L("Process sample") + " · " +
                             Date(timeIntervalSince1970: load.observed_at / 1000)
                                .formatted(date: .omitted, time: .standard))
                            .font(.caption)
                            .foregroundStyle(Theme.muted)
                        if load.agents.isEmpty {
                            Text(L("No coding-agent processes found."))
                                .foregroundStyle(Theme.muted)
                        }
                        ForEach(load.agents) { agent in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(agent.agent.capitalized).font(.headline)
                                Text("\(agent.processes) processes · \(agent.cpu_percent, specifier: "%.1f")% CPU · \(Int(agent.memory_bytes / 1_000_000)) MB")
                                ForEach(agent.groups, id: \.name) { group in
                                    Text("\(group.name) ×\(group.count) · \(group.cpu_percent, specifier: "%.1f")% · \(Int(group.memory_bytes / 1_000_000)) MB")
                                        .font(.caption)
                                        .foregroundStyle(Theme.muted)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12))
                        }
                    } else if let error = reader.machineLoadError {
                        Text(error).foregroundStyle(Theme.riskMed)
                    } else {
                        ProgressView()
                    }
                    let openTasks = reader.workspace?.tasks.filter {
                        $0.has_open_execution == true
                    } ?? []
                    if !openTasks.isEmpty {
                        Divider()
                        Text(L("Tasks with open sessions")).font(.headline)
                        ForEach(openTasks.prefix(12)) { task in
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(task.title).lineLimit(2)
                                    Text("\(task.project_name) · \(task.provider ?? L("Agent"))")
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 8)
                                Text(task.stateLabel).font(.caption).foregroundStyle(Theme.muted)
                            }
                            .padding(12)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .pageNavigationTitle(L("Computer")) {
            Button { Task { await reader.refreshMachineLoad() } } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
        .frame(minWidth: 620, minHeight: 480)
        .task { await reader.refreshMachineLoad() }
    }
}
#endif
