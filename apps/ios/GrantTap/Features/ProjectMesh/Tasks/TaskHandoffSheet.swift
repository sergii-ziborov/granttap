import SwiftUI

struct TaskHandoffSheet: View {
    @Environment(\.dismiss) var dismiss
    let session: SessionInfo
    @ObservedObject var model: AppModel
    let onPrepared: ((String) -> Void)?
    @State var targetRoom: String
    @State var checkpointUncommitted = false
    @State var pushBranch = false
    @State var targetProvider: String
    @State var targetModel: String
    @State var targetEffort = ""
    @State var cloudEnvironment = ""
    @State var cloudRun: ExecutionSessionLink?
    @State var userComment = ""
    @State var handoffError: String?
    @State var submitting = false
    @State var awaitingConfirmation = false
    @State var pendingHandoffEvents: Set<String>?
    @State var pendingHandoffComputer: String?
    @State var observesHandoff = true
    @State var handoffNotBefore: Double = 0

    init(
        session: SessionInfo,
        model: AppModel,
        initialTargetRoom: String = "",
        initialTargetProvider: String = "",
        initialTargetModel: String = "",
        onPrepared: ((String) -> Void)? = nil
    ) {
        self.session = session
        self.model = model
        self.onPrepared = onPrepared
        _targetRoom = State(initialValue: initialTargetRoom)
        _targetProvider = State(initialValue: initialTargetProvider)
        _targetModel = State(initialValue: initialTargetModel)
    }

    var sourceRoom: String? {
        #if targetEnvironment(macCatalyst)
        if model.usesLocalTaskDelivery(for: session) { return "local-mcp" }
        #endif
        return model.sourceRoom(forSessionId: session.sessionId)
    }
    var localComputerId: String? {
        #if targetEnvironment(macCatalyst)
        return model.localMCPReader?.status?.endpointId
        #else
        return nil
        #endif
    }
    var localComputerName: String? {
        #if targetEnvironment(macCatalyst)
        return model.localMCPReader?.status?.computer
        #else
        return nil
        #endif
    }
    /// Every computer of the mesh, this one first: a Task can move to another
    /// agent here as well as to another machine.
    var targets: [LinkedComputer] {
        let all = model.connectionRegistry.connections
        return all.filter { $0.id == sourceRoom } + all.filter { $0.id != sourceRoom }
    }
    /// A cloud runner is never "here", even though this computer starts it.
    var staysHere: Bool {
        guard cloudTarget == nil else { return false }
        return targetRoom == sourceRoom
            || (localComputerId != nil && destinationComputer(for: targetRoom) == localComputerId)
    }
    var effectiveTargetRoom: String {
        targetRoom.isEmpty ? defaultSelection.room : targetRoom
    }
    var effectiveTargetProvider: String {
        targetProvider.isEmpty ? defaultSelection.provider : targetProvider
    }
    /// The same agent on the same computer is not a move.
    var sameAgentHere: Bool {
        staysHere && AgentIdentity.normalize(targetProvider) == AgentIdentity.normalize(session.agent)
            && (targetModel.isEmpty || targetModel == session.model)
    }

    var body: some View {
        ChatSheetNavigation(title: L("Transfer to"), doneIdentifier: "handoff.close",
                            closeTitle: L("Cancel"), onClose: { observesHandoff = false; dismiss() }) {
            VStack(spacing: 0) {
                Form {
                    destinationSection
                    Section {
                        TextEditor(text: $userComment)
                            .frame(minHeight: 80)
                            .accessibilityIdentifier("handoff.comment")
                    } header: {
                        Text(L("Comment for the next agent"))
                    } footer: {
                        Text(L("The comment travels in the encrypted Task Capsule and is shown to the destination agent."))
                    }
                    if !grokActors.isEmpty && cloudTarget == nil {
                        Section("Grok Bot") {
                            ForEach(grokActors) { actor in
                                Button {
                                    model.prepareTaskHandoff(
                                        session: session, targetActorId: actor.actorId
                                    )
                                    dismiss()
                                } label: {
                                    HStack {
                                        Text(actor.displayName)
                                        Spacer()
                                        Text("Grok Bot").foregroundStyle(Theme.muted)
                                    }
                                }
                                .disabled(!isReadyForGrokBot)
                            }
                        }
                    }
                    if canCheckpointWork || !staysHere {
                        Section {
                            if canCheckpointWork {
                                Toggle(L("Commit changes before transfer"), isOn: $checkpointUncommitted)
                                    .accessibilityIdentifier("handoff.checkpoint")
                            }
                            if !staysHere {
                                Toggle(L("Push the branch to the remote"), isOn: $pushBranch)
                                    .accessibilityIdentifier("handoff.push")
                            }
                        } footer: {
                            Text(cloudTarget != nil
                                 ? L("A push publishes the branch, or a checkpoint branch, to the repository's remote, never by force, so the cloud runner can fetch it.")
                                 : staysHere
                                 ? L("The source computer commits the changes to a branch named granttap/checkpoint/… and nothing else moves.")
                                 : L("A checkpoint commits the changes to a branch named granttap/checkpoint/…. A push publishes that branch — or the current one — to the repository's remote, never by force, so the other computer can fetch the commit before it starts."))
                        }
                    }
                    Section(L("Handoff readiness")) {
                        ForEach(readinessChecks) { check in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: !check.ready ? "exclamationmark.triangle.fill"
                                      : check.warning ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                    .foregroundStyle(!check.ready ? Theme.riskHigh
                                                     : check.warning ? Theme.riskMed : Theme.ok)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(check.title).font(.system(size: 14, weight: .semibold))
                                    Text(check.detail).font(.caption).foregroundStyle(Theme.muted)
                                }
                            }
                        }
                    }
                    transferContextSection
                }
                .onAppear(perform: applyDefaults)
                .disabled(submitting || awaitingConfirmation || cloudRun != nil)
                transferFooter
            }
            .onDisappear { observesHandoff = false }
        }
    }

    /// Readiness for one concrete destination, so the button and the action
    /// that follows it can never disagree about what is being checked.
    func readinessChecks(room: String, provider: String) -> [HandoffReadinessCheck] {
        let cloud = TaskHandoffCloudTarget(tag: room)
        let computerRoom = cloud?.room ?? room
        let checks = TaskHandoffReadiness.checks(
            session: session,
            snapshot: session.projectId.flatMap { model.meshSnapshots[$0] },
            destinationSelected: targets.contains { $0.id == computerRoom }
                || (computerRoom == "local-mcp" && localComputerId != nil),
            targetProviderEnabled: !provider.isEmpty
                && model.agentMeshPreferences.isProviderEnabled(
                    AgentIdentity.normalize(cloud?.provider ?? provider)
                ),
            checkpoint: checkpointUncommitted
        )
        return cloud == nil ? checks : checks + [TaskHandoffCloudTarget.readiness(push: pushBranch)]
    }

    /// Whether this execution has work a plain handoff would leave behind.
    var hasUncommittedWork: Bool {
        TaskHandoffReadiness.sourceExecution(for: session,
            in: session.projectId.flatMap { model.meshSnapshots[$0] })?.uncommitted == true
    }

    /// The computer checks the checkout at submission; a delayed report must not hide this choice.
    var canCheckpointWork: Bool {
        TaskHandoffReadiness.sourceExecution(for: session,
            in: session.projectId.flatMap { model.meshSnapshots[$0] })?.uncommitted != false
    }

    var readinessChecks: [HandoffReadinessCheck] {
        readinessChecks(room: effectiveTargetRoom, provider: destinationProvider)
    }

    var isReady: Bool { TaskHandoffReadiness.isReady(readinessChecks) }

    /// Grok Bot needs no linked destination computer, but uncommitted work and
    /// overlapping claims block it for exactly the same reason.
    var isReadyForGrokBot: Bool {
        TaskHandoffReadiness.isReady(
            readinessChecks.filter { $0.id != "destination" && $0.id != "targetAgent" }
        )
    }

    var grokActors: [GrokBotMeshActor] {
        guard model.agentMeshPreferences.meshEnabled,
              let connection = model.grokBotConnection,
              connection.credential.status == "active",
              session.projectId.map(connection.credential.projectIds.contains) == true
        else { return [] }
        return connection.actors.filter(\.enabled)
    }

}
