import Foundation

/// What the single control at the end of the compose field does right now.
///
/// Splitting this across two places — a send arrow that appeared only once you
/// had typed, plus a bare "Done" floating above the keyboard — meant the button
/// you needed was never reliably in the same spot.
enum ComposerAction: Equatable {
    /// Nothing to send and nothing to dismiss: the composer is at rest.
    case none
    /// The field is open but empty; the useful action is to get out of the way.
    case dismiss
    /// There is something worth sending.
    case send

    var isVisible: Bool { self != .none }

    var systemImage: String {
        switch self {
        case .send: return "arrow.up"
        // The standard iOS idiom for "put the keyboard away".
        case .dismiss: return "keyboard.chevron.compact.down"
        case .none: return ""
        }
    }

    static func resolve(hasContent: Bool, isFocused: Bool) -> ComposerAction {
        if hasContent { return .send }
        return isFocused ? .dismiss : .none
    }

    static func resolve(text: String, attachments: Int, isFocused: Bool) -> ComposerAction {
        let typed = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return resolve(hasContent: typed || attachments > 0, isFocused: isFocused)
    }
}
