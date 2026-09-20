import Foundation

struct ProjectMeshProject: Codable, Equatable, Identifiable {
    let projectId: String
    let name: String
    var repositoryRoot: String?
    let canonicalRepositoryId: String
    var baseRemote: String?
    let createdAt: Double
    var id: String { projectId }
}

struct ProjectBindingSummary: Codable, Equatable, Identifiable {
    let bindingId: String
    let projectId: String
    let endpointId: String
    let repositoryId: String
    let displayName: String
    var localPathHint: String? = nil
    let available: Bool
    var revision: String? = nil
    var id: String { bindingId }
}

struct ProjectMeshTask: Codable, Equatable, Identifiable {
    let taskId: String
    let projectId: String
    var title: String
    var goal: String
    var state: String
    var ownerSessionId: String?
    /// Raised by every writer, so a delayed snapshot or a replayed event cannot
    /// restore an older owner or reopen finished work. Absent means a
    /// pre-revision publisher and reads as zero.
    var revision: Double? = nil
    let createdAt: Double
    var updatedAt: Double
    var id: String { taskId }
}

struct ExecutionSessionLink: Codable, Equatable, Identifiable {
    var taskId: String
    let sessionId: String
    let provider: String
    var actorId: String? = nil
    let computerId: String
    let workspace: String
    /// The repository the workspace belongs to, by canonical id.
    var repositoryId: String? = nil
    var branch: String?
    var worktree: String?
    /// Uncommitted work cannot travel inside a Task Capsule; the owning
    /// computer publishes whether this execution currently has any.
    var uncommitted: Bool? = nil
    /// When the owning computer last observed these facts.
    var updatedAt: Double? = nil
    /// When the chat itself last did anything, as the computer saw it.
    var activeAt: Double? = nil
    let startedAt: Double
    var endedAt: Double?
    var id: String { "\(computerId)\u{1f}\(provider)\u{1f}\(sessionId)" }

    /// The last moment this execution is known to have been alive.
    var lastSeenAt: Double { endedAt ?? activeAt ?? updatedAt ?? startedAt }
}

struct ProjectResourceClaim: Codable, Equatable, Identifiable {
    let claimId: String
    let projectId: String
    var taskId: String
    let ownerSessionId: String
    var repositoryId: String? = nil
    var endpointId: String? = nil
    var worktree: String? = nil
    let resource: String
    let mode: String
    let createdAt: Double
    let expiresAt: Double
    var id: String { claimId }
}

struct ProjectTaskDependency: Codable, Equatable, Identifiable {
    var taskId: String
    let dependsOnTaskId: String
    var summary: String?
    let createdAt: Double
    var id: String { "\(taskId)\u{1f}\(dependsOnTaskId)" }
}

struct TaskCapsule: Codable, Equatable {
    let taskId: String
    let goal: String
    let currentStatus: String
    let sourceProvider: String
    var sourceActorId: String? = nil
    let sourceComputer: String
    let targetProvider: String
    var targetActorId: String? = nil
    let targetComputer: String
    let repository: String
    let baseSha: String
    var branch: String?
    var latestCommit: String?
    var dirtyDiffHash: String?
    /// "clean", "dirty", or "unknown" — a probe that failed is never clean.
    var workingTree: String?
    let filesChanged: [String]
    var testsStatus: String?
    let dependencies: [String]
    let resourceClaims: [String]
    let remainingWork: [String]
    let importantDecisions: [String]
    /// What the checkpoint commit holds, when the capsule rides on one.
    var checkpoint: CapsuleCheckpoint? = nil
    let createdAt: Double
}

/// A checkpoint's own account of itself: complete, partial (secrets stayed
/// on the source computer, named in `excluded`), or requires_review (the
/// checkout was shared with other work, so the commit may carry changes
/// that are not this Task's).
struct CapsuleCheckpoint: Codable, Equatable {
    let status: String
    let files: Int
    let excluded: [String]

    static let statuses: Set<String> = ["complete", "partial", "requires_review"]

    var isComplete: Bool { status == "complete" }

    var summary: String {
        switch status {
        case "complete": return LPlural(files, one: "Checkpoint: %d file", many: "Checkpoint: %d files")
        case "partial":
            return String(format: L("Checkpoint is partial: %@ stayed on the source computer"), excluded.joined(separator: ", "))
        default: return L("Checkpoint needs review: the checkout was shared with other work")
        }
    }
}

struct ProjectHandoffReceipt: Codable, Equatable {
    let sourceSessionId: String
    var sourceActorId: String? = nil
    let targetSessionId: String
    let taskId: String
    let capsuleHash: String
    let acceptedAt: Double
}

struct ProjectMeshEventPayload: Codable, Equatable {
    var summary: String? = nil
    var dependsOnTaskId: String? = nil
    var question: String? = nil
    var category: String? = nil
    var questionEventId: String? = nil
    var answer: String? = nil
    var capsule: TaskCapsule? = nil
    var receipt: ProjectHandoffReceipt? = nil
    var reason: String? = nil
    var claim: ProjectResourceClaim? = nil
    var claimId: String? = nil
    var resource: String? = nil
    var artifact: String? = nil
    var commitSha: String? = nil
    var otherOwnerSessionId: String? = nil
    var resolved: Bool? = nil
    var needsUser: Bool? = nil
    var failed: Bool? = nil
}

struct ProjectMeshEvent: Codable, Equatable, Identifiable {
    let type: String
    let sessionId: String
    let eventId: String
    let projectId: String
    var taskId: String
    let sourceSessionId: String
    var sourceActorId: String? = nil
    var targetSessionId: String?
    let eventType: String
    let createdAt: Double
    var expiresAt: Double?
    let payload: ProjectMeshEventPayload
    var id: String { eventId }
}

/// One edge of the integration map a bound repository keeps in its
/// `WEAVATRIX.md`: the repository on the far side of a database, a topic, or an
/// API, as that repository states it.
struct ProjectIntegrationPeer: Codable, Equatable, Identifiable {
    let projectId: String
    let repositoryId: String
    let peer: String
    let via: String
    let relation: String
    var through: String? = nil
    let updatedAt: Double
    var id: String {
        [projectId, repositoryId, peer, via, relation, through ?? ""].joined(separator: "\u{1f}")
    }
}

/// A skill the Project catalog published. Presence here is not permission;
/// Governance is the only authority for what may run.
struct SharedSkill: Codable, Equatable, Identifiable {
    let name: String
    var description: String? = nil
    var version: String? = nil
    var digest: String? = nil
    var source: String? = nil
    /// installed | available | used | unknown
    var state: String? = nil
    var id: String { name }
}

struct AdvertisedModel: Codable, Equatable, Identifiable {
    let modelId: String
    let provider: String
    let endpointId: String
    let source: String
    var label: String? = nil
    let observedAt: Double
    var id: String { "\(endpointId)\u{1f}\(provider)\u{1f}\(modelId)" }
}

struct EndpointModelCatalog: Codable, Equatable, Identifiable {
    let endpointId: String
    let observedAt: Double
    var stale: Bool? = nil
    var models: [AdvertisedModel]
    var reason: String? = nil
    var id: String { endpointId }
}

struct ProjectMeshSnapshot: Codable, Equatable, Identifiable {
    let type: String
    let sessionId: String
    let projectId: String
    let project: ProjectMeshProject
    var bindings: [ProjectBindingSummary]? = nil
    var peers: [ProjectIntegrationPeer]? = nil
    var skills: [SharedSkill]? = nil
    var incomplete: Bool? = nil
    var execution: ProjectExecutionPolicy? = nil
    var restrictions: ProjectRestrictionSet? = nil
    var environment: ProjectEnvironment? = nil
    var modelCatalog: [EndpointModelCatalog]? = nil
    var tasks: [ProjectMeshTask]
    var executions: [ExecutionSessionLink]
    var claims: [ProjectResourceClaim]
    var dependencies: [ProjectTaskDependency]
    var events: [ProjectMeshEvent]
    let generatedAt: Double
    var id: String { projectId }
}

/// The person's own release of a claim: not an owner's event, which only an
/// owner may make, but the person's authority over a claim an agent died
/// holding or will not let go. Sent to each computer of the Project under
/// the Project's key; each writes down that it was used.
struct MeshClaimRelease: Codable, Equatable {
    let type: String
    let sessionId: String
    let projectId: String
    let claimId: String
    var reason: String? = nil
    var requestId: String? = nil
    let createdAt: Double

    var isWellFormed: Bool {
        type == "mesh.claim.release" && sessionId == projectId && !projectId.isEmpty && projectId.count <= 128
            && !claimId.isEmpty && claimId.count <= 128 && (reason.map { !$0.isEmpty && $0.count <= 1_000 } ?? true)
    }
}

/// What became of a release: done, or refused and why. A computer answers
/// the phone that asked; the phone that shares a Project answers the member
/// who asked through it.
struct MeshClaimReleaseResult: Codable, Equatable {
    let type: String
    let sessionId: String
    let projectId: String
    let claimId: String
    let ok: Bool
    var reason: String? = nil
    var detail: String? = nil
    var requestId: String? = nil
    let generatedAt: Double

    static let reasons: Set<String> = ["unknown_claim", "other_project", "not_allowed", "no_computer"]

    var isWellFormed: Bool {
        type == "mesh.claim.release.result" && sessionId == projectId && !projectId.isEmpty
            && !claimId.isEmpty && claimId.count <= 128
            && (ok || reason.map { Self.reasons.contains($0) } ?? false)
            && (detail.map { !$0.isEmpty && $0.count <= 1_000 } ?? true)
    }

    /// Why, in the person's words.
    var message: String {
        if let detail, !detail.isEmpty { return detail }
        switch reason {
        case "unknown_claim": return L("No such claim on that computer; it may already be gone.")
        case "other_project": return L("That claim belongs to another Project.")
        case "not_allowed": return L("Only an admin of this Project may release a claim.")
        case "no_computer": return L("No computer of the Project's owner is reachable right now.")
        default: return ok ? L("Released.") : L("The release was refused.")
        }
    }
}

struct ProjectMeshHandoffPrepare: Codable, Equatable {
    let type: String
    let sessionId: String
    let projectId: String
    let taskId: String
    let targetProvider: String
    var targetActorId: String? = nil
    let targetComputer: String
    let createdAt: Double
    /// Commit uncommitted work to a checkpoint branch on the source computer
    /// first. Local unless `push` is asked for as well.
    var checkpoint: Bool? = nil
    /// Publish the branch to the repository's remote before the capsule leaves,
    /// so another computer can fetch the commit. Never a force push.
    var push: Bool? = nil
}
