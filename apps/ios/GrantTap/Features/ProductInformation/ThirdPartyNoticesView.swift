import SwiftUI

struct ThirdPartyNoticesView: View {
    var body: some View {
        List {
            if let notices = try? ThirdPartyNotices.load() {
                Section {
                    Text(L("These components keep their original licenses. Full license texts are available here offline. The separate MCP and Engine carry their own notices."))
                }
                ForEach(notices) { notice in
                    NavigationLink {
                        ThirdPartyNoticeDetail(notice: notice)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(notice.name).font(.headline)
                            Text("\(notice.version) · \(notice.license)")
                                .font(.caption).foregroundStyle(Theme.muted)
                            Text(L(notice.scope)).font(.caption2).foregroundStyle(Theme.muted)
                        }
                    }
                    .accessibilityIdentifier("information.notice.\(notice.id)")
                }
            } else {
                Text(L("This document could not be loaded."))
            }
        }
        .pageNavigationTitle(L("Third-party notices"))
    }
}

struct ThirdPartyNoticeDetail: View {
    let notice: ThirdPartyNotice

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(notice.name) \(notice.version) · \(notice.license)").font(.headline)
                Text(L(notice.scope)).foregroundStyle(Theme.muted)
                Text(notice.text).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Link(L("Source"), destination: notice.source)
            }
            .padding()
            .frame(maxWidth: 850, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .pageNavigationTitle(notice.name)
    }
}
