import SwiftUI

/// GrantTap approval rules and native provider access are separate controls.
/// Choosing a rule never changes a provider sandbox or a global setting.
enum PersonalApprovalMode: String, CaseIterable, Identifiable {
    case every, risky, full, defaults, custom

    var id: String { rawValue }
    var label: String {
        switch self {
        case .every: return L("Ask for approval")
        case .risky: return L("Approve for me")
        case .full: return L("Allow all actions")
        case .defaults: return L("Use agent defaults")
        case .custom: return L("Custom rule")
        }
    }
    var detail: String {
        switch self {
        case .every: return L("Ask before every action handled by GrantTap.")
        case .risky: return L("Allow routine actions. Ask before publishing, destructive actions and external writes.")
        case .full: return L("Allow actions without asking in this chat. Global and Mesh blocks still apply.")
        case .defaults: return L("Use the provider's own approval flow and configuration.")
        case .custom: return L("This computer has reported a custom approval rule.")
        }
    }
    var symbol: String {
        switch self {
        case .every: return "hand.raised"
        case .risky: return "checkmark.shield"
        case .full: return "exclamationmark.shield"
        case .defaults: return "gearshape"
        case .custom: return "slider.horizontal.3"
        }
    }
}

@MainActor
struct ChatApprovalPreferences {
    let sessionId: String
    let session: SessionInfo
    let model: AppModel

    var mode: PersonalApprovalMode {
        if model.isExcluded(sessionId) { return .defaults }
        switch model.autoAcceptLevel(for: sessionId) {
        case "ask": return .every
        case "except_push": return .risky
        case "full": return .full
        default: return .custom
        }
    }

    var binding: Binding<PersonalApprovalMode> {
        Binding(get: { mode }, set: { apply($0) })
    }

    var available: Bool {
        guard !model.demoMode else { return false }
        if model.localTaskControlsAvailable(sessionId) { return true }
        return model.chatComputerRoute(forSessionId: sessionId)?.phase == .live
            && model.relayForSession(sessionId) != nil
    }

    func apply(_ choice: PersonalApprovalMode) {
        guard !model.demoMode else { return }
        switch choice {
        case .defaults: model.setSessionExcluded(sessionId, true)
        case .every: model.setSessionAutoAccept(sessionId, "ask")
        case .risky, .full:
            model.setSessionAutoAccept(sessionId, choice == .full ? "full" : "except_push",
                authorizeProjectAsk: true,
                expectedPolicyRevision: session.projectId.flatMap { model.projectGovernance[$0]?.revision })
        case .custom: break
        }
    }
}
