import AuthenticationServices
import Foundation
import UIKit

struct GrantTapAccountSession: Codable {
    let accountId: String
    let token: String
}

enum AccountBridgeError: LocalizedError {
    case invalidResponse, unavailable, expired, storage

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return L("GrantTap could not verify this passkey response.")
        case .unavailable: return L("The GrantTap account service is unavailable.")
        case .expired: return L("This sign-in expired. Try again.")
        case .storage: return L("The account session could not be saved on this device.")
        }
    }
}

enum GrantTapAccountAPI {
    static let root = URL(string: "https://granttap.com/api/account/")!
    private static let keychainService = "com.ziborov.granttap.account-session"

    static var session: GrantTapAccountSession? {
        guard let data = KeychainPairing.load(service: keychainService) else { return nil }
        return try? JSONDecoder().decode(GrantTapAccountSession.self, from: data)
    }

    static func clearSession() { KeychainPairing.remove(service: keychainService) }

    @MainActor static func authenticate(register: Bool) async throws -> GrantTapAccountSession {
        let kind = register ? "registration" : "authentication"
        let ceremony = try await json("\(kind)/options", method: "POST")
        guard let ceremonyId = ceremony["ceremonyId"] as? String,
              let options = ceremony["options"] as? [String: Any],
              let challenge = decodeURL(options["challenge"] as? String),
              challenge.count >= 16 else { throw AccountBridgeError.invalidResponse }
        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: "granttap.com")
        let request: ASAuthorizationRequest
        if register {
            guard let user = options["user"] as? [String: Any],
                  let userId = decodeURL(user["id"] as? String),
                  let name = user["name"] as? String else {
                throw AccountBridgeError.invalidResponse
            }
            let registration = provider.createCredentialRegistrationRequest(
                challenge: challenge, name: name, userID: userId)
            registration.userVerificationPreference = .required
            request = registration
        } else {
            let assertion = provider.createCredentialAssertionRequest(challenge: challenge)
            assertion.userVerificationPreference = .required
            request = assertion
        }
        let authorization = AccountPasskeyAuthorization()
        let credential = try await authorization.perform(request)
        withExtendedLifetime(authorization) {}
        let publicResponse: [String: Any]
        if let row = credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
           let attestation = row.rawAttestationObject {
            let id = encodeURL(row.credentialID)
            publicResponse = ["id": id, "rawId": id, "type": "public-key",
                              "response": ["clientDataJSON": encodeURL(row.rawClientDataJSON),
                                           "attestationObject": encodeURL(attestation)],
                              "clientExtensionResults": [:]]
        } else if let row = credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion {
            let id = encodeURL(row.credentialID)
            publicResponse = ["id": id, "rawId": id, "type": "public-key",
                              "response": ["clientDataJSON": encodeURL(row.rawClientDataJSON),
                                           "authenticatorData": encodeURL(row.rawAuthenticatorData),
                                           "signature": encodeURL(row.signature),
                                           "userHandle": row.userID.map(encodeURL) as Any? ?? NSNull()],
                              "clientExtensionResults": [:]]
        } else { throw AccountBridgeError.invalidResponse }
        let verified = try await json("\(kind)/verify", method: "POST",
                                      body: ["ceremonyId": ceremonyId, "response": publicResponse])
        guard let accountId = verified["accountId"] as? String,
              let token = verified["token"] as? String, token.count == 43 else {
            throw AccountBridgeError.invalidResponse
        }
        let session = GrantTapAccountSession(accountId: accountId, token: token)
        guard KeychainPairing.save(try JSONEncoder().encode(session), service: keychainService) else {
            throw AccountBridgeError.storage
        }
        return session
    }

    static func json(_ path: String, method: String = "GET", body: [String: Any]? = nil,
                     token: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: root.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw AccountBridgeError.expired }
        guard (200...299).contains(status), data.count <= 32_768,
              let result = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw AccountBridgeError.unavailable }
        return result
    }

    static func encodeURL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decodeURL(_ text: String?) -> Data? {
        guard let text, text.range(of: "^[A-Za-z0-9_-]+$", options: .regularExpression) != nil else {
            return nil
        }
        let padded = text.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        return Data(base64Encoded: padded + String(repeating: "=", count: (4 - padded.count % 4) % 4))
    }
}

private final class AccountPasskeyAuthorization: NSObject, ASAuthorizationControllerDelegate,
                                                 ASAuthorizationControllerPresentationContextProviding {
    private var continuation: CheckedContinuation<ASAuthorizationCredential, Error>?
    private var controller: ASAuthorizationController?

    func perform(_ request: ASAuthorizationRequest) async throws -> ASAuthorizationCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            self.controller = controller
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        continuation?.resume(returning: authorization.credential)
        continuation = nil
        self.controller = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        self.controller = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
