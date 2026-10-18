import Foundation

struct TurnModelGroup: Identifiable {
    let id: String
    let title: String
    let options: [TurnModelOption]
}

/// Keep provider family order; put the higher reasoning variants first.
/// Fast is a serving mode, not a claim of greater model capability.
enum TurnModelOrdering {
    static func sorted(_ options: [TurnModelOption], provider: String) -> [TurnModelOption] {
        guard provider == "cursor" else { return options }
        var families: [String] = []
        for option in options {
            let key = family(option.id)
            if !families.contains(key) { families.append(key) }
        }
        let positions = Dictionary(uniqueKeysWithValues: families.enumerated().map { ($0.element, $0.offset) })
        return options.enumerated().sorted { first, second in
            let a = first.element, b = second.element
            let af = family(a.id), bf = family(b.id)
            if af != bf { return positions[af, default: 0] < positions[bf, default: 0] }
            if reasoning(a.id) != reasoning(b.id) { return reasoning(a.id) > reasoning(b.id) }
            let aFast = a.id.hasSuffix("-fast"), bFast = b.id.hasSuffix("-fast")
            if aFast != bFast { return !aFast }
            return first.offset < second.offset
        }.map(\.element)
    }

    static func groups(_ options: [TurnModelOption], provider: String) -> [TurnModelGroup] {
        guard provider == "cursor" else { return [.init(id: "models", title: L("Model"), options: options)] }
        var ids: [String] = [], grouped: [String: [TurnModelOption]] = [:]
        for option in options {
            let key = family(option.id)
            if grouped[key] == nil { ids.append(key) }
            grouped[key, default: []].append(option)
        }
        return ids.map { id in
            let rows = grouped[id] ?? []
            let title = id == "auto" ? L("Automatic") : (rows.first?.label ?? id)
                .replacingOccurrences(of: #"(?:[ -]+(?:low|medium|high|xhigh|extra high|max|ultra|fast|thinking))+$"#,
                                      with: "", options: [.regularExpression, .caseInsensitive])
            return .init(id: id, title: title, options: rows)
        }
    }

    private static func family(_ id: String) -> String {
        id.replacingOccurrences(of: #"(?:-(?:low|medium|high|xhigh|max|ultra|fast|thinking))+$"#,
                                with: "", options: .regularExpression)
    }

    private static func reasoning(_ id: String) -> Int {
        for (name, rank) in [("ultra", 6), ("max", 5), ("xhigh", 4), ("high", 3), ("low", 1)] {
            if id.range(of: "(?:^|-)\(name)(?:-|$)", options: .regularExpression) != nil { return rank }
        }
        return 2
    }
}
