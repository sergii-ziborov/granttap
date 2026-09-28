#if targetEnvironment(macCatalyst)
import SwiftUI

extension TaskChatView {
    func loadLocalConversation(cursor: String? = nil) async {
        guard let reader = model.localMCPReader, model.usesLocalMCP(for: currentSession) else { return }
        localActivityLoading = true
        localActivityError = false
        defer { localActivityLoading = false }
        do {
            let activity = try await reader.activity(for: currentSession, cursor: cursor)
            MacLocalProjection.apply(activity, for: currentSession, to: model)
        } catch {
            localActivityError = true
        }
    }

    var macChatHeader: some View {
        MacPageHeader(title: ProjectMeshTaskTitle.presentable(currentSession.displayTitle)
                      ?? L("Untitled Task"), onBack: { dismiss() }) {
            if meshProjectId != nil {
                Button { openMesh() } label: {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                }
                .accessibilityLabel(L("Mesh"))
                .accessibilityIdentifier("chat.open-mesh")
            }
            taskControlsMenu
        }
    }
}
#endif
