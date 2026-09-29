import SwiftUI

struct ProductInformationView: View {
    let information: ProductInformation

    var body: some View {
        if information == .about {
            AboutGrantTapView()
        } else {
            ProductDocumentView(information: information)
        }
    }
}

struct ProductInformationLinks: View {
    var includesHelp = true

    private var items: [ProductInformation] {
        (includesHelp ? [.help] : []) + [.terms, .privacy, .licenses, .pricing]
    }

    var body: some View {
        ForEach(items, id: \.self) { item in
            NavigationLink(item.title) { ProductInformationView(information: item) }
                .accessibilityIdentifier("information.\(item.rawValue)")
        }
    }
}

private struct ProductDocumentView: View {
    let information: ProductInformation
    @AppStorage(AppLocale.storageKey) private var language = "en"

    var body: some View {
        List {
            if let document = try? ProductDocument.load(information, language: language) {
                Section {
                    Text(document.intro).textSelection(.enabled)
                    Text(L("Last updated") + ": " + document.updated)
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                if information == .help {
                    Section(L("Guides")) {
                        NavigationLink(L("Learn")) { LearnView() }
                            .accessibilityIdentifier("information.learn")
                        NavigationLink(L("Troubleshooting")) { TroubleshootingView() }
                        NavigationLink(L("Pricing and connection modes")) {
                            ProductInformationView(information: .pricing)
                        }
                    }
                }
                ForEach(Array(document.sections.enumerated()), id: \.offset) { _, section in
                    Section {
                        ForEach(section.paragraphs ?? [], id: \.self) { Text($0).textSelection(.enabled) }
                        ForEach(section.bullets ?? [], id: \.self) { item in
                            HStack(alignment: .top) {
                                Text("•").accessibilityHidden(true)
                                Text(item).textSelection(.enabled)
                            }
                        }
                        ForEach(section.links ?? [], id: \.href) { link in
                            if let url = link.url { Link(link.label, destination: url) }
                        }
                    } header: {
                        Text(section.heading).textCase(nil)
                    }
                }
                Section(L("Support")) {
                    Link("sergii.ziborov@gmail.com", destination: URL(string: "mailto:sergii.ziborov@gmail.com")!)
                    if let name = information.documentName {
                        Link(L("Read on the website"), destination: URL(string: "https://granttap.com/\(name)")!)
                    }
                }
            } else {
                Section {
                    Text(L("This document could not be loaded."))
                    Link(L("Support"), destination: URL(string: "https://granttap.com/support")!)
                }
            }
        }
        .pageNavigationTitle(information.title)
        .accessibilityIdentifier("information.page.\(information.rawValue)")
    }
}
