import Foundation

/// One thing a person can learn about GrantTap, and what it is made of.
///
/// The app explains itself in the app. Everything below is written the way
/// the screens are: what the thing is, what it does not do, and what a person
/// sees when it happens.
struct LearnTopic: Identifiable, Equatable {
    let id: String
    let icon: String
    /// Untranslated keys; the screens ask for them by name at render time.
    let title: String
    let summary: String
    let body: [LearnBlock]
}

/// A paragraph, a list of points, or a line of terminal a person may copy.
enum LearnBlock: Equatable {
    case text(String)
    case points([String])
    case command(String)
    case heading(String)
}

enum LearnChapter: Identifiable, Equatable {
    case start, work, project, cost, trust

    var id: String {
        switch self {
        case .start: return "start"
        case .work: return "work"
        case .project: return "project"
        case .cost: return "cost"
        case .trust: return "trust"
        }
    }

    var title: String {
        switch self {
        case .start: return "Getting started"
        case .work: return "Working with an agent"
        case .project: return "Projects and people"
        case .cost: return "What it costs"
        case .trust: return "What leaves your devices"
        }
    }

    var topics: [LearnTopic] {
        switch self {
        case .start: return LearnLibrary.start
        case .work: return LearnLibrary.work
        case .project: return LearnLibrary.project
        case .cost: return LearnLibrary.cost
        case .trust: return LearnLibrary.trust
        }
    }

    static let all: [LearnChapter] = [.start, .work, .project, .cost, .trust]
}
