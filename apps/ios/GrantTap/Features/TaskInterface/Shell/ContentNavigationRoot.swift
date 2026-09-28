import SwiftUI

extension ContentView {
    @ViewBuilder var navigationRoot: some View {
        #if targetEnvironment(macCatalyst)
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack(path: $macNavigationPath) {
                    navigationContent
                        .navigationDestination(for: MacMainWindowRoute.self, destination: macDestination)
                }
            } else {
                legacyNavigationRoot
            }
        }
        .id(macNavigationRevision)
        .environment(\.openMeshInMainWindow) { projectId, sessionId in
            openMeshInMainWindow(projectId: projectId, sessionId: sessionId)
        }
        #else
        legacyNavigationRoot
        #endif
    }

    private var legacyNavigationRoot: some View {
        CompatNavigationStack {
            navigationContent
                #if targetEnvironment(macCatalyst)
                .background(
                    NavigationLink(destination: legacyMacDestination,
                                   isActive: legacyMacNavigationActive) { EmptyView() }.hidden()
                )
                #else
                .background(
                    NavigationLink(destination: openedSessionDestination,
                                   isActive: chatNavigationActive) { EmptyView() }.hidden()
                )
                #endif
        }
    }

    private var navigationContent: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            #if targetEnvironment(macCatalyst)
            if !desktopLicense.license.permitsLocalControl && selectedTab != .settings {
                DesktopLicenseView(store: desktopLicense)
            } else if macLocalMCP.isReady || model.pairing != nil || model.demoMode || selectedTab == .settings {
                personalTabs
                    .id(selectedTab)
            } else {
                MacLocalMCPWelcomeView(
                    checked: macLocalMCP.hasCheckedLocalMCP,
                    refreshing: macLocalMCP.refreshing,
                    found: macLocalMCP.status != nil,
                    onRetry: { Task { await refreshMacLocal() } },
                    onSettings: { selectMacTab(.settings) }
                )
            }
            #else
            if model.pairing == nil && !model.demoMode { onboarding }
            else { personalTabs }
            privacyLayers
            #endif
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        #if targetEnvironment(macCatalyst)
        .navigationBarHidden(true)
        #else
        .navigationBarHidden(security.showsLockUI)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if !security.showsLockUI, model.pairing != nil || model.demoMode { connectionBadge }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !security.showsLockUI, model.pairing != nil || model.demoMode {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(L("Settings"))
                }
            }
        }
        #endif
    }
}
