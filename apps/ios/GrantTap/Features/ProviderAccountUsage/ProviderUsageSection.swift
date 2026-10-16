import SwiftUI

struct ProviderUsageSection: View {
    @ObservedObject var model: AppModel
    let sessions: [SessionInfo]

    private var catalogs: [ProjectEndpointModelCatalog] { model.meshSnapshots.values.flatMap { $0.modelCatalog ?? [] } }

    var body: some View {
        let byProvider = Dictionary(grouping: sessions) { AgentIdentity.normalize($0.agent) }
        let catalogs = self.catalogs
        Section(L("Providers and models")) {
            ForEach(["claude", "codex", "cursor", "grok"], id: \.self) { provider in
                let chats = byProvider[provider] ?? []
                let rows = ProviderAccountUsageRow.resolve(catalogs, provider: provider)
                DisclosureGroup {
                    if rows.isEmpty {
                        Text(L("Subscription limits have not been reported by this provider."))
                            .font(.caption).foregroundStyle(Theme.muted)
                    } else { ProviderAccountUsageRows(rows: rows) }
                    ForEach(Array(Set(chats.compactMap(\.model))).sorted(), id: \.self) { name in
                        let matching = chats.filter { $0.model == name }
                        NavigationLink {
                            UsageChatsView(title: name, sessions: matching, order: .tokens)
                        } label: {
                            HStack {
                                Text(name).lineLimit(1)
                                Spacer()
                                Text(String(format: L("%d chats"), matching.count))
                                    .font(.caption).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    if chats.isEmpty { Text(L("No reported sessions in this period.")).font(.caption).foregroundStyle(Theme.muted) }
                } label: {
                    HStack {
                        AgentGlyph(agent: provider, size: 24)
                        Text(AgentIdentity.displayName(provider))
                        Spacer()
                        Text("\(chats.count)").foregroundStyle(Theme.muted)
                    }
                }
                .accessibilityIdentifier("usage.provider.\(provider)")
            }
        }
    }
}
