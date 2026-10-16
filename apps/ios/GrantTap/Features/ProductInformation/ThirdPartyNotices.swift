import Foundation

struct ThirdPartyNotice: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    let version: String
    let license: String
    let scope: String
    let source: URL
    let text: String
}

enum ThirdPartyNotices {
    static func load(bundle: Bundle = .main) throws -> [ThirdPartyNotice] {
        guard let url = bundle.url(forResource: "Product-third-party-notices", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([ThirdPartyNotice].self, from: Data(contentsOf: url))
    }
}
