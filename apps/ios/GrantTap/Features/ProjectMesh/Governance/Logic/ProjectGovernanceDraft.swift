import Foundation

/// A Governance edit in progress, held outside the screen that made it.
///
/// The editor used to keep its pickers in view state and reload them from the
/// saved policy on every appearance. Leaving the screen before the computers
/// had applied the edit — which is the normal case, since they apply when they
/// next read their mailbox — discarded it silently.
struct ProjectGovernanceDraft: Equatable, Codable {
    var enforcement: ProjectEnforcementMode
    var defaults: [ProjectCapabilityKind: ProjectPolicyEffect]
    var named: [ProjectGovernanceLogic.NamedRule: ProjectPolicyEffect]

    /// Dictionaries keyed by anything but a string or an integer encode as
    /// flat arrays; pairs keep the file readable and the round trip exact.
    private struct DefaultPair: Codable { let kind: ProjectCapabilityKind; let effect: ProjectPolicyEffect }
    private struct NamedPair: Codable { let rule: ProjectGovernanceLogic.NamedRule; let effect: ProjectPolicyEffect }
    private enum CodingKeys: String, CodingKey { case enforcement, defaults, named }

    init(
        enforcement: ProjectEnforcementMode,
        defaults: [ProjectCapabilityKind: ProjectPolicyEffect],
        named: [ProjectGovernanceLogic.NamedRule: ProjectPolicyEffect]
    ) {
        self.enforcement = enforcement
        self.defaults = defaults
        self.named = named
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enforcement = try c.decode(ProjectEnforcementMode.self, forKey: .enforcement)
        defaults = Dictionary(
            (try c.decode([DefaultPair].self, forKey: .defaults)).map { ($0.kind, $0.effect) },
            uniquingKeysWith: { _, last in last }
        )
        named = Dictionary(
            (try c.decode([NamedPair].self, forKey: .named)).map { ($0.rule, $0.effect) },
            uniquingKeysWith: { _, last in last }
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enforcement, forKey: .enforcement)
        try c.encode(
            defaults.map { DefaultPair(kind: $0.key, effect: $0.value) }.sorted { $0.kind.rawValue < $1.kind.rawValue },
            forKey: .defaults
        )
        try c.encode(
            named.map { NamedPair(rule: $0.key, effect: $0.value) }
                .sorted { ($0.rule.kind.rawValue, $0.rule.name) < ($1.rule.kind.rawValue, $1.rule.name) },
            forKey: .named
        )
    }

    /// Whether this draft asks for anything the saved policy does not say.
    func differs(from policy: ProjectPolicy?, enforcement saved: ProjectEnforcementMode) -> Bool {
        enforcement != saved
            || defaults != ProjectGovernanceLogic.defaultEffects(policy)
            || named != ProjectGovernanceLogic.namedEffects(policy)
    }
}

/// Edits waiting on the computers, kept across launches.
///
/// Closing the app between Save and the computer's answer used to throw the
/// edit away; on the next launch Governance showed the old policy and nothing
/// said an edit had ever been made.
enum ProjectGovernanceDraftStore {
    private static var url: URL? {
        // A test host must neither read a person's drafts nor leave its own
        // behind for the next run: each test process gets a file of its own.
        if NSClassFromString("XCTestCase") != nil {
            return FileManager.default.temporaryDirectory.appendingPathComponent(
                "granttap-tests-\(ProcessInfo.processInfo.processIdentifier)-policy-drafts.json"
            )
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("GrantTap", isDirectory: true)
            .appendingPathComponent("project-policy-drafts.json")
    }

    static func load(from override: URL? = nil) -> [String: ProjectGovernanceDraft] {
        guard let url = override ?? url, let data = try? Data(contentsOf: url), data.count <= 512 * 1_024,
              let drafts = try? JSONDecoder().decode([String: ProjectGovernanceDraft].self, from: data)
        else { return [:] }
        return drafts
    }

    static func save(_ drafts: [String: ProjectGovernanceDraft], to override: URL? = nil) {
        guard let url = override ?? url else { return }
        if drafts.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(drafts) else { return }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            // The edit is still held in memory for this session.
        }
    }
}
