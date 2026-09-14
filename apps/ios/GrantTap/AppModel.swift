import Foundation
import Combine
import UIKit

/// App-wide state + orchestration. Owns the relay connection and the list of
/// pending approvals, and is reachable from the notification delegate so a tap
/// on the watch can resolve a request.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()
    private static let restoredMesh = ProjectMeshPersistence.load()
    private static let restoredGovernance = ProjectGovernancePersistence.load()
    // Read once per process, before anything in it writes: an edit made by one
    // model must not surface in another model of the same process.
    private static let restoredDrafts = ProjectGovernanceDraftStore.load()

    @Published var pairing: Pairing? = nil
    /// All linked Mac/PC rooms (3–4+ is normal). Preferred drives chat catalog.
    @Published var connectionRegistry: ConnectionRegistry = .empty
    @Published var demoMode = false
    @Published var connected = false
    /// Offline grace — brief WS blips must not flicker the Connected pill.
    var connectedDebounceTask: Task<Void, Never>?
    @Published var pending: [ApprovalRequest] = []
    /// requestId → submitted decision. The card remains until the machine
    /// confirms with approval.resolved (or cancels it).
    @Published var approvalDecisionsInFlight: [String: String] = [:]
    /// Normalized session scope captured when a decision is submitted. Empty
    /// means the original request was intentionally unscoped.
    var approvalDecisionSessionScope: [String: String] = [:]
    @Published var questions: [AgentEvent] = []
    @Published var log: [String] = []
    @Published var sessions: [SessionInfo] = []
    @Published var sessionHistory: [SessionInfo] = []
    /// Restored from disk: a reopened chat shows what the phone already has
    /// instead of waiting on the Mac to re-send and decrypt it.
    @Published var activities: [String: SessionActivity] = SessionActivityPersistence.load()
    @Published var agentIntegrations: [AgentIntegrationInfo] = []
    /// The same, per computer: a tool lives on one machine, and so does its update.
    @Published var agentIntegrationsByRoom: [String: [AgentIntegrationInfo]] = [:]
    @Published var toolUpdates: [String: ToolUpdateProgress] = [:]
    @Published var tokensRecent: Int = 0
    @Published var tokenWindowHours: Int = 12
    @Published var machineName: String = ""
    @Published var gatingEnabled: Bool = true
    @Published var excludedSessions: [String] = []
    @Published var autoAcceptDefault: String = "except_push"
    @Published var autoAcceptBySession: [String: String] = [:]
    @Published var autoAcceptPaused: Bool = false
    @Published var globalMcpDisabled: Set<String> = []
    @Published var globalSkillsDisabled: Set<String> = []
    @Published var globalShellDisabled: Bool = false
    @Published var sessionToOpen: String?
    /// Notification tap / remote wake — surface this Allow on the home pending list.
    @Published var focusedApprovalId: String?
    @Published var deliveries: [OutgoingDelivery] = DeliveryPersistence.load()
    @Published var archivedSessionIds: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: "granttap.archived-sessions") ?? []
    )
    @Published var archivedSessions: [String: SessionInfo] = ArchivedSessionPersistence.load()
    @Published var compactingSessions: Set<String> = []
    @Published var compactResults: [String: SessionCompactResult] = [:]
    /// Attachments already on their way to a computer, by the draft they came from.
    @Published var attachmentUploads: [UUID: AttachmentUpload] = [:]
    /// Chats whose pause or resume is on its way to the computer.
    @Published var sessionControlPending: Set<String> = []
    @Published var sessionControlResults: [String: SessionControlResult] = [:]
    /// Short status under the Sessions header after pull-to-refresh / tap refresh.
    @Published var refreshHint: String?
    @Published var meshSnapshots: [String: ProjectMeshSnapshot] = restoredMesh.snapshots
    /// Bounded phone projection only. The endpoint engine owns canonical policy.
    @Published var projectGovernance: [String: ProjectGovernanceProjection] = restoredGovernance
    @Published var pendingProjectPolicyRevisions: [String: Int] = [:]
    @Published var projectPolicyErrors: [String: String] = [:]
    /// A Governance edit the relay has taken, per Project, by revision.
    ///
    /// The computers apply it when they next read their mailbox, and say so
    /// through coverage. Waiting for one of them to echo the policy back before
    /// calling the edit saved made a Project-wide decision hostage to whichever
    /// machine happened to be awake.
    @Published var deliveredProjectPolicyRevisions: [String: Int] = [:]
    /// What someone typed into Governance but has not yet seen applied.
    ///
    /// Reloading the screen from the saved policy threw the edit away whenever
    /// it had not landed, which is exactly when it was still needed.
    @Published var projectPolicyDrafts: [String: ProjectGovernanceDraft] = restoredDrafts {
        didSet { if projectPolicyDrafts != oldValue { ProjectGovernanceDraftStore.save(projectPolicyDrafts) } }
    }
    /// Governance edits still to be handed to the relay, per Project room.
    ///
    /// A computer that was asleep when a policy was written used to miss it
    /// outright: the send went to whichever rooms happened to be connected and
    /// was never retried. A Project decision is not one machine's business.
    var projectPolicyOutbox: [ProjectPolicyOutboxEntry] = ProjectPolicyOutboxStore.load()
    /// This phone's own word on each Project: its name here, whether it shows.
    @Published var projectPreferences: [String: ProjectPreference] = ProjectPreferencesStore.load() {
        didSet { if projectPreferences != oldValue { ProjectPreferencesStore.save(projectPreferences) } }
    }
    @Published var pendingMeshEvents: [ProjectMeshEvent] = restoredMesh.pendingEvents
    @Published var meshAttentionStates: [String: ProjectMeshAttentionState] = restoredMesh.attentionStates
    @Published var agentMeshPreferences: AgentMeshPreferences = AgentMeshPreferencesStore.load()
    @Published var grokBotConnection: GrokBotEndpointConnection? = GrokBotEndpointStore.load()

    /// Latest measured load per linked computer. Runtime-only: a stale reading
    /// would misattribute a spike that has already passed.
    @Published var machineLoadByRoom: [String: MachineLoad] = [:]
    /// The last hour of readings per computer, kept across launches.
    @Published var machineLoadHistoryByRoom: [String: [LoadHistoryPoint]] = [:]

    /// Answer settings, kept per provider and per chat rather than as one
    /// shared pair: models differ between agents, and a chat's own choice must
    /// outlive the screen that made it.
    @Published var turnOverrides = TurnOverrideStore()
    // Shared across AppModel extensions in sibling files (Swift `private` is file-scoped).
    var relay: RelayClient?
    var relaysByRoom: [String: RelayClient] = [:]
    /// When each agent conversation was last asked for, so opening a card
    /// twice does not read a transcript twice.
    var threadEventRequestsAt: [String: Double] = [:]
    var meshEndpointRelaysById: [String: RelayClient] = [:]
    var meshEndpointRoomToId: [String: String] = [:]
    /// People invited into a Project's mesh from this phone.
    @Published var memberLinks: [MemberLink] = MemberLinkStore.load()
    var memberHubTimers: [String: Timer] = [:]
    var memberLinkConnected: Set<String> = []
    /// Which member sent a Governance edit, by request id (or project and
    /// revision), so the computer's answer can be handed back to that phone.
    var memberForwardedSets: [String: String] = [:]
    /// Which member wrote a message into a chat, by message id, so the
    /// computer's receipt goes back to that phone and not into this outbox.
    var memberForwardedMessages: [String: String] = [:]
    /// Which member asked for a claim's release, by claim and request, so the
    /// computers' answer goes back to that phone.
    var memberForwardedReleases: [String: String] = [:]
    /// Claims released from here and not yet answered, so a refusal can put one back.
    var releasedClaims: [String: ProjectResourceClaim] = [:]
    /// Claims released from here, by claim id, until each claim's own expiry:
    /// snapshots merge claims by union, so a computer that was away would
    /// otherwise hand one back the moment it published what it last knew.
    var meshReleasedClaims: [String: Double] = [:]
    /// Which member's phone first spoke for a Mesh row, by row identity. A
    /// member's copy of everyone else's work is not an authority over it.
    var meshContributionRooms: [String: String] = [:]
    /// Which member asked for a pause, by chat, so the answer reaches them.
    var memberForwardedControls: [String: String] = [:]
    /// What the phone showed before a pause was asked for, to go back to.
    var sessionControlPrevious: [String: Bool] = [:]
    /// Why a release was refused, by claim, for the screen the claim is on.
    @Published var claimReleaseNotices: [String: String] = [:]
    var roomRuntime: [String: RoomRuntime] = [:]
    /// Restored on launch, not rebuilt from live traffic alone.
    ///
    /// Deriving it only from arriving payloads meant a relaunch reported that
    /// the phone held no Project key, and left Governance with nobody to send
    /// a policy to, for as long as it took the next snapshot to arrive.
    var meshProjectSourceRooms: [String: Set<String>] =
        restoredMesh.projectRooms.mapValues(Set.init)
    var meshEventSourceRooms: [String: String] = restoredMesh.eventSourceRooms
    var authorizedHandoffRoutes: [String: String] = [:]
    /// approval / question id → room that delivered it (for multi-PC decide routing).
    var requestSourceRoom: [String: String] = {
        (UserDefaults.standard.dictionary(forKey: "granttap.request-source-rooms") as? [String: String]) ?? [:]
    }()
    /// Native session id -> every authenticated room that has published it.
    /// A set (rather than a single last-writer value) makes provider/room id
    /// collisions fail closed instead of routing an old chat to the preferred PC.
    var sessionSourceRooms: [String: [String]] = {
        (UserDefaults.standard.dictionary(forKey: "granttap.session-source-rooms")
            as? [String: [String]]) ?? [:]
    }()
    var activitySubscribers: [String: Set<String>] = [:]
    var activityHeartbeatTasks: [String: Task<Void, Never>] = [:]
    var backgroundWakeCompletions: [UUID: (UIBackgroundFetchResult) -> Void] = [:]
    var sessionRefreshWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]
    var refreshAfterConnect = false
    var lastSessionsGeneratedAt: Double = 0
    var refreshHintClearTask: Task<Void, Never>?
    /// Phone-minted session UUIDs Mac has never confirmed — omit on the wire so
    /// even granttap-mcp@0.6.5 starts a real new task instead of "session not found".
    var localOnlySessionIds: Set<String> = Set(
        UserDefaults.standard.stringArray(forKey: "granttap.local-only-sessions") ?? []
    )
    /// Stub → Mac session id after adopt. Open chat sheets keep the old UUID in
    /// `let session`; send/subscribe/activity must resolve through this map.
    var sessionIdAliases: [String: String] = {
        (UserDefaults.standard.dictionary(forKey: "granttap.session-id-aliases") as? [String: String]) ?? [:]
    }()
    let maxDeliveryAttempts = 5
    /// Generations with a completion callback owned by this process. Persisted
    /// `.sending` generations absent here were interrupted by app termination
    /// and are safe to resend with the same bridge-deduplicated message id.
    var liveDeliveryAttemptGenerations: Set<String> = []

    func start() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["GRANTTAP_DEMO"] == "1" {
            // Demo must not activate WCSession — on Simulator it can peg CPU at ~100%
            // and starve sheet `.task` / MainActor work (controls stuck on Loading…).
            startDemo()
            return
        }
        #endif
        WatchBridge.shared.start()
        loadConnectionRegistry()
        loadCachedSessionCatalogIfNeeded()
        // Paired / real mode: wipe any leftover Explore Demo rows before UI paints.
        if !demoMode,
           sessions.contains(where: { Self.isGrantTapDemoSessionId($0.sessionId) })
            || sessionHistory.contains(where: { Self.isGrantTapDemoSessionId($0.sessionId) }) {
            purgeDemoCatalogResidue(reason: "start")
        }
        pushToWatch(force: true)
        startGrokBotEndpointIfNeeded()
        attachStoredMemberLinks()
        if !connectionRegistry.connections.isEmpty {
            NotificationManager.shared.requestAuthorization()
        }
        guard !connectionRegistry.connections.isEmpty else { return }
        restartAllRelays()
        PushRegistrationManager.shared.pairingDidChange()
    }

    /// Debounce Offline so Connected does not blink on every WS blip.
    func applyConnectionChange(
        _ up: Bool,
        client: RelayClient,
        disconnectDelayNanoseconds: UInt64 = 1_800_000_000
    ) {
        connectedDebounceTask?.cancel()
        if up {
            connected = true
            refreshAfterConnect = false
            nudgeMacSessionScan(via: client)
            retryQueuedDeliveries()
            objectWillChange.send()
            pushToWatch()
            return
        }
        connectedDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: disconnectDelayNanoseconds)
            guard !Task.isCancelled else { return }
            // If we came back up during grace, leave Connected alone.
            guard self.relay?.task == nil else { return }
            self.connected = false
            self.objectWillChange.send()
            self.pushToWatch()
        }
    }

    /// Unlink every computer — Settings “forget all”.
    func forgetPairing() {
        for conn in connectionRegistry.connections {
            PushRegistrationManager.shared.unregister(conn.pairing)
        }
        AuditStore.shared.record("pairing", detail: "All linked computers removed")
        PairedConnectionStore.removeAll()
        clearLinkLocalState()
        pushToWatch()
    }

    /// Mac cancel/cancel-all watermark — drop late approval.request that arrives after Mac=0.
    /// Keys include the authenticated room so one computer cannot suppress another.
    var recentlyCancelledIds: [String: Date] = [:]
    var lastCancelAllAtByRoom: [String: Date] = [:]
    /// Per-room high-water mark prevents reliable relay snapshots arriving out
    /// of order from rolling approval state backwards.
    var approvalStatusWatermarkByRoom: [String: Double] = {
        (UserDefaults.standard.dictionary(forKey: "granttap.approval-status-watermarks")
            as? [String: Double]) ?? [:]
    }()
    /// Exact room/request/session tombstones block a stale pending snapshot or
    /// approval.request after a terminal event. Values are local receipt times.
    var approvalTerminalTombstones: [String: Double] = {
        (UserDefaults.standard.dictionary(forKey: "granttap.approval-terminal-tombstones")
            as? [String: Double]) ?? [:]
    }()

}
