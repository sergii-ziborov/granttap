import Foundation
import SwiftUI
import UIKit

extension AppModel {
    func attachRelay(for pairing: Pairing) {
        let room = pairing.room
        relaysByRoom[room]?.disconnect()
        let client = RelayClient(pairing: pairing)
        client.onConnectionChange = { [weak self, weak client] up in
            guard let self, let client else { return }
            self.applyRoomConnectionChange(up, client: client)
        }
        client.onRequest = { [weak self] (req: ApprovalRequest) in
            guard let self else { return }
            self.receive(req, fromRoom: room)
            self.finishBackgroundWake(.newData)
        }
        client.onDecision = { [weak self] (dec: ApprovalDecision) in
            self?.receiveRemoteDecision(dec, fromRoom: room)
            self?.finishBackgroundWake(.newData)
        }
        client.onApprovalCancel = { [weak self] (cancel: ApprovalCancel) in
            guard let self else { return }
            self.receive(cancel, fromRoom: room)
            self.finishBackgroundWake(.newData)
        }
        client.onApprovalResolved = { [weak self] resolved in
            guard let self else { return }
            self.receive(resolved, fromRoom: room)
            self.finishBackgroundWake(.newData)
        }
        client.onApprovalsStatus = { [weak self] status in
            guard let self else { return }
            self.receive(status, fromRoom: room)
            self.finishBackgroundWake(.newData)
        }
        client.onAgentEvent = { [weak self] (ev: AgentEvent) in
            guard let self else { return }
            self.receive(ev, fromRoom: room)
            self.finishBackgroundWake(.newData)
        }
        client.onActivity = { [weak self] activity in
            guard let self else { return }
            // A detail view subscribes through the session's owning room, which
            // can be a non-preferred computer. Accept that exact owner; for
            // legacy unowned ids accept only the preferred room. A raw id known
            // in multiple rooms remains ambiguous and therefore fail-closed.
            guard self.acceptsSessionPayload(sessionId: activity.sessionId,
                                             fromRoom: room) else { return }
            self.applyActivity(activity, sourceNamespace: room)
        }
        client.onCapabilityUsage = { status in
            CapabilityUsageStore.shared.merge(status.events, sourceNamespace: room)
            CapabilityTotalsStore.shared.apply(status.totals, fromRoom: room)
        }
        client.onCapabilityCatalog = { status in
            CapabilityCatalogStore.shared.apply(status, fromRoom: room)
        }
        client.onSessions = { [weak self] status in
            self?.applySessionsStatus(status, fromRoom: room)
        }
        client.onMachineHeartbeat = { [weak self] beat in
            self?.noteMachineHeartbeat(beat, fromRoom: room)
        }
        client.onMachineLoad = { [weak self] load in
            self?.recordMachineLoad(load, fromRoom: room)
        }
        client.onMeshSnapshot = { [weak self] snapshot in
            self?.receive(snapshot, fromRoom: room)
        }
        client.onMeshEvent = { [weak self] event in
            self?.receive(event, fromRoom: room)
        }
        client.onProjectPolicyStatus = { [weak self] status in
            self?.receive(status, fromRoom: room)
        }
        client.onProjectPolicyAck = { [weak self] acknowledgement in
            self?.receive(acknowledgement, fromRoom: room)
        }
        client.onProjectPolicyRejected = { [weak self] rejected in
            self?.receive(rejected, fromRoom: room)
        }
        client.onClaimReleaseResult = { [weak self] result in
            self?.receive(result, fromRoom: room)
        }
        client.onDeliveryReceipt = { [weak self] receipt in
            self?.receive(receipt, fromRoom: room)
            self?.finishBackgroundWake(.newData)
        }
        client.onToolUpdateResult = { [weak self] result in
            self?.receive(result, fromRoom: room)
        }
        client.onCompactResult = { [weak self] result in
            guard let self, room == self.connectionRegistry.preferredId else { return }
            self.compactingSessions.remove(result.sessionId)
            self.compactResults[result.sessionId] = result
            self.append(result.message)
        }
        client.onSessionControlResult = { [weak self] result in
            self?.receive(result)
        }
        relaysByRoom[room] = client
        client.connect()
    }

    func applyRoomConnectionChange(_ up: Bool, client: RelayClient) {
        let room = client.pairing.room
        if !up {
            markDeliveryAttemptsInterrupted(forRoom: room)
        }
        if up {
            syncAgentMeshSettings(to: client)
            var rt = roomRuntime[room] ?? RoomRuntime()
            if !rt.socketUp { rt.socketUpSince = Date().timeIntervalSince1970 * 1000 }
            rt.socketUp = true
            roomRuntime[room] = rt
        } else {
            var rt = roomRuntime[room] ?? RoomRuntime()
            rt.socketUp = false
            roomRuntime[room] = rt
        }

        let isPreferred = room == connectionRegistry.preferredId
            || (connectionRegistry.preferredId == nil && client === relay)
        if isPreferred {
            applyConnectionChange(up, client: client)
        } else {
            if up { retryQueuedDeliveries(forRoom: room) }
            objectWillChange.send()
        }
        // A Governance edit written while this room was down is offered again
        // now, rather than being lost to whichever machine was awake.
        if up { flushProjectPolicyOutbox() }
    }
}
