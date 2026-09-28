import Foundation

/// Once a command observation has been received, a sparse subsequent transcript
/// page must not erase it. Explicit new evidence always wins, and evidence is
/// never copied to a different tool call or capability.
enum SessionActivityTelemetry {
    static func retaining(_ incoming: ActivityEntry, from previous: ActivityEntry?) -> ActivityEntry {
        guard let previous, incoming.id == previous.id, incoming.kind == "tool",
              incoming.kind == previous.kind, incoming.toolName == previous.toolName else { return incoming }
        var result = incoming
        result.durationMs = incoming.durationMs ?? previous.durationMs
        result.estimatedContextTokens = incoming.estimatedContextTokens ?? previous.estimatedContextTokens
        if let capabilities = incoming.capabilities {
            result.capabilities = capabilities.map { capability in
                guard let old = previous.capabilities?.first(where: {
                    $0.kind == capability.kind && $0.name == capability.name && $0.toolName == capability.toolName
                }) else { return capability }
                var retained = capability
                retained.resource = capability.resource ?? old.resource
                retained.durationMs = capability.durationMs ?? old.durationMs
                retained.estimatedContextTokens = capability.estimatedContextTokens ?? old.estimatedContextTokens
                return retained
            }
        } else {
            result.capabilities = previous.capabilities
        }
        return result
    }
}
