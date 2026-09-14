import SwiftUI

/// What surrounds the tabs: the screen shown before a computer is paired,
/// the tab bar itself, and the badge that says whether the phone is connected.
extension ContentView {
    var onboarding: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 50)
                notPairedCard
            }
            .padding(16)
        }
    }

    var personalTabs: some View {
        TabView(selection: $selectedTab) {
            tabScroll {
                pendingSection
                nowSessionsSection
                Button { prepareNewTask() } label: {
                    Label(L("New Task"), systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(OutlineButton(tint: Theme.ink))
            }
            .tabItem { Label(L("Now"), systemImage: "bolt.fill") }
            .tag(PersonalTab.now)

            tabScroll { tasksSection }
                .tabItem { Label(L("Tasks"), systemImage: "tray.full") }
                .tag(PersonalTab.tasks)

            ProjectsTabView(model: model) { session in
                model.sessionToOpen = session.sessionId
            }
            .tabItem { Label(L("Projects"), systemImage: "point.3.connected.trianglepath.dotted") }
            .tag(PersonalTab.projects)

            CapabilityUsageView()
                .tabItem { Label(L("Usage"), systemImage: "chart.bar.xaxis") }
                .tag(PersonalTab.usage)
        }
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
