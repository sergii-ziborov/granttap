import Foundation

/// Confirmation only reads status. Checking again cannot prepare another chat.
@MainActor
enum TaskHandoffConfirmationPoller {
    static func wait(lookup: () -> TaskHandoffOutcome, destinationAvailable: (String) -> Bool,
                     observing: () -> Bool, attempts: Int = 120,
                     pause: () async throws -> Void = {
                         try await Task.sleep(nanoseconds: 500_000_000)
                     }) async -> TaskHandoffOutcome? {
        for _ in 0..<attempts {
            guard observing() else { return nil }
            let outcome = lookup()
            switch outcome {
            case .prepared(let destination):
                if destinationAvailable(destination) { return outcome }
            case .failed: return outcome
            case .waiting: break
            }
            do { try await pause() } catch { return nil }
        }
        return .waiting
    }
}
