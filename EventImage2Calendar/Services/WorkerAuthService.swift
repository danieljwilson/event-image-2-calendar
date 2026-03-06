import Foundation
import CryptoKit
import Security

enum WorkerAuthService {
    private static let workerBaseURL = URL(string: "https://event-digest-worker.daniel-j-wilson-587.workers.dev")!
    private static let keychainService = "com.eventsnap.EventImage2Calendar.worker-auth"
    private static let deviceIDAccount = "worker-device-id"
    private static let privateKeyAccount = "worker-private-key"
    private static let tokenCache = AccessTokenCache()

    private struct RegisterRequest: Encodable {
        let deviceId: String
        let publicKey: String
        let timestamp: Int64
        let signature: String
    }

    private struct TokenRequest: Encodable {
        let deviceId: String
        let timestamp: Int64
        let signature: String
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresAt: Int64
    }

    static func accessToken() async -> String? {
        if let cached = await tokenCache.validToken() {
            return cached
        }

        guard let privateKey = loadOrCreatePrivateKey() else { return nil }
        let deviceID = loadOrCreateDeviceID()
        let publicKey = base64url(privateKey.publicKey.rawRepresentation)

        let registerTimestamp = Int64(Date().timeIntervalSince1970)
        guard let registerSignature = sign(
            message: "register:\(deviceID):\(registerTimestamp)",
            with: privateKey
        ) else { return nil }

        let registerBody = RegisterRequest(
            deviceId: deviceID,
            publicKey: publicKey,
            timestamp: registerTimestamp,
            signature: registerSignature
        )

        guard await postJSON(registerBody, path: "auth/register", expectedStatuses: [200, 201]) != nil else {
            return nil
        }

        let tokenTimestamp = Int64(Date().timeIntervalSince1970)
        guard let tokenSignature = sign(
            message: "token:\(deviceID):\(tokenTimestamp)",
            with: privateKey
        ) else { return nil }

        let tokenBody = TokenRequest(
            deviceId: deviceID,
            timestamp: tokenTimestamp,
            signature: tokenSignature
        )

        guard let responseData = await postJSON(tokenBody, path: "auth/token", expectedStatuses: [200]),
              let tokenResponse = try? JSONDecoder().decode(TokenResponse.self, from: responseData) else {
            return nil
        }

        await tokenCache.store(token: tokenResponse.accessToken, expiresAtUnix: tokenResponse.expiresAt)
        return tokenResponse.accessToken
    }

    private static func postJSON<T: Encodable>(
        _ body: T,
        path: String,
        expectedStatuses: Set<Int>
    ) async -> Data? {
        let endpoint = workerBaseURL.appendingPathComponent(path)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  expectedStatuses.contains(httpResponse.statusCode) else {
                return nil
            }
            return data
        } catch {
            return nil
        }
    }

    private static func sign(message: String, with privateKey: P256.Signing.PrivateKey) -> String? {
        guard let payload = message.data(using: .utf8),
              let signature = try? privateKey.signature(for: payload) else {
            return nil
        }
        return base64url(signature.rawRepresentation)
    }

    private static func loadOrCreateDeviceID() -> String {
        if let existing = keychainRead(account: deviceIDAccount),
           let value = String(data: existing, encoding: .utf8),
           !value.isEmpty {
            return value
        }

        let deviceID = UUID().uuidString
        _ = keychainWrite(data: Data(deviceID.utf8), account: deviceIDAccount)
        return deviceID
    }

    private static func loadOrCreatePrivateKey() -> P256.Signing.PrivateKey? {
        if let stored = keychainRead(account: privateKeyAccount),
           let key = try? P256.Signing.PrivateKey(rawRepresentation: stored) {
            return key
        }

        let newKey = P256.Signing.PrivateKey()
        guard keychainWrite(data: newKey.rawRepresentation, account: privateKeyAccount) else {
            return nil
        }
        return newKey
    }

    private static func keychainRead(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    @discardableResult
    private static func keychainWrite(data: Data, account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]

        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        return status == errSecSuccess
    }

    private static func base64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private actor AccessTokenCache {
    private var token: String?
    private var expiresAt: Date = .distantPast

    func validToken() -> String? {
        guard let token,
              Date().addingTimeInterval(30) < expiresAt else {
            return nil
        }
        return token
    }

    func store(token: String, expiresAtUnix: Int64) {
        self.token = token
        self.expiresAt = Date(timeIntervalSince1970: TimeInterval(expiresAtUnix))
    }
}
