import Foundation
import OSLog
import SwiftUI

enum NotificationPrivacy {
    static let hideDetailsKey = "granttap.security.hide-notification-details"
    static var hidesDetails: Bool { UserDefaults.standard.bool(forKey: hideDetailsKey) }
}

@MainActor
final class AuditStore: ObservableObject {
    static let shared = AuditStore()
    private static let persistenceLogger = Logger(subsystem: "com.ziborov.granttap",
                                                  category: "audit")
    @Published private(set) var events: [AuditEvent] = []

    init(loadPersisted: Bool = true, initialEvents: [AuditEvent]? = nil) {
        events = initialEvents ?? (loadPersisted ? Self.load() : [])
    }

    func record(_ action: String, detail: String, outcome: String = "ok") {
        let clean = detail.replacingOccurrences(of: "\n", with: " ").prefix(240)
        events.insert(AuditEvent(id: UUID().uuidString.lowercased(),
                                 createdAt: Date().timeIntervalSince1970 * 1000,
                                 action: action, detail: String(clean), outcome: outcome), at: 0)
        if events.count > 500 { events.removeLast(events.count - 500) }
        persist()
    }

    func clear() {
        events = []
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        do {
            try FileManager.default.createDirectory(at: Self.directoryURL,
                                                    withIntermediateDirectories: true)
            try data.write(to: Self.fileURL,
                           options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Self.persistenceLogger.error("Audit history write failed (code: \((error as NSError).code, privacy: .public))")
        }
    }

    private static func load() -> [AuditEvent] {
        guard let data = try? Data(contentsOf: fileURL),
              let value = try? JSONDecoder().decode([AuditEvent].self, from: data) else { return [] }
        return Array(value.prefix(500))
    }

    private static var directoryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GrantTap", isDirectory: true)
    }
    private static var fileURL: URL { directoryURL.appendingPathComponent("audit-log.json") }
}
