import LocalAuthentication

enum DeviceOwnerAuthResult: Equatable {
    case success
    case failure(String?)
    case unavailable(String?)
}

@MainActor
protocol DeviceOwnerAuthenticating {
    var biometryName: String { get }
    func authenticate(
        reason: String,
        completion: @escaping @MainActor (DeviceOwnerAuthResult) -> Void
    )
}

@MainActor
struct LocalDeviceOwnerAuthenticator: DeviceOwnerAuthenticating {
    private let contextFactory: () -> LAContext

    init(contextFactory: @escaping () -> LAContext = { LAContext() }) {
        self.contextFactory = contextFactory
    }

    var biometryName: String {
        let context = contextFactory()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return L("Face ID")
        }
    }

    func authenticate(
        reason: String,
        completion: @escaping @MainActor (DeviceOwnerAuthResult) -> Void
    ) {
        let context = contextFactory()
        context.localizedCancelTitle = L("Cancel")
        context.localizedFallbackTitle = ""
        var biometricError: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(
            .deviceOwnerAuthenticationWithBiometrics, error: &biometricError
        ) ? .deviceOwnerAuthenticationWithBiometrics : .deviceOwnerAuthentication
        var evaluationError: NSError?
        guard context.canEvaluatePolicy(policy, error: &evaluationError) else {
            let message = evaluationError?.localizedDescription
                ?? L("Face ID is unavailable. Use PIN.")
            completion(.unavailable(message))
            return
        }
        context.evaluatePolicy(policy, localizedReason: reason) { success, error in
            Task { @MainActor in
                completion(success ? .success : .failure(error?.localizedDescription))
            }
        }
    }
}
