import Foundation
import StoreKit

/// Apple's verified sandbox transaction identifies non-production testing,
/// including TestFlight and App Review. It does not prove a paid purchase.
@MainActor
enum TestFlightAccessStore {
    static func current() async -> Bool {
        await signedEvidence() != nil
    }

    static func signedEvidence() async -> String? {
        guard !AppRuntime.isRunningUnitTests,
              #available(iOS 16.0, macCatalyst 16.0, *),
              let result = try? await AppTransaction.shared, accepts(result) else { return nil }
        return result.jwsRepresentation
    }

    static func refresh() async throws -> Bool {
        guard #available(iOS 16.0, macCatalyst 16.0, *) else { return false }
        return accepts(try await AppTransaction.refresh())
    }

    @available(iOS 16.0, macCatalyst 16.0, *)
    private static func accepts(_ result: VerificationResult<AppTransaction>) -> Bool {
        guard case .verified(let transaction) = result else { return false }
        return transaction.environment == .sandbox
            && transaction.bundleID == Bundle.main.bundleIdentifier
    }
}
