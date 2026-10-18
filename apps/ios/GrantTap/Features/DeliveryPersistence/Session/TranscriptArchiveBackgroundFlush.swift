import UIKit

/// iOS gets a bounded background window to finish writes before suspension.
@MainActor
enum TranscriptArchiveBackgroundFlush {
    static func start(_ application: UIApplication) {
        let lease = TranscriptArchiveBackgroundLease(application)
        lease.token = application.beginBackgroundTask(withName: "granttap.transcript-archive") { lease.end() }
        SessionActivityPersistence.finish {
            ProjectMeshPersistence.finish {
                DispatchQueue.main.async { lease.end() }
            }
        }
    }
}

@MainActor
private final class TranscriptArchiveBackgroundLease {
    let application: UIApplication
    var token = UIBackgroundTaskIdentifier.invalid
    init(_ application: UIApplication) { self.application = application }
    func end() {
        guard token != .invalid else { return }
        application.endBackgroundTask(token)
        token = .invalid
    }
}
