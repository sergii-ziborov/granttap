import Combine
import Foundation

@MainActor
final class ProjectNetworkCoordinator: ObservableObject {
    enum State { case configuring, ready, failed }
    typealias Send = (ProjectTransportCommand, ProjectNetworkEndpoint) -> Void
    @Published private(set) var states: [String: State] = [:]
    private var pending: [String: ProjectNetworkConfirmation] = [:]
    private var plans: [String: ProjectNetworkPlan] = [:]
    private let load: (String) -> ProjectNetworkPlan?
    private let save: (ProjectNetworkPlan) throws -> Void
    private let publish: (ProjectNetworkWriter, Pairing) async throws -> Void
    private let publishConfiguration: (ProjectTransportCommand, Pairing) async throws -> Void
    private let nativeGrant: (ProjectNetworkWriter, String) async throws -> Void
    private let nativeConfiguration: (ProjectTransportCommand) async throws -> ProjectTransportAck
    private let clock: () -> Double

    init(load: @escaping (String) -> ProjectNetworkPlan? = ProjectNetworkVault.load,
         save: @escaping (ProjectNetworkPlan) throws -> Void = ProjectNetworkVault.save,
         publish: @escaping (ProjectNetworkWriter, Pairing) async throws -> Void = ProjectNetworkHTTP.publish,
         publishConfiguration: @escaping (ProjectTransportCommand, Pairing) async throws -> Void
            = ProjectNetworkConfigurationHTTP.publish,
         nativeGrant: @escaping (ProjectNetworkWriter, String) async throws -> Void = ProjectNetworkNative.publish,
         nativeConfiguration: @escaping (ProjectTransportCommand) async throws -> ProjectTransportAck = ProjectNetworkNative.configure,
         clock: @escaping () -> Double = { floor(Date().timeIntervalSince1970 * 1_000) }) {
        self.load = load
        self.save = save
        self.publish = publish
        self.publishConfiguration = publishConfiguration
        self.nativeGrant = nativeGrant
        self.nativeConfiguration = nativeConfiguration
        self.clock = clock
    }

    func ensure(projectId: String, endpoints: [ProjectNetworkEndpoint], pairings: [String: Pairing],
                requiredEndpoints: Set<String>? = nil, nativeEndpointId: String? = nil,
                routingEnabled: Bool? = nil, allowCrossPlatform: Bool? = nil, send: @escaping Send) async throws {
        guard states[projectId] != .configuring else { throw ProjectNetworkError.notConfirmed }
        let ordered = endpoints.sorted { $0.id < $1.id }, now = clock()
        let required = requiredEndpoints ?? Set(ordered.map(\.id))
        guard !required.isEmpty, required.isSubset(of: Set(ordered.map(\.id))) else {
            throw ProjectNetworkError.invalidScope
        }
        guard nativeEndpointId == nil || ordered.contains(where: { $0.id == nativeEndpointId }),
              ordered.allSatisfy({ $0.id == nativeEndpointId || pairings[$0.id]?.room == $0.room
            && pairings[$0.id]?.peerPublicKey == $0.publicKey && pairings[$0.id]?.isHub == false }) else {
            throw ProjectNetworkError.invalidScope
        }
        let old = plans[projectId] ?? load(projectId)
        var plan: ProjectNetworkPlan
        let desiredRouting = routingEnabled ?? old?.commands.first?.routingEnabled ?? false
        let desiredCrossPlatform = allowCrossPlatform ?? old?.commands.first?.allowCrossPlatform ?? false
        if let old, old.endpoints == ordered, old.commands.allSatisfy({ $0.expiresAt > now + 3_600_000 }) {
            plan = old
        } else {
            plan = try ProjectNetworkPlan.make(projectId: projectId, endpoints: ordered, routingEnabled: desiredRouting,
                allowCrossPlatform: desiredCrossPlatform,
                revision: max(Int(now), (old?.revision ?? 0) + 1), now: now)
        }
        if plan.commands.contains(where: { $0.routingEnabled != desiredRouting || $0.allowCrossPlatform != desiredCrossPlatform }) {
            plan = plan.changingRouting(desiredRouting, allowCrossPlatform: desiredCrossPlatform, now: now)
        }
        plans[projectId] = plan
        if required.isSubset(of: plan.confirmedEndpoints) { states[projectId] = .ready; return }
        states[projectId] = .configuring
        pending[projectId] = .init(plan: plan)
        defer { pending[projectId] = nil }
        do {
            try save(plan)
            try await install(plan, pairings: pairings, nativeEndpointId: nativeEndpointId, send: send)
            let deadline = clock() + 30_000
            while clock() < deadline {
                if let confirmation = pending[projectId], confirmation.rejected.isDisjoint(with: required),
                   required.isSubset(of: confirmation.plan.confirmedEndpoints) {
                    try save(confirmation.plan)
                    plans[projectId] = confirmation.plan
                    states[projectId] = .ready
                    return
                }
                if states[projectId] == .failed || pending[projectId]?.rejected.isDisjoint(with: required) == false {
                    throw ProjectNetworkError.notConfirmed
                }
                try await Task.sleep(nanoseconds: 200_000_000)
            }
            throw ProjectNetworkError.notConfirmed
        } catch {
            states[projectId] = .failed
            throw error
        }
    }

    func routingEnabled(projectId: String) -> Bool {
        (plans[projectId] ?? load(projectId))?.commands.first?.routingEnabled ?? false
    }

    func allowsCrossPlatform(projectId: String) -> Bool {
        (plans[projectId] ?? load(projectId))?.commands.first?.allowCrossPlatform ?? false
    }

    private func install(_ plan: ProjectNetworkPlan, pairings: [String: Pairing], nativeEndpointId: String?,
                         send: @escaping Send) async throws {
        for writer in plan.writers {
            if writer.ownerEndpointId == nativeEndpointId { try await nativeGrant(writer, plan.projectId) }
            else if let pairing = pairings[writer.ownerEndpointId] { try await publish(writer, pairing) }
            else { throw ProjectNetworkError.invalidScope }
        }
        for command in plan.commands {
            guard let endpoint = plan.endpoints.first(where: { $0.id == command.targetEndpointId }) else {
                throw ProjectNetworkError.invalidScope
            }
            if command.targetEndpointId == nativeEndpointId {
                receive(try await nativeConfiguration(command), room: endpoint.room)
            } else if let pairing = pairings[command.targetEndpointId] {
                try await publishConfiguration(command, pairing)
            } else { throw ProjectNetworkError.invalidScope }
        }
        for command in plan.commands where command.targetEndpointId != nativeEndpointId {
            if let endpoint = plan.endpoints.first(where: { $0.id == command.targetEndpointId }) { send(command, endpoint) }
        }
    }

    func receive(_ ack: ProjectTransportAck, room: String) {
        guard var confirmation = pending[ack.projectId], confirmation.receive(ack, room: room) else { return }
        do {
            try save(confirmation.plan)
            pending[ack.projectId] = confirmation
            plans[ack.projectId] = confirmation.plan
        } catch { states[ack.projectId] = .failed }
    }
}
