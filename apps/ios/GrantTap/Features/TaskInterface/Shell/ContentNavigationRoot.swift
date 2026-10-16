import SwiftUI

extension ContentView {
    @ViewBuilder var navigationRoot: some View {
        #if targetEnvironment(macCatalyst)
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack(path: $macNavigationPath) {
                    navigationContent
                        .onAppear { macNavigationRootVisible = true }
                        .onDisappear { macNavigationRootVisible = false }
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
            if !desktopLicense.license.permitsLocalControl
                && !macRelayCompanionReady
                && selectedTab != .settings && selectedTab != .devices {
                DesktopLicenseView(store: desktopLicense, onBack: { selectMacTab(.devices) })
            } else if macLocalMCP.isReady || model.pairing != nil || model.demoMode
                        || selectedTab == .settings || selectedTab == .devices {
                personalTabs
            } else {
                MacLocalMCPWelcomeView(
                    checked: macLocalMCP.hasCheckedLocalMCP,
                    refreshing: macLocalMCP.refreshing,
                    found: macLocalMCP.status != nil,
                    accountLinked: macLocalMCP.status?.accountLinkSaved == true,
                    onRetry: { Task { await refreshMacLocal() } },
                    onSettings: { selectMacTab(.settings) },
                    onDevices: { selectMacTab(.devices) }
                )
            }
            #else
            personalTabs
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
                if !security.showsLockUI,
                   !model.connectionOverview.isEmpty || GrantTapAccountAPI.session != nil || model.demoMode {
                    connectionBadge
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if !security.showsLockUI {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel(L("Settings"))
                }
            }
        }
        #endif
    }

    #if targetEnvironment(macCatalyst)
    private var macRelayCompanionReady: Bool {
        model.connectionRegistry.connections.contains { connection in
            desktopLicense.license.permitsRelayCompanionInspection(linkedAccountID: connection.linkedAccountId,
                currentAccountID: subscription.currentAccountID())
        }
    }
    #endif
}
