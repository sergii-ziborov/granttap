import Foundation

struct ProviderHookInfo: Codable, Equatable, Identifiable, Sendable {
    let event: String
    let trustStatus: String
    let enabled: Bool
    var key: String? = nil
    var currentHash: String? = nil
    var command: String? = nil

    var id: String { event }
    var isActive: Bool { ["PreToolUse", "PermissionRequest"].contains(event) && trustStatus == "trusted" && enabled }
    static func summary(_ hooks: [Self]?) -> String {
        guard let hooks, hooks.count == 2, Set(hooks.map(\.event)) == ["PreToolUse", "PermissionRequest"] else {
            return L("Unknown")
        }
        if hooks.allSatisfy(\.isActive) { return L("Ready") }
        if hooks.contains(where: { !["trusted", "untrusted", "modified", "missing"].contains($0.trustStatus) }) {
            return L("Unknown")
        }
        if hooks.contains(where: { $0.trustStatus == "missing" }) { return L("Not configured") }
        if hooks.contains(where: { $0.trustStatus == "untrusted" || $0.trustStatus == "modified" }) {
            return L("Needs review")
        }
        return L("Disabled in Codex")
    }
    var canReview: Bool {
        ["PreToolUse", "PermissionRequest"].contains(event) &&
        ["trusted", "modified", "untrusted"].contains(trustStatus) &&
        key?.isEmpty == false && currentHash?.isEmpty == false && command?.isEmpty == false &&
        (key?.count ?? 513) <= 512 && (currentHash?.count ?? 129) <= 128 &&
        (command?.count ?? 2_049) <= 2_048
    }
    var title: String {
        switch trustStatus {
        case "trusted": return enabled ? L("Trusted and enabled") : L("Disabled in Codex")
        case "modified": return L("Changed — review required")
        case "untrusted": return L("Needs your review")
        case "missing": return L("GrantTap hook is not configured")
        default: return L("Hook status is unavailable")
        }
    }
    var purpose: String {
        event == "PreToolUse" ? L("Applies GrantTap tool rules before a tool runs.") :
            L("Delivers Codex permission requests to GrantTap.")
    }
}

struct ProviderHookTrust: Codable, Equatable {
    let type: String
    let agent: String
    let endpointId: String
    let event: String
    let key: String
    let currentHash: String
    let requestId: String
    let createdAt: Double
}

struct ProviderHookTrustResult: Codable, Equatable {
    let type: String
    let agent: String
    let endpointId: String
    let requestId: String
    let ok: Bool
    let message: String
    let hooks: [ProviderHookInfo]
    let checkedAt: Double
}
