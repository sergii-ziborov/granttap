import SwiftUI

struct TaskHandoffSheet: View {
    @Environment(\.dismiss) private var dismiss
    let session: SessionInfo
    @ObservedObject var model: AppModel
    @State private var targetRoom: String
    @State private var checkpointUncommitted = false
    @State private var pushBranch = false
    @State private var targetProvider: String

    init(
        session: SessionInfo,
        model: AppModel,
        initialTargetRoom: String = "",
        initialTargetProvider: String = "codex"
    ) {
        self.session = session
        self.model = model
        _targetRoom = State(initialValue: initialTargetRoom)
        _targetProvider = State(initialValue: initialTargetProvider)
    }

    var sourceRoom: String? { model.sourceRoom(forSessionId: session.sessionId) }
    /// Every computer of the mesh, this one first: a Task can move to another
    /// agent here as well as to another machine.
    var targets: [LinkedComputer] {
        let all = model.connectionRegistry.connections
        return all.filter { $0.id == sourceRoom } + all.filter { $0.id != sourceRoom }
    }
    var staysHere: Bool { targetRoom == sourceRoom }
    /// The same agent on the same computer is not a move.
    var sameAgentHere: Bool {
        staysHere && AgentIdentity.normalize(targetProvider) == AgentIdentity.normalize(session.agent)
    }

    var body: some View {
        CompatNavigationStack {
            Form {
                Section {
                    Picker(L("Computer"), selection: $targetRoom) {
                        computerOptions
                    }
                    Picker(L("Agent"), selection: $targetProvider) {
                        agentOptions
                    }
                } header: {
                    Text(L("Destination"))
                } footer: {
                    Text(sameAgentHere
                         ? L("Choose another agent, or another computer: this is where the Task already is.")
                         : staysHere
                            ? L("The Task continues here with the other agent, in a worktree of its own from the last commit.")
                            : L("The other computer needs the commit: push the branch, or make sure it can fetch it."))
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
                Button(L("Prepare and hand off"), action: submitHandoff)
                .disabled(!isReady || sameAgentHere)
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

    /// Readiness for one concrete destination, so the button and the action
    /// that follows it can never disagree about what is being checked.
    func readinessChecks(room: String, provider: String) -> [HandoffReadinessCheck] {
        TaskHandoffReadiness.checks(
            session: session,
            snapshot: session.projectId.flatMap { model.meshSnapshots[$0] },
            destinationSelected: targets.contains { $0.id == room },
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
        readinessChecks(room: targetRoom, provider: targetProvider)
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
        ForEach(targets) { connection in
            Text(connection.id == sourceRoom
                 ? String(format: L("%@ (this computer)"), computerName(connection))
                 : computerName(connection)).tag(connection.id)
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

    func applyDefaults() {
        let defaults = defaultSelection
        targetRoom = defaults.room
        targetProvider = defaults.provider
    }

    func submitHandoff() {
        if performHandoff(targetRoom: targetRoom, targetProvider: targetProvider) { dismiss() }
    }

    /// Another computer when there is one, else this one with another agent.
    var defaultSelection: (room: String, provider: String) {
        let source = AgentIdentity.normalize(session.agent)
        let enabled = AgentIdentity.composeIds.filter {
            $0 != source && model.agentMeshPreferences.isProviderEnabled($0)
        }
        let preferred = source == "claude" ? "codex" : "claude"
        let provider = enabled.contains(preferred) ? preferred : enabled.first ?? ""
        let room = targets.first { $0.id != sourceRoom }?.id ?? targets.first?.id ?? ""
        return (room, provider)
    }

    @discardableResult
    func performHandoff(targetRoom: String, targetProvider: String) -> Bool {
        guard TaskHandoffReadiness.isReady(
                  readinessChecks(room: targetRoom, provider: targetProvider)
              ),
              let target = targets.first(where: { $0.id == targetRoom }) else { return false }
        let normalizedProvider = AgentIdentity.normalize(targetProvider)
        guard AgentIdentity.composeIds.contains(normalizedProvider),
              model.agentMeshPreferences.isProviderEnabled(normalizedProvider) else { return false }
        guard !(targetRoom == sourceRoom && normalizedProvider == AgentIdentity.normalize(session.agent)) else {
            return false
        }
        model.prepareTaskHandoff(
            session: session,
            targetProvider: normalizedProvider,
            targetComputer: computerName(target),
            checkpoint: checkpointUncommitted && hasUncommittedWork,
            push: pushBranch && targetRoom != sourceRoom
        )
        return true
    }

    func computerName(_ connection: LinkedComputer) -> String {
        let published = connection.lastMachineName.trimmingCharacters(in: .whitespacesAndNewlines)
        return published.isEmpty ? connection.displayName : published
    }
}
