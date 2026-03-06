import Foundation

enum APIKeyStorage {
    static func getAPIKey() -> String {
        guard let key = Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String,
              !key.isEmpty,
              key != "sk-ant-your-key-here" else {
            return ""
        }
        return key
    }

    static func getDigestAuthToken() -> String {
        guard let token = Bundle.main.infoDictionary?["DIGEST_AUTH_TOKEN"] as? String,
              !token.isEmpty else {
            return ""
        }
        return token
    }
}
