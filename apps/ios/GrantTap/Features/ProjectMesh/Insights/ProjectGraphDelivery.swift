import Foundation

/// A transport acknowledgement has a deadline even if its callback never arrives.
@MainActor
final class ProjectGraphDelivery {
    private var continuation: CheckedContinuation<Void, Error>?

    func send(timeoutNanoseconds: UInt64 = 12_000_000_000,
              operation: (@escaping (Error?) -> Void) -> Void) async throws {
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { waiting in
                continuation = waiting
                operation { [weak self] error in
                    Task { @MainActor in self?.finish(error) }
                }
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                    self?.finish(URLError(.timedOut))
                }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in self?.finish(CancellationError()) }
        })
    }

    private func finish(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
    }
}
