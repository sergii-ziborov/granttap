import Foundation

/// A slider position always names an advertised level, never an invented one.
struct EffortScale {
    let choices: [TurnEffort]
    let selection: TurnEffort?
    let fallback: TurnEffort?

    var effective: TurnEffort? {
        if let selection, choices.contains(selection) { return selection }
        if let fallback, choices.contains(fallback) { return fallback }
        return nil
    }

    var index: Int? { effective.flatMap { choices.firstIndex(of: $0) } }
    var fraction: Double { Double(index ?? 0) / Double(max(1, choices.count - 1)) }

    func choice(at fraction: Double) -> TurnEffort? {
        guard !choices.isEmpty, fraction.isFinite else { return nil }
        let index = Int((min(1, max(0, fraction)) * Double(choices.count - 1)).rounded())
        return choices[index]
    }
}

struct EffortParticle: Equatable {
    let x: Double
    let y: Double
    let opacity: Double
    let size: Double
}

/// Deterministic, bounded motion used only while the effort picker is visible.
enum EffortMotion {
    static func particles(for effort: TurnEffort, time: Double, reduceMotion: Bool) -> [EffortParticle] {
        let level = TurnEffort.allCases.firstIndex(of: effort) ?? 0
        let count = [8, 12, 18, 28, 36, 48][level]
        let clock = reduceMotion ? 0 : time
        return (0..<count).map { index in
            let seed = Double(index) * 0.61803398875
            let phase = (clock * (0.055 + Double(level) * 0.018) + seed)
                .truncatingRemainder(dividingBy: 1)
            return EffortParticle(x: phase, y: 0.5 + sin(seed * 17 + clock * 0.3) * 0.36,
                opacity: 0.2 + (sin(seed * 11 + clock) + 1) * 0.22,
                size: effort == .max ? 2.5 : 1.4 + Double(index % 3) * 0.65)
        }
    }
}
