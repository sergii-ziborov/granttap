import SwiftUI

extension Format {
    static func latencyMs(_ milliseconds: Int) -> String {
        milliseconds < 1_000
            ? "\(milliseconds) ms"
            : String(format: "%.1f s", Double(milliseconds) / 1_000)
    }
}

struct MCPIdentity {
    let name: String

    /// Canonical brand spellings the generic title-caser cannot infer from a
    /// single lowercase token (e.g. "granttap" would otherwise read "Granttap").
    private static let brandNames: [String: String] = [
        "granttap": "GrantTap",
        "github": "GitHub",
    ]

    /// A configured key that is an identifier rather than a name someone chose.
    ///
    /// Some servers are registered under a UUID. Title-casing its segments
    /// produces "4e69538b Cf6e 4c6c" — longer, still unreadable, and no longer
    /// matching the id it came from.
    var isOpaqueIdentifier: Bool {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return UUID(uuidString: value) != nil
            || (value.count >= 24 && value.allSatisfy { $0.isHexDigit || $0 == "-" })
    }

    var displayName: String {
        let key = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let brand = Self.brandNames[key] { return brand }
        // An id is shortened rather than dressed up: the head still identifies
        // it, and nothing pretends a name was chosen.
        if isOpaqueIdentifier {
            return "MCP " + name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(8)
        }
        return name.split(separator: "-").map { part in
            let value = String(part)
            return value.count <= 3 ? value.uppercased() : value.prefix(1).uppercased() + String(value.dropFirst())
        }.joined(separator: " ")
    }

    /// Human-facing leaf of a fully-qualified MCP tool id: the segment after the
    /// final `__` in `mcp__server__tool`. Names without `__` pass through.
    static func shortToolName(_ toolName: String) -> String {
        guard let range = toolName.range(of: "__", options: .backwards) else {
            return toolName
        }
        return String(toolName[range.upperBound...])
    }
}

extension McpServerInfo {
    var displayTitle: String {
        guard metadataSource == "mcp", let title, !title.isEmpty else {
            return MCPIdentity(name: name).displayName
        }
        return title
    }

    func preferredIcon(for colorScheme: ColorScheme) -> McpIconInfo? {
        guard metadataSource == "mcp" else { return nil }
        let theme = colorScheme == .dark ? "dark" : "light"
        return icons?.first(where: { $0.theme == theme }) ?? icons?.first
    }
}

struct MCPBadge: View {
    let name: String
    var size: CGFloat = 30
    var showsName = false
    var server: McpServerInfo?
    @Environment(\.colorScheme) private var colorScheme

    private var identity: MCPIdentity { MCPIdentity(name: name) }
    private var displayName: String { server?.displayTitle ?? identity.displayName }
    private var icon: McpIconInfo? { server?.preferredIcon(for: colorScheme) }

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                MCPServerIcon(icon: icon, size: size)
                    .id(icon.src)
            } else {
                Image(systemName: "shippingbox")
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: size, height: size)
                    .background(Theme.raised,
                                in: RoundedRectangle(cornerRadius: size * 0.3,
                                                     style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                        .stroke(Theme.line, lineWidth: 1))
            }
            if showsName {
                Text(displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("MCP \(displayName)")
    }
}

struct CapabilitySummary: Identifiable {
    let kind: CapabilityUsageKind
    let name: String
    let agent: String?
    let model: String?
    let count: Int
    let lastUsedAt: Double
    let estimatedContextTokens: Int
    let estimatedTokensSaved: Int
    let averageDurationMs: Int?
    let latestCommandPreview: String?
    var id: String { CapabilityUsageGrouping.key(agent: agent, model: model, kind: kind, name: name) }
}

enum CapabilityUsageGrouping {
    static func key(agent: String?, model: String?,
                    kind: CapabilityUsageKind, name: String) -> String {
        let agent = agent.map(AgentIdentity.normalize) ?? "unknown"
        let model = model?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return "\(agent):\(model):\(kind.rawValue):\(name)"
    }
}
