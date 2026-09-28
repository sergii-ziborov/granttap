import Foundation

enum EngineCoverageCodec {
    static func matches(_ result: [String: Any], projectId: String) -> Bool {
        guard let report = result["coverage"] as? [String: Any],
              report["project_id"] as? String == projectId,
              let revision = report["policy_revision"] as? Int, revision >= 0,
              let enforcement = report["enforcement"] as? String,
              ["strict", "best_available"].contains(enforcement),
              report["strict_ready"] is Bool,
              let required = report["required_capabilities"] as? [String],
              validKinds(required),
              let endpoints = report["endpoints"] as? [[String: Any]],
              endpoints.count <= 32 else { return false }
        return endpoints.allSatisfy { endpoint in
            guard endpoint["project_id"] as? String == projectId,
                  endpoint["policy_revision"] as? Int == revision,
                  let endpointId = endpoint["endpoint_id"] as? String,
                  validIdentity(endpointId, maxBytes: 128),
                  let provider = endpoint["provider"] as? String,
                  validIdentity(provider, maxBytes: 80),
                  let capabilities = endpoint["capabilities"] as? [[String: Any]],
                  capabilities.count <= 8,
                  let observedAt = endpoint["observed_at"] as? Int,
                  observedAt >= 0 else { return false }
            let kinds = capabilities.compactMap { $0["kind"] as? String }
            return kinds.count == capabilities.count && validKinds(kinds)
                && capabilities.allSatisfy {
                    guard let status = $0["status"] as? String else { return false }
                    return ["enforced", "observed", "unsupported", "unknown"].contains(status)
                }
        }
    }

    private static func validKinds(_ kinds: [String]) -> Bool {
        let allowed: Set<String> = ["agent", "mcp", "skill", "shell", "script",
                                    "file_write", "deploy", "network"]
        return kinds.count <= 8 && Set(kinds).count == kinds.count
            && kinds.allSatisfy { allowed.contains($0) }
    }

    private static func validIdentity(_ value: String, maxBytes: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= maxBytes
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}
