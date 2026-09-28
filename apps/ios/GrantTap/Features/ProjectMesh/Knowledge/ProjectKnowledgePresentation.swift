import CryptoKit
import Foundation

enum ProjectKnowledgePresentation {
    struct Revision: Identifiable, Equatable {
        let id: String
        let repositoryId: String
        let name: String
        let commitSha: String
        let hasGraph: Bool
    }

    struct Entry: Identifiable, Equatable {
        let id: String
        let text: String
        let source: String
        let taskId: String
        let repositoryId: String?
        let commitSha: String?
        let revision: String?
        let hasGraph: Bool
    }

    struct Summary: Equatable {
        let decisions: [Entry]
        let attempts: [Entry]
        let results: [Entry]
        let packets: [ProjectCortexIntegration]
        let revisions: [Revision]
        let freshness: Double

        var rowDetail: String {
            let counts = [
                decisions.isEmpty ? nil : LPlural(decisions.count, one: "%d decision", many: "%d decisions"),
                attempts.isEmpty ? nil : LPlural(attempts.count, one: "%d attempt", many: "%d attempts"),
                results.isEmpty ? nil : LPlural(results.count, one: "%d result", many: "%d results")
            ].compactMap { $0 }
            return counts.isEmpty ? L("Mesh evidence and context status") : counts.joined(separator: " · ")
        }
    }

    static func invocations(
        _ history: [String: [ProjectInvocationRecord]], snapshot: ProjectMeshSnapshot
    ) -> [ProjectInvocationRecord] {
        snapshot.tasks.flatMap { task in
            history["\(snapshot.projectId)\u{1f}\(task.taskId)"] ?? []
        }
        .sorted { left, right in
            left.event.occurred_at == right.event.occurred_at
                ? left.id < right.id : left.event.occurred_at > right.event.occurred_at
        }
    }

    static func summary(
        snapshot: ProjectMeshSnapshot, invocations: [ProjectInvocationRecord]
    ) -> Summary {
        let graphIds = Set((snapshot.repositoryGraphs ?? []).map(\.repositoryId))
        let durable = (snapshot.knowledge ?? []).map { record -> Entry in
            Entry(id: "memory:\(record.id)", text: record.content,
                  source: knowledgeSource(record.source), taskId: record.taskId,
                  repositoryId: record.repositoryId, commitSha: commit(record.commitSha),
                  revision: nil, hasGraph: record.repositoryId.map(graphIds.contains) == true)
        }
        let memoryRefs = Set((snapshot.knowledge ?? []).map(\.sourceRef))
        let correctedIds = Set(snapshot.supersededKnowledgeRecordIds ?? [])
        var seenDecisions = Set<String>()
        let decisions = snapshot.events.flatMap { event -> [Entry] in
            guard !memoryRefs.contains(event.eventId) else { return [] }
            guard let capsule = event.payload.capsule else { return [] }
            let repositoryId = repositoryId(for: event, snapshot: snapshot)
            let sha = commit(capsule.latestCommit) ?? commit(capsule.baseSha)
            return capsule.importantDecisions.enumerated().compactMap { index, value in
                let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !clean.isEmpty,
                      capsuleRecordId(event.eventId, index: index)
                        .map({ !correctedIds.contains($0) }) ?? false,
                      seenDecisions.insert("\(event.taskId)\u{1f}\(clean)").inserted else {
                    return nil
                }
                return Entry(
                    id: "decision:\(event.eventId):\(index)", text: clean,
                    source: L("Task capsule"), taskId: event.taskId,
                    repositoryId: repositoryId, commitSha: sha, revision: nil,
                    hasGraph: repositoryId.map(graphIds.contains) == true
                )
            }
        }
        let callAttempts = invocations.prefix(32).map { record -> Entry in
            let call = record.event
            let repositoryId = call.repository_id
            return Entry(
                id: "invocation:\(record.id)",
                text: [call.tool_name, phaseLabel(call.phase), sourceLabel(call.source)]
                    .joined(separator: " · "),
                source: L("Invocation history"), taskId: call.task_id,
                repositoryId: repositoryId, commitSha: nil, revision: call.revision,
                hasGraph: repositoryId.map(graphIds.contains) == true
            )
        }
        let wrongTurns = snapshot.events.compactMap { event -> Entry? in
            guard !memoryRefs.contains(event.eventId), !correctedIds.contains(event.eventId)
            else { return nil }
            guard ReportBuilder.wrongTurnEventTypes.contains(event.eventType) else { return nil }
            let detail = event.payload.summary ?? event.payload.reason ?? ""
            let repositoryId = repositoryId(for: event, snapshot: snapshot)
            return Entry(
                id: "event:\(event.eventId)",
                text: [ReportBuilder.meshLabel(event.eventType), detail]
                    .filter { !$0.isEmpty }.joined(separator: " · "),
                source: L("Mesh event"), taskId: event.taskId,
                repositoryId: repositoryId,
                commitSha: commit(event.payload.commitSha), revision: nil,
                hasGraph: repositoryId.map(graphIds.contains) == true
            )
        }
        var seenRevisions = Set<String>()
        let revisions = (snapshot.bindings ?? []).compactMap { binding -> Revision? in
            guard let sha = commit(binding.revision) else { return nil }
            let id = "\(binding.repositoryId):\(sha)"
            guard seenRevisions.insert(id).inserted else { return nil }
            return Revision(id: id, repositoryId: binding.repositoryId,
                            name: binding.displayName, commitSha: sha,
                            hasGraph: graphIds.contains(binding.repositoryId))
        }.sorted { $0.name == $1.name ? $0.commitSha < $1.commitSha : $0.name < $1.name }
        return Summary(
            decisions: Array((durableFor("decision", snapshot: snapshot, entries: durable)
                              + decisions).prefix(16)),
            attempts: Array((durableFor("attempt", snapshot: snapshot, entries: durable)
                             + callAttempts + wrongTurns).prefix(32)),
            results: Array(durableFor("result", snapshot: snapshot, entries: durable).prefix(16)),
            packets: (snapshot.cortex ?? []).filter { $0.packet != nil }
                .sorted { $0.endpointId < $1.endpointId },
            revisions: Array(revisions.prefix(32)),
            freshness: max(snapshot.generatedAt,
                           max(invocations.map(\.event.occurred_at).max() ?? 0,
                               (snapshot.knowledge ?? []).map(\.recordedAt).max() ?? 0))
        )
    }

    private static func durableFor(
        _ category: String, snapshot: ProjectMeshSnapshot, entries: [Entry]
    ) -> [Entry] {
        zip(snapshot.knowledge ?? [], entries).filter { $0.0.category == category }.map { $0.1 }
    }

    private static func knowledgeSource(_ value: String) -> String {
        switch value {
        case "task_capsule": return L("Task capsule")
        case "observed_invocation": return L("Observed call")
        case "user_decision": return L("Mesh decision")
        default: return L("Agent report")
        }
    }

    private static func repositoryId(
        for event: ProjectMeshEvent, snapshot: ProjectMeshSnapshot
    ) -> String? {
        let bound = Set((snapshot.bindings ?? []).map(\.repositoryId)
            + [snapshot.project.canonicalRepositoryId])
        if let repository = event.payload.capsule?.repository, bound.contains(repository) {
            return repository
        }
        return snapshot.executions.first {
            $0.taskId == event.taskId && $0.sessionId == event.sourceSessionId
        }?.repositoryId
    }

    private static func commit(_ value: String?) -> String? {
        guard let value, (7...64).contains(value.count),
              value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) })
        else { return nil }
        return value
    }

    private static func capsuleRecordId(_ eventId: String, index: Int) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: [eventId, index]) else { return nil }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "capsule-\(digest)"
    }

    static func phaseLabel(_ phase: String) -> String {
        switch phase {
        case "requested": return L("Requested")
        case "reported_success": return L("Reported success")
        case "reported_failure": return L("Reported failure")
        case "reported_unknown": return L("Outcome unknown")
        case "denied": return L("Denied")
        case "change_observed": return L("Change verified")
        case "source_gap": return L("History gap")
        default: return L("Unknown")
        }
    }

    static func sourceLabel(_ source: String) -> String {
        switch source {
        case "transcript": return L("Agent transcript")
        case "hook": return L("Computer hook")
        case "filesystem": return L("Filesystem")
        case "scanner": return L("Scanner")
        default: return source
        }
    }
}
