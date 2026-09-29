import Foundation

enum ProductInformation: String, CaseIterable, Hashable {
    case about, help, terms, privacy, licenses, pricing

    var title: String {
        switch self {
        case .about: return L("About GrantTap")
        case .help: return L("GrantTap Help")
        case .terms: return L("Terms of Use")
        case .privacy: return L("Privacy Policy")
        case .licenses: return L("Licenses")
        case .pricing: return L("Pricing and connection modes")
        }
    }

    var documentName: String? {
        switch self {
        case .about: return nil
        case .help: return "support"
        default: return rawValue
        }
    }

    static let requested = Notification.Name("granttap.product-information.requested")

    func open(in center: NotificationCenter = .default) {
        center.post(name: Self.requested, object: self)
    }
}

struct ProductDocument: Decodable, Equatable {
    struct Section: Decodable, Equatable {
        let heading: String
        let paragraphs: [String]?
        let bullets: [String]?
        let links: [DocumentLink]?
    }

    struct DocumentLink: Decodable, Equatable {
        let label: String
        let href: String

        var url: URL? {
            let value = href.hasPrefix("/") ? "https://granttap.com" + href : href
            guard let url = URL(string: value), ["https", "mailto"].contains(url.scheme) else { return nil }
            return url
        }
    }

    let title: String
    let updated: String
    let intro: String
    let sections: [Section]

    static func load(_ information: ProductInformation, language: String = AppLocale.code,
                     bundle: Bundle = .main) throws -> Self {
        guard let name = information.documentName,
              let url = bundle.url(forResource: "Product-\(name)-\(language == "ru" ? "ru" : "en")",
                                   withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    }
}
