import Foundation

/// A person invited into a Project's mesh from this phone.
///
/// The mesh moves through this phone: computers hand it their Project and
/// the phone forwards it to every other party it has admitted. A person's
/// phone is one more such party. This phone mints a pairing for it, hands
/// the other half over a one-time code, and then speaks to that phone the
/// way a computer speaks to this one — forwarding the Project, and applying
/// the rules below to whatever comes back.
enum MemberRole: String, Codable, CaseIterable, Identifiable {
    case viewer, member, admin
    var id: String { rawValue }

    var title: String {
        switch self {
        case .viewer: return L("Viewer")
        case .member: return L("Member")
        case .admin: return L("Admin")
        }
    }

    var explanation: String {
        switch self {
        case .viewer: return L("Sees the Project's Tasks, computers and Governance. Changes nothing.")
        case .member: return L("Sees the Project's chats on your computers and can write to them, hand Tasks off and post to the Project. Governance stays yours.")
        case .admin: return L("Can also edit Governance for this Project.")
        }
    }
}

/// What a member's phone may do; each answer is enforced on this phone
/// before anything reaches a computer.
struct MemberRules: Codable, Equatable {
    var canEditGovernance = false
    var canHandOffTasks = false
    var canPostEvents = false
    /// The Project's chats on this phone's computers, as they happen.
    var canSeeChats = false
    /// Messages, pauses and resumes into those chats. Approvals never leave this phone.
    var canSendToChats = false

    init(
        canEditGovernance: Bool = false, canHandOffTasks: Bool = false, canPostEvents: Bool = false,
        canSeeChats: Bool = false, canSendToChats: Bool = false
    ) {
        self.canEditGovernance = canEditGovernance
        self.canHandOffTasks = canHandOffTasks
        self.canPostEvents = canPostEvents
        self.canSeeChats = canSeeChats
        self.canSendToChats = canSendToChats
    }

    /// A link stored before chats could be shared decodes with them off.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canEditGovernance = try container.decodeIfPresent(Bool.self, forKey: .canEditGovernance) ?? false
        canHandOffTasks = try container.decodeIfPresent(Bool.self, forKey: .canHandOffTasks) ?? false
        canPostEvents = try container.decodeIfPresent(Bool.self, forKey: .canPostEvents) ?? false
        canSeeChats = try container.decodeIfPresent(Bool.self, forKey: .canSeeChats) ?? false
        canSendToChats = try container.decodeIfPresent(Bool.self, forKey: .canSendToChats) ?? false
    }

    static func preset(_ role: MemberRole) -> MemberRules {
        switch role {
        case .viewer: return MemberRules()
        case .member:
            return MemberRules(canEditGovernance: false, canHandOffTasks: true, canPostEvents: true,
                               canSeeChats: true, canSendToChats: true)
        case .admin:
            return MemberRules(canEditGovernance: true, canHandOffTasks: true, canPostEvents: true,
                               canSeeChats: true, canSendToChats: true)
        }
    }

    var summary: String {
        var parts: [String] = []
        if canEditGovernance { parts.append(L("governance")) }
        if canHandOffTasks { parts.append(L("hand-off")) }
        if canPostEvents { parts.append(L("posts")) }
        if canSendToChats { parts.append(L("chats")) } else if canSeeChats { parts.append(L("reads chats")) }
        return parts.isEmpty ? L("view only") : parts.joined(separator: " · ")
    }
}

enum MemberLinkState: Equatable {
    case waiting(expiresAt: Double)
    case expired
    case connected
    case offline(lastSeenAt: Double?)
}

struct MemberLink: Codable, Identifiable, Equatable {
    /// The pairing room, which is also how a payload is traced back to a member.
    let id: String
    let projectId: String
    var name: String
    var role: MemberRole
    var rules: MemberRules
    let createdAt: Double
    var inviteExpiresAt: Double
    var joinedAt: Double? = nil
    var lastSeenAt: Double? = nil
    /// This phone's half of the pairing: the "machine" side of the room.
    let hubPairing: Pairing

    func state(now: Double, connected: Bool) -> MemberLinkState {
        if connected { return .connected }
        if joinedAt == nil { return now < inviteExpiresAt ? .waiting(expiresAt: inviteExpiresAt) : .expired }
        return .offline(lastSeenAt: lastSeenAt)
    }
}

/// Which of a member's payloads this phone forwards, by the member's rules.
///
/// A member's phone speaks to this one as a phone speaks to a computer, so
/// what arrives is the same set of payloads a computer would hear. Each is
/// let through by one rule, and what no rule names stays here.
enum MemberHubPolicy {
    static func allows(_ type: String, rules: MemberRules) -> Bool {
        switch type {
        case "project.policy.set", "mesh.claim.release": return rules.canEditGovernance
        case "mesh.handoff.prepare": return rules.canHandOffTasks
        case "mesh.event", "mesh.snapshot": return rules.canPostEvents
        case "user.message", "session.control": return rules.canSendToChats
        case "session.subscribe", "session.events", "sessions.refresh": return rules.canSeeChats
        default: return false
        }
    }

    /// A Mesh event a member may publish. Ownership moves only with a
    /// receipt, which the phone checks; a handoff request is a hand-off.
    static func allowsEvent(_ eventType: String, rules: MemberRules) -> Bool {
        switch eventType {
        case "HANDOFF_REQUEST": return rules.canHandOffTasks
        case "HANDOFF_REJECTED": return rules.canHandOffTasks
        default: return true
        }
    }

    /// Why a payload was not forwarded, for the member's screen.
    static func refusal(_ type: String) -> String {
        switch type {
        case "project.policy.set": return L("This member may not edit Governance.")
        case "mesh.claim.release": return L("This member may not release claims; an admin may.")
        case "mesh.handoff.prepare": return L("This member may not hand Tasks off.")
        case "mesh.event", "mesh.snapshot": return L("This member may not post to the Project.")
        case "user.message", "session.control": return L("This member may not write to the Project's chats.")
        case "session.subscribe", "session.events", "sessions.refresh": return L("This member may not see the Project's chats.")
        default: return L("Members cannot do that from another phone.")
        }
    }
}

/// Member links hold this phone's secret keys for each room, so they live in
/// the keychain beside the other pairings.
enum MemberLinkStore {
    static let service = "com.ziborov.granttap.member-links"
    static let maxLinks = 64

    static func load(service: String = service) -> [MemberLink] {
        guard let data = KeychainPairing.load(service: service),
              let links = try? JSONDecoder().decode([MemberLink].self, from: data) else { return [] }
        return links
    }

    @discardableResult
    static func save(_ links: [MemberLink], service: String = service) -> Bool {
        let bounded = Array(links.sorted { $0.createdAt > $1.createdAt }.prefix(maxLinks))
        guard let data = try? JSONEncoder().encode(bounded) else { return false }
        return KeychainPairing.save(data, service: service)
    }

    static func remove(service: String = service) {
        KeychainPairing.remove(service: service)
    }
}
