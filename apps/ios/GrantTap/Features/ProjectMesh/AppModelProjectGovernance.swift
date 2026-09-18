import Foundation

extension AppModel {
    func receive(_ status: ProjectPolicyStatus, fromRoom room: String) {
        guard agentMeshPreferences.meshEnabled,
              ProjectGovernanceWireValidator.validStatus(status) else { return }
        meshProjectSourceRooms[status.projectId, default: []].insert(room)
        guard let merged = ProjectGovernanceLogic.merged(
            current: projectGovernance[status.projectId], status: status
        ) else { return }
        projectGovernance[status.projectId] = merged
        if let pending = pendingProjectPolicyRevisions[status.projectId],
           status.policy.revision >= pending {
            pendingProjectPolicyRevisions.removeValue(forKey: status.projectId)
        }
        if let delivered = deliveredProjectPolicyRevisions[status.projectId],
           status.policy.revision >= delivered {
            deliveredProjectPolicyRevisions.removeValue(forKey: status.projectId)
        }
        // A draft that the saved policy now says is in force has served its
        // purpose. One that still differs is kept: it is the edit someone is
        // waiting on, and reloading over it is how it used to be lost.
        if let draft = projectPolicyDrafts[status.projectId],
           !draft.differs(from: merged.policy, enforcement: merged.enforcement) {
            projectPolicyDrafts.removeValue(forKey: status.projectId)
        }
        projectPolicyErrors.removeValue(forKey: status.projectId)
        ProjectGovernancePersistence.save(projectGovernance)
        forwardGovernanceStatusToMembers(status, fromRoom: room)
    }

    /// The computer refused the edit. The draft stays — it is what the person
    /// wants — and the reason is said where Save was tapped; when the computer
    /// also says which revision it holds, the next Save builds on that.
    func receive(_ rejected: ProjectPolicyRejected, fromRoom room: String) {
        guard agentMeshPreferences.meshEnabled,
              ProjectGovernanceWireValidator.validRejected(rejected) else { return }
        meshProjectSourceRooms[rejected.projectId, default: []].insert(room)
        if handOffRejectionToMember(rejected) { return }
        pendingProjectPolicyRevisions.removeValue(forKey: rejected.projectId)
        deliveredProjectPolicyRevisions.removeValue(forKey: rejected.projectId)
        projectPolicyErrors[rejected.projectId] = Self.rejectionMessage(rejected)
    }

    static func rejectionMessage(_ rejected: ProjectPolicyRejected) -> String {
        switch rejected.reason {
        case "revision_mismatch":
            if let current = rejected.currentRevision {
                return String(format: L("The computer holds revision %d, not %d. Your edit is kept; Save again to apply it on top."), current, rejected.expectedRevision)
            }
            return L("The computer holds a different revision. Your edit is kept; Save again to apply it on top.")
        case "engine_unavailable":
            return L("The computer could not reach its policy engine. Your edit is kept; try again once GrantTap on that computer is running.")
        case "invalid_policy":
            return L("The computer refused the policy as invalid. Your edit is kept.")
        default:
            return L("The computer did not apply the edit. Your edit is kept.")
        }
    }

    func receive(_ ack: ProjectPolicyAck, fromRoom room: String) {
        guard agentMeshPreferences.meshEnabled,
              ProjectGovernanceWireValidator.validAck(ack) else { return }
        meshProjectSourceRooms[ack.projectId, default: []].insert(room)
        guard let merged = ProjectGovernanceLogic.merged(
            current: projectGovernance[ack.projectId], ack: ack
        ) else { return }
        projectGovernance[ack.projectId] = merged
        ProjectGovernancePersistence.save(projectGovernance)
    }

    @discardableResult
    func applyProjectGovernance(
        projectId: String, enforcement: ProjectEnforcementMode,
        defaults: [ProjectCapabilityKind: ProjectPolicyEffect],
        named: [ProjectGovernanceLogic.NamedRule: ProjectPolicyEffect] = [:]
    ) -> Bool {
        guard agentMeshPreferences.meshEnabled, let current = projectGovernance[projectId] else {
            projectPolicyErrors[projectId] = L("Refresh Project policy before editing.")
            return false
        }
        // A Project with no policy yet is the one that needs a first one
        // written. Requiring an existing policy to write one refused exactly
        // the case the editor exists for; `updatedPolicy` already starts from
        // revision zero when there is nothing to build on.
        let canonical = current.policy
        // Computers apply a policy; a member's phone only hears about it.
        let rooms = computerRooms(for: projectId)
        guard !rooms.isEmpty else {
            projectPolicyErrors[projectId] = L(
                "No linked Project computer is ready to receive policy."
            )
            return false
        }
        let policy = ProjectGovernanceLogic.updatedPolicy(
            current: canonical, projectId: projectId, enforcement: enforcement,
            defaults: defaults, named: named, createdBy: "granttap-phone"
        )
        let request = ProjectPolicySet(
            type: "project.policy.set", sessionId: projectId, projectId: projectId,
            expectedRevision: canonical?.revision ?? 0, policy: policy,
            // Named, so the answer to this edit is told from another's of the
            // same revision when two phones edit through one hub at once.
            requestId: UUID().uuidString.lowercased(),
            createdAt: Date().timeIntervalSince1970 * 1_000
        )
        guard ProjectGovernanceWireValidator.validSet(request) else {
            projectPolicyErrors[projectId] = L("Policy update could not be delivered.")
            return false
        }
        pendingProjectPolicyRevisions[projectId] = policy.revision
        projectPolicyErrors.removeValue(forKey: projectId)
        // The edit is kept until it is seen applied. Leaving the screen before
        // the computers have read their mailbox used to discard it.
        projectPolicyDrafts[projectId] = ProjectGovernanceDraft(
            enforcement: enforcement, defaults: defaults, named: named
        )
        // Written down before anything is sent. A room that is not listening
        // now is retried when it comes back, rather than skipped for good.
        // Anything not newer for this Project is superseded outright: a computer
        // applying both in order would end on the policy that was replaced.
        // Two edits made before the computers confirm the first both target the
        // same revision, so the same revision counts as superseded too — or the
        // outbox would hold two entries under one id.
        projectPolicyOutbox = projectPolicyOutbox.filter {
            $0.projectId != projectId || $0.revision > policy.revision
        } + ProjectPolicyOutboxLogic.entries(
            for: request, rooms: rooms, at: Date().timeIntervalSince1970 * 1_000
        )
        ProjectPolicyOutboxStore.save(projectPolicyOutbox)
        pendingProjectPolicyRevisions.removeValue(forKey: projectId)
        deliveredProjectPolicyRevisions[projectId] = policy.revision
        flushProjectPolicyOutbox()
        return true
    }

    @discardableResult
    func applyProjectExecution(
        projectId: String,
        mode: ProjectExecutionMode,
        targetEndpointId: String?,
        offlineBehavior: ExecutionOfflineBehavior
    ) -> Bool {
        guard agentMeshPreferences.meshEnabled, let current = projectGovernance[projectId] else {
            projectPolicyErrors[projectId] = L("Refresh Project policy before editing.")
            return false
        }
        let rooms = computerRooms(for: projectId)
        guard !rooms.isEmpty else {
            projectPolicyErrors[projectId] = L("No linked Project computer is ready to receive policy.")
            return false
        }
        var policy = current.policy ?? ProjectPolicy(
            projectId: projectId, revision: 1, enforcement: current.enforcement, rules: []
        )
        policy.revision += current.policy == nil ? 0 : 1
        if current.policy == nil { policy.revision = 1 }
        policy.execution = ProjectExecutionPolicy(
            mode: mode,
            targetEndpointId: mode == .pinned ? targetEndpointId : nil,
            revision: policy.revision,
            hostGrantStatus: mode == .pinned ? .pending : .none,
            offlineBehavior: offlineBehavior
        )
        let request = ProjectPolicySet(
            type: "project.policy.set", sessionId: projectId, projectId: projectId,
            expectedRevision: current.policy?.revision ?? 0, policy: policy,
            requestId: UUID().uuidString.lowercased(),
            createdAt: Date().timeIntervalSince1970 * 1_000
        )
        guard ProjectGovernanceWireValidator.validSet(request) else {
            projectPolicyErrors[projectId] = L("Policy update could not be delivered.")
            return false
        }
        projectPolicyErrors.removeValue(forKey: projectId)
        projectPolicyOutbox = projectPolicyOutbox.filter {
            $0.projectId != projectId || $0.revision > policy.revision
        } + ProjectPolicyOutboxLogic.entries(
            for: request, rooms: rooms, at: Date().timeIntervalSince1970 * 1_000
        )
        ProjectPolicyOutboxStore.save(projectPolicyOutbox)
        deliveredProjectPolicyRevisions[projectId] = policy.revision
        flushProjectPolicyOutbox()
        return true
    }

    /// Hand the relay every Governance edit it can take right now.
    ///
    /// Called after an edit and whenever a Project room comes back up. The
    /// relay keeps what it accepts for a day, so a computer collects the policy
    /// when it next reads its mailbox — which is what makes this a Project
    /// decision rather than one machine's.
    func flushProjectPolicyOutbox() {
        let now = Date().timeIntervalSince1970 * 1_000
        let pending = ProjectPolicyOutboxLogic.pending(projectPolicyOutbox, at: now)
        guard !pending.isEmpty else {
            if !projectPolicyOutbox.isEmpty {
                projectPolicyOutbox = []
                ProjectPolicyOutboxStore.save(projectPolicyOutbox)
            }
            return
        }
        for entry in pending {
            guard let relay = relaysByRoom[entry.room] else { continue }
            relay.sendSession(
                payload: entry.request, sessionId: entry.projectId, ttl: 24 * 60 * 60,
                deliveryId: "project-policy-\(entry.projectId)-\(entry.revision)"
            ) { [weak self] error in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if error != nil {
                        // Left in the outbox: the next time this room is up it
                        // is offered again.
                        self.projectPolicyErrors[entry.projectId] = L(
                            "Policy update could not be delivered."
                        )
                        return
                    }
                    self.projectPolicyOutbox = ProjectPolicyOutboxLogic.settled(
                        self.projectPolicyOutbox, delivered: entry
                    )
                    ProjectPolicyOutboxStore.save(self.projectPolicyOutbox)
                    self.projectPolicyErrors.removeValue(forKey: entry.projectId)
                }
            }
        }
    }
}
