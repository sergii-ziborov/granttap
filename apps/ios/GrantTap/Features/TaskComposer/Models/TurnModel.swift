import Foundation

/// Persist provider identifiers without freezing them to one released generation.
struct TurnModel: RawRepresentable, Hashable, Identifiable {
    let rawValue: String
    var id: String { rawValue }

    init?(rawValue: String) {
        guard rawValue.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9._:/-]{0,159}$"#,
                             options: .regularExpression) != nil else { return nil }
        self.rawValue = rawValue
    }

    static let opus = TurnModel(rawValue: "opus")!
    static let sonnet = TurnModel(rawValue: "sonnet")!
    static let haiku = TurnModel(rawValue: "haiku")!
    static let fable = TurnModel(rawValue: "fable")!
    // Keep persisted choices from earlier versions readable.
    static let gpt56Sol = TurnModel(rawValue: "gpt-5.6-sol")!
    static let gpt56Terra = TurnModel(rawValue: "gpt-5.6-terra")!
    static let gpt56Luna = TurnModel(rawValue: "gpt-5.6-luna")!
    static let gpt55 = TurnModel(rawValue: "gpt-5.5")!
    static let allCases: [TurnModel] = [.opus, .sonnet, .haiku, .fable,
        .gpt56Sol, .gpt56Terra, .gpt56Luna, .gpt55]

    var label: String {
        switch rawValue {
        case "opus": return "Opus"
        case "sonnet": return "Sonnet"
        case "haiku": return "Haiku"
        case "fable": return "Fable"
        default:
            return rawValue.hasPrefix("gpt-")
                ? rawValue.replacingOccurrences(of: "gpt-", with: "GPT-") : rawValue
        }
    }

    /// These are CLI aliases, whose concrete version the installed provider resolves.
    static func supported(by agent: String) -> [TurnModel] {
        AgentIdentity.normalize(agent) == "claude" ? [.opus, .sonnet, .haiku, .fable] : []
    }

    func accepted(by agent: String) -> Bool {
        let claude = Self.supported(by: "claude").contains(self) || rawValue.hasPrefix("claude-")
        switch AgentIdentity.normalize(agent) {
        case "claude": return claude
        case "codex": return !claude
        default: return false
        }
    }
}
