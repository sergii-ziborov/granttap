import SwiftUI

/// A Task destination that exists even when no native session does.
struct TaskRoute: Identifiable, Hashable {
    let projectId: String
    let taskId: String
    var id: String { "\(projectId)\u{1f}\(taskId)" }
}

/// Task-first detail.
///
/// Data has been Task-first since Project Mesh shipped, but Needs You still
/// resolved to a native `SessionInfo` and silently did nothing when the current
/// owner was a Grok Bot actor, an offline computer, or a session this phone no
/// longer knows. The Task itself is the destination; what to do inside it is
/// decided from the current owner.
struct TaskRouteView: View {
    @Environment(\.dismiss) var dismiss
    let route: TaskRoute
    @ObservedObject var model: AppModel
    var onOpenSession: (SessionInfo) -> Void
    /// Presented as a sheet, this screen carries its own way out. Pushed onto a
    /// navigation stack it does not: the system already gives it a back button,
    /// and offering Done beside it is two exits from one screen.
    var presentedAsSheet: Bool = true
    @State var answerText = ""
    @State private var showReport = false
    /// A claim the person is about to release by their own authority.
    @State private var releasing: ProjectResourceClaim?

    var snapshot: ProjectMeshSnapshot? { model.meshSnapshots[route.projectId] }
    var task: ProjectMeshTask? { snapshot?.tasks.first { $0.taskId == route.taskId } }
    /// One row per chat: the same chat under two names of one computer is
    /// one execution, not two.
    var executions: [ExecutionSessionLink] {
        ExecutionCoalescing.coalesced((snapshot?.executions ?? []).filter { $0.taskId == route.taskId })
            .sorted { ($0.endedAt == nil ? 0 : 1) < ($1.endedAt == nil ? 0 : 1) }
    }
    var claims: [ProjectResourceClaim] {
        (snapshot?.claims ?? []).filter { $0.taskId == route.taskId }
    }

    /// Someone else's claim touching this Task's files or modules: the merge
    /// conflict that has not happened yet, shown while it can still be avoided.
    var neighbours: [(claim: ProjectResourceClaim, kind: TaskHandoffReadiness.OverlapKind)] {
        let mine = claims
        return (snapshot?.claims ?? [])
            .filter { $0.taskId != route.taskId }
            .compactMap { other in
                let kinds = mine.compactMap { TaskHandoffReadiness.overlapKind($0, other) }
                guard let kind = kinds.contains(.file) ? .file
                    : kinds.contains(.logicalFile) ? .logicalFile : kinds.first else { return nil }
                return (claim: other, kind: kind)
            }
    }
    var events: [ProjectMeshEvent] { model.meshEvents(forTaskId: route.taskId) }

    /// Another Task changing the far side of a contract this Task touches: the
    /// consumer of a topic it produces, the caller of an API it changes.
    var otherSide: [ProjectOtherSide.Row] {
        guard let snapshot else { return [] }
        return ProjectOtherSide.rows(in: snapshot, taskId: route.taskId)
    }

    var ownerExecution: ExecutionSessionLink? {
        guard let ownerSessionId = task?.ownerSessionId else { return nil }
        return executions.first { $0.sessionId == ownerSessionId }
    }

    /// The current owner may live in the bounded history after becoming idle.
    /// The Task stays current even when its native provider session does not.
    var localSession: SessionInfo? {
        guard let execution = ownerExecution, execution.endedAt == nil else { return nil }
        return session(for: execution)
    }

    func session(for execution: ExecutionSessionLink) -> SessionInfo? {
        let expected = model.resolvedSessionId(execution.sessionId)
        let pool = model.sessions + model.sessionHistory + Array(model.archivedSessions.values)
        return pool.first { $0.sessionId == execution.sessionId }
            ?? pool.first { model.resolvedSessionId($0.sessionId) == expected }
    }

    @discardableResult
    func openChat(for execution: ExecutionSessionLink) -> Bool {
        guard let chat = session(for: execution) else { return false }
        onOpenSession(chat)
        return true
    }

    var pendingQuestion: ProjectMeshEvent? {
        model.meshNeedsYouEvents.first {
            $0.taskId == route.taskId && $0.eventType == "AGENT_QUESTION"
        }
    }

    @ViewBuilder
    var contextCard: some View {
        if let snapshot {
            let card = TaskContextPresentation.card(
                task: task,
                snapshot: snapshot,
                events: events,
                invocations: model.invocationHistoryByTask[
                    AppModel.invocationTaskKey(route.projectId, route.taskId)
                ] ?? []
            )
            Section {
                if let revision = card.revision {
                    Text("\(L("Revision")) \(revision)").font(.caption)
                }
                Text(TaskContextPresentation.deliveryLabel(
                    offered: card.offered, issued: card.issued, confirmed: card.confirmed
                )).font(.caption).foregroundStyle(Theme.muted)
                if !card.sources.isEmpty {
                    Text(card.sources.joined(separator: " · ")).font(.caption)
                }
                ForEach(card.decisions, id: \.self) { decision in
                    Text(decision).font(.caption)
                }
                if !card.missing.isEmpty {
                    Text("\(L("Missing")) · \(card.missing.joined(separator: ", "))")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                Text(card.sizeLabel).font(.caption2).foregroundStyle(Theme.muted)
            } header: {
                Text(L("Context"))
            }
        }
    }

    /// Why a release of this claim was refused, when it was.
    @ViewBuilder
    private func releaseNotice(_ claim: ProjectResourceClaim) -> some View {
        if let notice = model.claimReleaseNotices[claim.claimId] {
            Text(String(format: L("Release refused: %@"), notice))
                .font(.caption).foregroundStyle(Theme.riskHigh)
                .accessibilityIdentifier("claim.release.refused.\(claim.claimId)")
        }
    }

    /// The person's override, offered on every claim: the computers, or the
    /// Project's owner when this phone is a member's, decide whether it applies.
    private func releaseButton(_ claim: ProjectResourceClaim) -> some View {
        Button(role: .destructive) {
            releasing = claim
        } label: {
            Label(L("Release claim…"), systemImage: "lock.open")
        }
        .accessibilityIdentifier("claim.release.\(claim.claimId)")
    }

    var body: some View {
        // Pushed, the surrounding stack owns the chrome; wrapping it in another
        // one is what produced a second title bar with its own exit.
        if presentedAsSheet {
            CompatNavigationStack { content }
        } else {
            content
        }
    }

    private var content: some View {
            List {
                Section {
                    Text(visibleTitle)
                        .font(.system(size: 17, weight: .semibold))
                    if let goal = task?.goal, goal != visibleTitle {
                        Text(goal).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    }
                    Text(stateLine).font(.caption).foregroundStyle(Theme.muted)
                }
                contextCard
                if let question = pendingQuestion { answerSection(question) }
                Section(L("Executions")) {
                    if executions.isEmpty {
                        Text(L("No execution is registered for this task yet."))
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                    ForEach(executions) { execution in
                        executionRow(execution)
                    }
                }
                runtimeSection
                if !claims.isEmpty {
                    Section {
                        ForEach(claims) { claim in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(claim.resource).font(.system(size: 13, design: .monospaced))
                                // A requested Edit may fail; the claim is early
                                // coordination evidence, never proof of a change.
                                Text(claim.mode == "intent" ? L("Edit requested") : L("Claimed"))
                                    .font(.caption).foregroundStyle(Theme.muted)
                                releaseNotice(claim)
                            }
                            .contextMenu { releaseButton(claim) }
                        }
                    } header: {
                        Text(L("Claims"))
                    } footer: {
                        Text(L("Touch and hold a claim to release it yourself, when the agent holding it is gone or stuck."))
                    }
                }
                if !neighbours.isEmpty {
                    Section {
                        ForEach(neighbours, id: \.claim.claimId) { item in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: item.kind == .file
                                      ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                                    .foregroundStyle(item.kind == .file ? Theme.riskHigh : Theme.riskMed)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.claim.resource)
                                        .font(.system(size: 13, design: .monospaced))
                                    Text(String(format: item.kind == .file
                                                ? L("%@ is editing the same file")
                                                : item.kind == .logicalFile
                                                    ? L("%@ is working on another checkout of this file")
                                                    : L("%@ is working in the same module"),
                                                item.claim.ownerSessionId))
                                        .font(.caption).foregroundStyle(Theme.muted)
                                    releaseNotice(item.claim)
                                }
                            }
                            .contextMenu { releaseButton(item.claim) }
                        }
                    } header: {
                        Text(L("Also being edited"))
                    } footer: {
                        Text(L("Seen before the merge would say so. Coordinate, or hand the task off."))
                    }
                }
                if !otherSide.isEmpty, let snapshot {
                    Section {
                        ForEach(otherSide) { row in
                            NavigationLink {
                                TaskRouteView(
                                    route: .init(projectId: route.projectId, taskId: row.taskId),
                                    model: model, onOpenSession: onOpenSession, presentedAsSheet: false
                                )
                            } label: {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                                        .foregroundStyle(Theme.riskMed)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(row.title)
                                        Text(ProjectOtherSide.describe(row, in: snapshot))
                                            .font(.caption).foregroundStyle(Theme.muted)
                                    }
                                }
                            }
                        }
                    } header: {
                        Text(L("Other side of this repository"))
                    } footer: {
                        Text(L("Another Task is changing the far side of a contract this Task touches."))
                    }
                }
                if !events.isEmpty {
                    Section(L("Timeline")) {
                        ForEach(events.suffix(24)) { event in
                            ProjectMeshTimelineRow(event: event)
                        }
                    }
                }
            }
            .navigationTitle(L("Task"))
            .onAppear {
                model.requestInvocationHistory(projectId: route.projectId, taskId: route.taskId)
            }
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                releasing.map { String(format: L("Release the claim on %@?"), $0.resource) } ?? "",
                isPresented: Binding(get: { releasing != nil }, set: { if !$0 { releasing = nil } }),
                titleVisibility: .visible
            ) {
                Button(L("Release claim"), role: .destructive) {
                    if let claim = releasing {
                        model.releaseClaimByPerson(projectId: route.projectId, claimId: claim.claimId, reason: L("Released from the phone"))
                    }
                    releasing = nil
                }
            } message: {
                if let claim = releasing {
                    Text(String(format: L("Held by %@. Releasing it lets other agents edit the file; the holder is not asked. Do this when the holder is gone or stuck. Each computer writes down that you did."), claim.ownerSessionId))
                }
            }
            .sheet(isPresented: $showReport) {
                if let task, let snapshot {
                    ReportExportSheet(report: model.report(for: .task(snapshot, task)))
                }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if task != nil, snapshot != nil {
                        Button {
                            showReport = true
                        } label: {
                            Image(systemName: "doc.text")
                        }
                        .accessibilityLabel(L("Report (PDF or CSV)…"))
                        .accessibilityIdentifier("task.report")
                    }
                }
                // The condition lives inside the item, not around it: a
                // conditional toolbar item needs iOS 16, and the app runs on 15.
                ToolbarItem(placement: .confirmationAction) {
                    if presentedAsSheet {
                        Button(L("Done")) { dismiss() }
                    }
                }
            }
    }
}
