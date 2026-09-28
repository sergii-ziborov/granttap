import SwiftUI

struct MainWindowMeshRoute: Identifiable, Hashable {
    let projectId: String
    let sessionId: String
    var id: String { projectId }
}

private struct MainWindowMeshActionKey: EnvironmentKey {
    static let defaultValue: ((String, String) -> Void)? = nil
}

extension EnvironmentValues {
    var openMeshInMainWindow: ((String, String) -> Void)? {
        get { self[MainWindowMeshActionKey.self] }
        set { self[MainWindowMeshActionKey.self] = newValue }
    }
}

#if targetEnvironment(macCatalyst)
enum MacMainWindowRoute: Hashable {
    case chat(String)
    case mesh(MainWindowMeshRoute)
}

extension ContentView {
    func openMeshInMainWindow(projectId: String, sessionId: String) {
        showChatHistory = false
        showCapabilityUsage = false
        openedTaskRoute = nil
        selectedTab = .projects
        openedSession = nil
        model.sessionToOpen = nil
        macNavigationPath = [.mesh(MainWindowMeshRoute(projectId: projectId, sessionId: sessionId))]
    }

    func navigateMacChat(_ session: OpenSession?) {
        guard let session else {
            if case .chat = macNavigationPath.last { macNavigationPath.removeLast() }
            return
        }
        let route = MacMainWindowRoute.chat(session.id)
        if macNavigationPath.last != route { macNavigationPath.append(route) }
    }

    var legacyMacNavigationActive: Binding<Bool> {
        Binding(get: { !macNavigationPath.isEmpty || openedSession != nil }, set: { active in
            if !active {
                macNavigationPath = []
                openedSession = nil
            }
        })
    }

    @ViewBuilder var legacyMacDestination: some View {
        if let route = macNavigationPath.last { macDestination(route) }
        else { openedSessionDestination }
    }

    @ViewBuilder func macDestination(_ route: MacMainWindowRoute) -> some View {
        switch route {
        case .chat(let sessionId):
            sessionDestination(id: sessionId)
        case .mesh(let mesh):
            if let snapshot = model.meshSnapshot(for: mesh.projectId) {
                ProjectMeshView(snapshot: snapshot, model: model,
                    onOpenSession: { session in open(session) }, onBack: { selectMacTab(.projects) })
            } else {
                ProjectMeshPendingView(projectId: mesh.projectId, sessionId: mesh.sessionId, model: model,
                    onBack: { selectMacTab(.projects) })
            }
        }
    }
}
#endif
