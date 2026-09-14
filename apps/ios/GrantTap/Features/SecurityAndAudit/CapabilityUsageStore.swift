import Foundation
import OSLog
import SwiftUI

@MainActor
final class CapabilityUsageStore: ObservableObject {
    static let shared = CapabilityUsageStore()
    private static let persistenceLogger = Logger(subsystem: "com.ziborov.granttap",
                                                  category: "capability-usage")
    @Published private(set) var events: [CapabilityUsageEvent] = []
    private var pendingWrite: DispatchWorkItem?
    private static let clearedAtKey = "granttap.capability-usage.cleared-at"
    private static let persistenceQueue = DispatchQueue(
        label: "com.ziborov.granttap.capability-usage",
        qos: .utility
    )

    private init() { events = Self.load() }

    func record(_ kind: CapabilityUsageKind, name: String, sessionId: String?,
                sourceId: String, createdAt: Double = Date().timeIntervalSince1970 * 1000,
                toolName: String? = nil, commandPreview: String? = nil,
                estimatedContextTokens: Int? = nil,
                estimatedBaselineTokens: Int? = nil, durationMs: Int? = nil,
                outcome: CapabilityOutcome? = nil, errorClass: String? = nil,
                sourceNamespace: String? = nil, agent: String? = nil,
                model: String? = nil, resource: CapabilityResourceUsage? = nil) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let namespacedSourceId = Self.sourceId(sourceId, namespace: sourceNamespace)
        let sourceRoom = Self.normalizedRoom(sourceNamespace)
        let cleanSession = Self.normalizedSession(sessionId)
        let cleanPreview = Self.commandPreview(commandPreview)
        let cleanAgent = Self.normalizedAgent(agent)
        let cleanModel = Self.normalizedModel(model)
        let target = Self.chatTarget(room: sourceRoom, sessionId: cleanSession)
        guard !clean.isEmpty, createdAt > Self.clearedAt else { return }
        if let index = events.firstIndex(where: {
            $0.sourceId == namespacedSourceId && $0.kind == kind && $0.name == clean
        }) {
            var current = events[index]
            let nextRoom = sourceRoom ?? current.sourceRoom
            let nextSession = cleanSession ?? current.sessionId
            let nextTarget = target ?? current.deepLinkTarget
            let nextPreview = cleanPreview ?? current.commandPreview
            let nextAgent = cleanAgent ?? current.agent
            let nextModel = cleanModel ?? current.model
            let nextResource = resource ?? current.resource
            guard current.sourceRoom != nextRoom || current.sessionId != nextSession
                    || current.agent != nextAgent || current.model != nextModel
                    || current.toolName != toolName
                    || current.commandPreview != nextPreview
                    || current.deepLinkTarget != nextTarget
                    || current.estimatedContextTokens != estimatedContextTokens
                    || current.estimatedBaselineTokens != estimatedBaselineTokens
                    || current.durationMs != durationMs || current.outcome != outcome
                    || current.errorClass != errorClass
                    || current.resource != nextResource else { return }
            current.sourceRoom = nextRoom
            current.sessionId = nextSession
            current.agent = nextAgent
            current.model = nextModel
            current.toolName = toolName
            current.commandPreview = nextPreview
            current.deepLinkTarget = nextTarget
            current.estimatedContextTokens = estimatedContextTokens
            current.estimatedBaselineTokens = estimatedBaselineTokens
            current.durationMs = durationMs
            current.outcome = outcome
            current.errorClass = errorClass
            current.resource = nextResource
            var next = events
            next[index] = current
            events = next
            persist()
            return
        }
        events.insert(CapabilityUsageEvent(id: UUID().uuidString.lowercased(), sourceId: namespacedSourceId,
                                           sourceRoom: sourceRoom, agent: cleanAgent,
                                           model: cleanModel, kind: kind, name: clean,
                                           sessionId: cleanSession,
                                           createdAt: createdAt, toolName: toolName,
                                           commandPreview: cleanPreview,
                                           deepLinkTarget: target,
                                           estimatedContextTokens: estimatedContextTokens,
                                           estimatedBaselineTokens: estimatedBaselineTokens,
                                           durationMs: durationMs, outcome: outcome,
                                           errorClass: errorClass, resource: resource), at: 0)
        if events.count > 1_000 { events.removeLast(events.count - 1_000) }
        persist()
    }

    func merge(_ incoming: [RemoteCapabilityUsageEvent], sourceNamespace: String? = nil) {
        // Work on a plain snapshot and publish once. A subscribed chat can
        // contain hundreds of tool rows; mutating the @Published array once per
        // row while SwiftUI is mounting the destination creates an
        // AttributeGraph update storm (white screen / watchdog termination).
        var next = events
        var indices: [String: Int] = [:]
        for (index, event) in next.enumerated() {
            indices[Self.eventKey(sourceId: event.sourceId, kind: event.kind,
                                  name: event.name)] = index
        }
        var changed = false
        let sourceRoom = Self.normalizedRoom(sourceNamespace)
        for item in incoming {
            let clean = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let sourceId = Self.sourceId(item.sourceId, namespace: sourceNamespace)
            let sessionId = Self.normalizedSession(item.sessionId)
            let preview = Self.commandPreview(item.commandPreview)
            let agent = Self.normalizedAgent(item.agent)
            let model = Self.normalizedModel(item.model)
            // Never trust a room claimed inside encrypted payload over the
            // authenticated RelayClient that delivered it.
            let claimedTarget = item.deepLinkTarget
            let target: CapabilityChatTarget? = {
                guard let local = Self.chatTarget(room: sourceRoom, sessionId: sessionId) else {
                    return nil
                }
                guard Self.normalizedRoom(item.roomId).map({ $0 == local.roomId }) ?? true,
                      let claimedTarget,
                      claimedTarget.kind == "chat",
                      claimedTarget.roomId == local.roomId,
                      claimedTarget.sessionId == local.sessionId else {
                    return local
                }
                return claimedTarget
            }()
            guard !clean.isEmpty, item.createdAt > Self.clearedAt else { continue }
            let key = Self.eventKey(sourceId: sourceId, kind: item.kind, name: clean)
            if let index = indices[key] {
                let mergedRoom = sourceRoom ?? next[index].sourceRoom
                let mergedSession = sessionId ?? next[index].sessionId
                let mergedTarget = target ?? next[index].deepLinkTarget
                let mergedPreview = preview ?? next[index].commandPreview
                let mergedAgent = agent ?? next[index].agent
                let mergedModel = model ?? next[index].model
                let mergedResource = item.resource ?? next[index].resource
                if next[index].sourceRoom != mergedRoom ||
                    next[index].sessionId != mergedSession ||
                    next[index].agent != mergedAgent ||
                    next[index].model != mergedModel ||
                    next[index].toolName != item.toolName ||
                    next[index].commandPreview != mergedPreview ||
                    next[index].deepLinkTarget != mergedTarget ||
                    next[index].estimatedContextTokens != item.estimatedContextTokens ||
                    next[index].estimatedBaselineTokens != item.estimatedBaselineTokens ||
                    next[index].durationMs != item.durationMs ||
                    next[index].outcome != item.outcome ||
                    next[index].errorClass != item.errorClass ||
                    next[index].resource != mergedResource {
                    next[index].sourceRoom = mergedRoom
                    next[index].sessionId = mergedSession
                    next[index].agent = mergedAgent
                    next[index].model = mergedModel
                    next[index].toolName = item.toolName
                    next[index].commandPreview = mergedPreview
                    next[index].deepLinkTarget = mergedTarget
                    next[index].estimatedContextTokens = item.estimatedContextTokens
                    next[index].estimatedBaselineTokens = item.estimatedBaselineTokens
                    next[index].durationMs = item.durationMs
                    next[index].outcome = item.outcome
                    next[index].errorClass = item.errorClass
                    next[index].resource = mergedResource
                    changed = true
                }
                continue
            }
            next.append(CapabilityUsageEvent(
                id: UUID().uuidString.lowercased(), sourceId: sourceId,
                sourceRoom: sourceRoom, agent: agent, model: model,
                kind: item.kind, name: clean,
                sessionId: sessionId,
                createdAt: item.createdAt, toolName: item.toolName,
                commandPreview: preview,
                deepLinkTarget: target,
                estimatedContextTokens: item.estimatedContextTokens,
                estimatedBaselineTokens: item.estimatedBaselineTokens,
                durationMs: item.durationMs, outcome: item.outcome,
                errorClass: item.errorClass, resource: item.resource
            ))
            indices[key] = next.count - 1
            changed = true
        }
        guard changed else { return }
        next.sort { $0.createdAt > $1.createdAt }
        if next.count > 1_000 { next.removeLast(next.count - 1_000) }
        events = next
        persist()
    }

    func clear() {
        pendingWrite?.cancel()
        pendingWrite = nil
        UserDefaults.standard.set(Date().timeIntervalSince1970 * 1000,
                                  forKey: Self.clearedAtKey)
        events = []
        let fileURL = Self.fileURL
        Self.persistenceQueue.async {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func persist() {
        // Tool streams can contain several MCP calls in one update. Encoding
        // and atomically rewriting up to 1,000 records for every entry on the
        // MainActor made task-tab gestures hitch. Coalesce a burst and do the
        // bounded local write on a utility queue.
        pendingWrite?.cancel()
        let snapshot = events
        let item = DispatchWorkItem { Self.write(snapshot) }
        pendingWrite = item
        Self.persistenceQueue.asyncAfter(deadline: .now() + 0.2, execute: item)
    }

    private static func write(_ events: [CapabilityUsageEvent]) {
        guard let data = try? JSONEncoder().encode(events) else { return }
        do {
            try FileManager.default.createDirectory(at: directoryURL,
                                                    withIntermediateDirectories: true)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            persistenceLogger.error("Capability history write failed (code: \((error as NSError).code, privacy: .public))")
        }
    }

    private static func load() -> [CapabilityUsageEvent] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return decodePersisted(data)
    }

    static var clearedAt: Double {
        UserDefaults.standard.double(forKey: clearedAtKey)
    }

    private static func sourceId(_ raw: String, namespace: String?) -> String {
        guard let namespace = namespace?.trimmingCharacters(in: .whitespacesAndNewlines),
              !namespace.isEmpty else { return raw }
        return "\(namespace):\(raw)"
    }

    static func normalizedRoom(_ value: String?) -> String? {
        guard let room = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !room.isEmpty else { return nil }
        return room
    }

    static func normalizedSession(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty, value.count <= 256 else { return nil }
        return value
    }

    private static func normalizedAgent(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return AgentIdentity.normalize(value)
    }

    private static func normalizedModel(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return String(value.prefix(160))
    }

    static func commandPreview(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(160))
    }

    static func chatTarget(room: String?, sessionId: String?) -> CapabilityChatTarget? {
        guard let room, let sessionId else { return nil }
        return CapabilityChatTarget(kind: "chat", roomId: room, sessionId: sessionId)
    }

    private static func eventKey(sourceId: String, kind: CapabilityUsageKind,
                                 name: String) -> String {
        "\(sourceId)\u{1f}\(kind.rawValue)\u{1f}\(name)"
    }

    private static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrantTap", isDirectory: true)
    }
    private static var fileURL: URL { directoryURL.appendingPathComponent("capability-usage.json") }
}
