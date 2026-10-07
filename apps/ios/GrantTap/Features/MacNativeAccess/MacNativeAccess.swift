#if targetEnvironment(macCatalyst)
import AuthenticationServices
import CryptoKit
import Foundation
import UIKit

private enum MacNativeAccountAuthorizationError: LocalizedError {
    case denied
    var errorDescription: String? {
        L("This passkey could not authorize the local Mac service. Update GrantTap MCP, check the account, and try again.")
    }
}

@MainActor
final class MacNativeAccess: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = MacNativeAccess()
    private static let credentialService = "com.ziborov.granttap.desktop-access"
    @Published private(set) var busy = false
    @Published private(set) var lastError: String?
    private var session: ASWebAuthenticationSession?
    private var accountAuthorization: Task<Void, Error>?

    static var baseURL: URL {
        let port = Int(ProcessInfo.processInfo.environment["GRANTTAP_MCP_HTTP_PORT"] ?? "17342") ?? 17342
        return URL(string: "http://127.0.0.1:\((1...65_535).contains(port) ? port : 17342)")!
    }

    var token: String? {
        guard let bytes = KeychainPairing.load(service: Self.credentialService),
              let token = String(data: bytes, encoding: .utf8), token.count == 43 else { return nil }
        return token
    }

    func linkAccount(_ accountToken: String) async throws {
        if token == nil {
            try await authorizeWithAccount(accountToken)
            return
        }
        guard let token else { throw MacLocalMCPError.untrusted }
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("desktop/account/link"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["accountToken": accountToken])
        do { _ = try await MacNativeTransport.fetch(request, limit: 2_048, timeout: 35) }
        catch { try await authorizeWithAccount(accountToken) }
    }

    func authorizeWithAccount(_ accountToken: String) async throws {
        if let accountAuthorization { try await accountAuthorization.value; return }
        let attempt = Task { try await exchangeAccountToken(accountToken) }
        accountAuthorization = attempt
        defer { accountAuthorization = nil }
        try await attempt.value
    }

    private func exchangeAccountToken(_ accountToken: String) async throws {
        busy = true
        defer { busy = false }
        do {
            var request = URLRequest(url: Self.baseURL.appendingPathComponent("desktop/account/authorize"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["accountToken": accountToken])
            let bytes = try await MacNativeTransport.fetch(request, limit: 2_048, timeout: 35)
            try saveAccessToken(bytes)
            session?.cancel()
            lastError = nil
        } catch {
            lastError = MacNativeAccountAuthorizationError.denied.localizedDescription
            throw MacNativeAccountAuthorizationError.denied
        }
    }

    private func saveAccessToken(_ bytes: Data) throws {
        guard let response = try JSONSerialization.jsonObject(with: bytes) as? [String: String],
              let token = response["access_token"],
              token.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              KeychainPairing.save(Data(token.utf8), service: Self.credentialService) else {
            throw MacLocalMCPError.untrusted
        }
    }

    func authorize() async {
        guard !busy else { return }
        do {
            try await Self.authorize(
                accountToken: GrantTapAccountAPI.session?.token,
                usingAccount: { try await self.authorizeWithAccount($0) },
                usingLocalConsent: { try await self.authorizeLocally() }
            )
            lastError = nil
        } catch {
            if token == nil {
                lastError = L("Local Mac authorization was not completed. Try again from Settings.")
            }
        }
    }

    static func authorize(
        accountToken: String?,
        usingAccount: (String) async throws -> Void,
        usingLocalConsent: () async throws -> Void
    ) async throws {
        if let accountToken {
            do { try await usingAccount(accountToken); return }
            catch { /* A saved passkey session must not prevent local recovery. */ }
        }
        try await usingLocalConsent()
    }

    private func authorizeLocally() async throws {
        busy = true
        defer { busy = false; session = nil }
        let verifier = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let state = UUID().uuidString
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        var url = URLComponents(url: Self.baseURL.appendingPathComponent("desktop/authorize"), resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "challenge", value: challenge), URLQueryItem(name: "state", value: state)]
        let callback = try await browser(url.url!)
        let code = try Self.authorizationCode(callback, expectedState: state)
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("desktop/token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["code": code, "verifier": verifier])
        let bytes = try await MacNativeTransport.fetch(request, limit: 2_048, timeout: 35)
        try saveAccessToken(bytes)
    }

    static func authorizationCode(_ url: URL, expectedState: String) throws -> String {
        guard url.scheme == "granttap", url.host == "desktop-auth",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.queryItems?.filter({ $0.name == "state" }).count == 1,
              parts.queryItems?.first(where: { $0.name == "state" })?.value == expectedState,
              parts.queryItems?.filter({ $0.name == "code" }).count == 1,
              let code = parts.queryItems?.first(where: { $0.name == "code" })?.value,
              code.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil else {
            throw MacLocalMCPError.untrusted
        }
        return code
    }

    private func browser(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            session = ASWebAuthenticationSession(url: url, callbackURLScheme: "granttap") { callback, error in
                if let callback { continuation.resume(returning: callback) }
                else { continuation.resume(throwing: error ?? MacLocalMCPError.unavailable) }
            }
            session?.presentationContextProvider = self
            session?.prefersEphemeralWebBrowserSession = true
            if session?.start() != true { continuation.resume(throwing: MacLocalMCPError.unavailable) }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
#endif
