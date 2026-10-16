import SwiftUI

extension ProjectNewTaskView {
    func createTask() {
        guard !model.demoMode, !draft.sending else { return }
        let request: ProjectTaskCreationRequest
        do { request = try draft.request(context) }
        catch { draft.error = error.localizedDescription; return }
        draft.sending = true
        draft.error = nil
        savedProvider = request.provider
        #if targetEnvironment(macCatalyst)
        if request.endpointId == context.localEndpointId {
            Task {
                defer { draft.sending = false }
                do {
                    guard let reader = model.localMCPReader else { throw ProjectTaskDraftError.invalidRoute }
                    let result = try await reader.createTask(projectId: request.projectId, bindingId: request.bindingId,
                        endpointId: request.endpointId, provider: request.provider, text: request.text,
                        model: request.model, attachments: request.attachments, effort: request.effort,
                        operationId: request.operationId)
                    guard result.created else {
                        draft.confirmedFailure()
                        draft.error = result.error ?? L("Could not create this Task.")
                        return
                    }
                    await reader.refresh()
                    MacLocalProjection.apply(reader.meshSnapshots, to: model)
                    close()
                    if let session = result.session_id { model.sessionToOpen = session }
                } catch { draft.error = L("Could not create this Task. Your draft is kept; try again.") }
            }
            return
        }
        #endif
        guard let room = context.rooms[request.endpointId] else {
            draft.sending = false
            draft.error = L("This computer is not connected to the Mesh.")
            return
        }
        model.sendMessage(request.text, agent: request.provider, cwd: request.workspace,
            attachments: request.attachments.map(\.payload),
            attachmentRefs: model.attachmentRefs(for: request.attachments, room: room),
            roomId: room, projectId: request.projectId, model: request.model,
            overrides: TurnOverrides(effort: request.effort.flatMap(TurnEffort.init(rawValue:))))
        draft.sending = false
        close()
    }
}
