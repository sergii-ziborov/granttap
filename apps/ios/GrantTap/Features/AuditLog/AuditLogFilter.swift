import Foundation

enum AuditLogFilter: String, CaseIterable {
    case all
    case errors

    var title: String {
        switch self {
        case .all: return L("All")
        case .errors: return L("Errors")
        }
    }

    func apply(_ events: [AuditEvent], search: String) -> [AuditEvent] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return events.filter { event in
            let outcomeMatches = self == .all || event.outcome == "failed"
            let searchMatches = query.isEmpty
                || event.action.lowercased().contains(query)
                || event.detail.lowercased().contains(query)
            return outcomeMatches && searchMatches
        }
    }
}
