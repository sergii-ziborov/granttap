import Foundation

enum AppLocale {
    static let storageKey = "granttap.language"

    static var code: String {
#if DEBUG
        if let testCode = ProcessInfo.processInfo.environment["GRANTTAP_TEST_LANGUAGE"] {
            return testCode == "ru" ? "ru" : "en"
        }
#endif
        let saved = UserDefaults.standard.string(forKey: storageKey)
        return saved == "ru" ? "ru" : "en"
    }

    static var speechIdentifier: String {
        code == "ru" ? "ru-RU" : "en-US"
    }

    static func text(_ key: String) -> String {
        guard code != "en",
              let path = Bundle.main.path(forResource: code, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
}

func L(_ key: String) -> String {
    AppLocale.text(key)
}

/// A count with its noun in the right form. English has one and many;
/// Russian adds a form for two to four, kept under the many-key with a
/// `|few` suffix so English never meets it.
func LPlural(_ count: Int, one: String, many: String) -> String {
    let n = abs(count)
    let key: String
    if AppLocale.code == "ru" {
        let tail = n % 100
        let unit = n % 10
        if unit == 1 && tail != 11 {
            key = one
        } else if (2...4).contains(unit) && !(12...14).contains(tail) {
            key = many + "|few"
        } else {
            key = many
        }
    } else {
        key = n == 1 ? one : many
    }
    return String(format: L(key), count)
}

enum AppVersion {
    static var short: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    static var display: String {
        "\(short) (\(build))"
    }
}

/// Keeps common engineering names intact when a Russian dictation model emits
/// them phonetically. This is deliberately deterministic and runs locally on
/// both iPhone and Watch; it never sends dictated text to another service.
enum VoiceTextNormalizer {
    static let recognitionTerms = [
        "API", "APNs", "Apple Watch", "ChatGPT", "Claude", "Claude Code",
        "Cloudflare", "Codex", "Docker", "GitHub", "GPT", "HTTP", "iPhone",
        "JavaScript", "JSON", "Kubernetes", "MCP", "Next.js", "Node.js", "npm",
        "OpenAI", "PostgreSQL", "Python", "React", "React Native", "SQLite", "SQL",
        "Swift", "SwiftUI", "Tailwind", "TypeScript", "Vite", "WebSocket", "Xcode",
    ]

    private static let aliases: [(String, String)] = [
        ("эпл вотч", "Apple Watch"),
        ("swift ui", "SwiftUI"), ("node js", "Node.js"),
        ("next js", "Next.js"), ("type script", "TypeScript"),
        ("java script", "JavaScript"), ("git hub", "GitHub"),
        ("react native", "React Native"), ("web socket", "WebSocket"),
        ("open ai", "OpenAI"), ("chat gpt", "ChatGPT"),
        ("клауд код", "Claude Code"), ("клод код", "Claude Code"),
        ("клаудфлер", "Cloudflare"), ("клауд флер", "Cloudflare"),
        ("тайп скрипт", "TypeScript"), ("тайпскрипт", "TypeScript"),
        ("джава скрипт", "JavaScript"), ("джаваскрипт", "JavaScript"),
        ("свифт ю ай", "SwiftUI"), ("свифтюай", "SwiftUI"),
        ("нод джей эс", "Node.js"), ("ноуд джей эс", "Node.js"),
        ("эм си пи", "MCP"), ("эмсипи", "MCP"),
        ("джейсон", "JSON"), ("джей сон", "JSON"), ("джсон", "JSON"),
        ("гит хаб", "GitHub"), ("гитхаб", "GitHub"),
        ("икс код", "Xcode"), ("экс код", "Xcode"), ("икскод", "Xcode"),
        ("эн пи эм", "npm"), ("энпиэм", "npm"),
        ("эй пи ай", "API"), ("эйпиай", "API"),
        ("эс кью эль", "SQL"), ("эскьюэль", "SQL"),
        ("эйч ти ти пи", "HTTP"),
        ("постгрес", "PostgreSQL"), ("постгрескьюэль", "PostgreSQL"),
        ("кубернетес", "Kubernetes"), ("кубернетис", "Kubernetes"),
        ("пайтон", "Python"), ("питон", "Python"),
        ("айфон", "iPhone"), ("кодекс", "Codex"),
        ("докер", "Docker"), ("реакт натив", "React Native"), ("реакт", "React"),
        ("некст джей эс", "Next.js"), ("некстджейэс", "Next.js"),
        ("опен эй ай", "OpenAI"), ("опенэйай", "OpenAI"),
        ("чат джи пи ти", "ChatGPT"), ("джи пи ти", "GPT"),
        ("веб сокет", "WebSocket"), ("вебсокет", "WebSocket"),
        ("скьюлайт", "SQLite"), ("эс кью лайт", "SQLite"),
        ("эй пи эн эс", "APNs"), ("виит", "Vite"), ("вайт", "Vite"),
        ("тэйлвинд", "Tailwind"), ("тейлвинд", "Tailwind"),
    ]

    static func normalize(_ source: String) -> String {
        var result = source
        for (alias, canonical) in aliases {
            let escaped = NSRegularExpression.escapedPattern(for: alias)
            guard let regex = try? NSRegularExpression(
                pattern: "(?iu)(?<![\\p{L}\\p{N}_])\(escaped)(?![\\p{L}\\p{N}_])"
            ) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: canonical)
        }
        if let punctuation = try? NSRegularExpression(pattern: "\\s+([,.;:!?])") {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = punctuation.stringByReplacingMatches(in: result, range: range, withTemplate: "$1")
        }
        return result
    }

    static func isKnownTechnology(_ value: String) -> Bool {
        let folded = normalize(value)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .punctuationCharacters.union(.whitespacesAndNewlines))
        return recognitionTerms.contains {
            $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == folded
        }
    }
}
