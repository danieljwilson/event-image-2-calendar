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
}
