import SwiftUI

/// "+12 −3", the way git says it: what a file tool put in and took out.
struct DiffStatsBadge: View {
    let added: Int
    let removed: Int

    var body: some View {
        HStack(spacing: 3) {
            if added > 0 {
                Text("+\(added)").foregroundStyle(Theme.ok)
            }
            if removed > 0 {
                Text("−\(removed)").foregroundStyle(Theme.riskHigh)
            }
        }
        .font(.system(size: 9, weight: .heavy, design: .monospaced))
        .accessibilityLabel(String(format: L("%d lines added, %d removed"), added, removed))
        .accessibilityIdentifier("chat.diff")
    }
}

/// One line of a change and how it reads: added, removed, kept, or the note
/// that more was left out.
enum DiffLineKind: Equatable {
    case added, removed, context, note

    static func of(_ line: String) -> DiffLineKind {
        if line.hasPrefix("+") { return .added }
        if line.hasPrefix("-") || line.hasPrefix("−") { return .removed }
        if line.hasPrefix("…") { return .note }
        return .context
    }
}

/// The lines of a change, coloured the way git colours them.
struct DiffPreviewView: View {
    let text: String

    var lines: [String] { text.components(separatedBy: "\n") }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                let kind = DiffLineKind.of(line)
                Text(line.isEmpty ? " " : line)
                    .font(Theme.mono(11))
                    .foregroundStyle(Self.ink(kind))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 1.5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Self.ground(kind))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .accessibilityIdentifier("chat.diff.preview")
    }

    static func ink(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .added: return Theme.ok
        case .removed: return Theme.riskHigh
        case .context: return Theme.muted
        case .note: return Theme.muted
        }
    }

    static func ground(_ kind: DiffLineKind) -> Color {
        switch kind {
        case .added: return Theme.ok.opacity(0.12)
        case .removed: return Theme.riskHigh.opacity(0.12)
        case .context, .note: return .clear
        }
    }
}
