import SwiftUI

/// Main navigation and the status of an individual linked computer.
extension ContentView {
    var navigationTitle: String {
        switch selectedTab {
        case .now: return "GrantTap"
        case .tasks: return L("Tasks")
        case .projects: return L("Mesh")
        case .usage: return L("Usage")
        case .devices: return L("Devices")
        case .settings: return L("Settings")
        }
    }

    var personalTabs: some View {
        #if targetEnvironment(macCatalyst)
        macSelectedScreen
        #else
        TabView(selection: $selectedTab) {
            tabScroll {
                if model.pairing == nil && GrantTapAccountAPI.session == nil && !model.demoMode {
                    notPairedCard
                }
                pendingSection
                nowSessionsSection
            }
            .tabItem { Label(L("Now"), systemImage: "bolt.fill") }
            .tag(PersonalTab.now)

            tabScroll { tasksSection }
                .tabItem { Label(L("Tasks"), systemImage: "tray.full") }
                .tag(PersonalTab.tasks)

            ProjectsTabView(model: model) { session in
                model.sessionToOpen = session.sessionId
            }
            .tabItem { Label(L("Mesh"), systemImage: "point.3.connected.trianglepath.dotted") }
            .tag(PersonalTab.projects)

            CapabilityUsageView()
                .tabItem { Label(L("Usage"), systemImage: "chart.bar.xaxis") }
                .tag(PersonalTab.usage)

            DevicesView()
                .environmentObject(model)
                .tabItem { Label(L("Devices"), systemImage: "desktopcomputer") }
                .tag(PersonalTab.devices)
        }
        #endif
    }

    func tabScroll<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) { content() }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .refreshable { await model.refreshSessions() }
    }

    var connectionBadge: some View {
        Button { showConnectionDetail = true } label: {
            HStack(spacing: 5) {
                Circle().fill(model.connectionSnapshot.statusColor).frame(width: 7, height: 7)
                Text(model.connectionSnapshot.statusTitle).font(.system(size: 11, weight: .semibold))
            }
        }
        .foregroundStyle(Theme.ink)
    }
}
