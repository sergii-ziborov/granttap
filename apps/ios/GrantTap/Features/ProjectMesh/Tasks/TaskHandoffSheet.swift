import SwiftUI

struct TaskHandoffSheet: View {
    @Environment(\.dismiss) var dismiss
    let session: SessionInfo
    @ObservedObject var model: AppModel
    @State var targetRoom: String
    @State var checkpointUncommitted = false
    @State var pushBranch = false
    @State var targetProvider: String
    @State var targetModel: String
    @State var userComment = ""
    @State var handoffError: String?
    @State var submitting = false

    init(
        session: SessionInfo,
        model: AppModel,
        initialTargetRoom: String = "",
        initialTargetProvider: String = "",
        initialTargetModel: String = ""
    ) {
        self.session = session
        self.model = model
        _targetRoom = State(initialValue: initialTargetRoom)
        _targetProvider = State(initialValue: initialTargetProvider)
        _targetModel = State(initialValue: initialTargetModel)
    }

    var sourceRoom: String? {
        #if targetEnvironment(macCatalyst)
        if model.usesLocalMCP(for: session) { return "local-mcp" }
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
    var staysHere: Bool {
        targetRoom == sourceRoom
            || (localComputerId != nil && destinationComputer(for: targetRoom) == localComputerId)
    }
    private var effectiveTargetRoom: String {
        targetRoom.isEmpty ? defaultSelection.room : targetRoom
    }
    private var effectiveTargetProvider: String {
        targetProvider.isEmpty ? defaultSelection.provider : targetProvider
    }
    /// The same agent on the same computer is not a move.
    var sameAgentHere: Bool {
        staysHere && AgentIdentity.normalize(targetProvider) == AgentIdentity.normalize(session.agent)
            && (targetModel.isEmpty || targetModel == session.model)
    }

    var modelOptions: [TurnModelOption] {
        #if targetEnvironment(macCatalyst)
        if effectiveTargetRoom == "local-mcp" {
            return model.turnModelCatalog(agent: effectiveTargetProvider, session: session).options
        }
        #endif
        return model.turnModelCatalog(agent: effectiveTargetProvider, roomId: effectiveTargetRoom).options
    }

    var body: some View {
        CompatNavigationStack {
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
                if !grokActors.isEmpty {
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
                if hasUncommittedWork || !staysHere {
                    Section {
                        if hasUncommittedWork {
                            Toggle(L("Checkpoint uncommitted work"), isOn: $checkpointUncommitted)
                                .accessibilityIdentifier("handoff.checkpoint")
                        }
                        if !staysHere {
                            Toggle(L("Push the branch to the remote"), isOn: $pushBranch)
                                .accessibilityIdentifier("handoff.push")
                        }
                    } footer: {
                        Text(staysHere
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
                Section {
                    Text(L("GrantTap sends a bounded encrypted Task Capsule: goal, git state, changed files, tests, dependencies, claims, remaining work, and explicit decisions. It never copies hidden reasoning."))
                    Text(L("Use a separate branch or worktree on the destination computer. If no authorized checkout matches, the handoff fails safely in Needs You."))
                }
                if let handoffError {
                    Text(handoffError).foregroundStyle(Theme.riskHigh)
                }
                Button(L("Prepare and hand off"), action: submitHandoff)
                .disabled(!isReady || sameAgentHere || userComment.count > 1_000 || submitting)
                .accessibilityIdentifier("handoff.submit")
            }
            .navigationTitle(L("Task handoff"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Cancel")) { dismiss() }
                }
            }
            .onAppear(perform: applyDefaults)
        }
    }

    private var destinationSection: some View {
        Section {
            Picker(L("Computer"), selection: $targetRoom) { computerOptions }
            Picker(L("Agent"), selection: $targetProvider) { agentOptions }
            Picker(L("Model"), selection: $targetModel) {
                Text(L("Automatic")).tag("")
                ForEach(modelOptions) { option in Text(option.label).tag(option.id) }
            }
            .accessibilityIdentifier("handoff.model")
            .onChange(of: targetProvider) { _ in targetModel = "" }
            .onChange(of: targetRoom) { _ in targetModel = "" }
        } header: {
            Text(L("Destination"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(sameAgentHere
                     ? L("Choose another agent or model, or another computer: this is where the Task already is.")
                     : staysHere
                        ? L("The Task continues here in a new worktree from the last commit.")
                        : L("The other computer needs the commit: push the branch, or make sure it can fetch it."))
                if !targetModel.isEmpty {
                    Text(L("A new execution starts with Task context and your comment; native chat history is not copied."))
                }
            }
        }
    }

    /// Readiness for one concrete destination, so the button and the action
    /// that follows it can never disagree about what is being checked.
    func readinessChecks(room: String, provider: String) -> [HandoffReadinessCheck] {
        TaskHandoffReadiness.checks(
            session: session,
            snapshot: session.projectId.flatMap { model.meshSnapshots[$0] },
            destinationSelected: targets.contains { $0.id == room }
                || (room == "local-mcp" && localComputerId != nil),
            targetProviderEnabled: !provider.isEmpty
                && model.agentMeshPreferences.isProviderEnabled(
                    AgentIdentity.normalize(provider)
                ),
            checkpoint: checkpointUncommitted
        )
    }

    /// Whether this execution has work a plain handoff would leave behind.
    var hasUncommittedWork: Bool {
        session.projectId.flatMap { model.meshSnapshots[$0] }?.executions
            .first { $0.sessionId == session.sessionId && $0.endedAt == nil }?.uncommitted == true
    }

    var readinessChecks: [HandoffReadinessCheck] {
        readinessChecks(room: effectiveTargetRoom, provider: effectiveTargetProvider)
    }

    var isReady: Bool { TaskHandoffReadiness.isReady(readinessChecks) }

    /// Grok Bot needs no linked destination computer, but uncommitted work and
    /// overlapping claims block it for exactly the same reason.
    var isReadyForGrokBot: Bool {
        TaskHandoffReadiness.isReady(
            readinessChecks.filter { $0.id != "destination" && $0.id != "targetAgent" }
        )
    }

    var computerOptions: some View {
        Group {
            if let localComputerId {
                Text(String(format: L("%@ (this computer)"),
                            localComputerName ?? localComputerId)).tag("local-mcp")
            }
            ForEach(targets) { connection in
                Text(connection.id == sourceRoom
                     ? String(format: L("%@ (this computer)"), computerName(connection))
                     : computerName(connection)).tag(connection.id)
            }
        }
    }

    var agentOptions: some View {
        Group {
            ForEach(AgentIdentity.composeIds.filter {
                model.agentMeshPreferences.isProviderEnabled($0)
            }, id: \.self) { provider in
                Text(AgentIdentity.displayName(provider)).tag(provider)
            }
        }
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
