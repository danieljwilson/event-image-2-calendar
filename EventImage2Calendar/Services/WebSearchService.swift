import Foundation

enum WebSearchService {
    /// Builds a Google search URL from the event details.
    static func googleSearchURL(title: String, venue: String, address: String) -> String {
        let query = [title, venue, address]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "https://www.google.com/search?q=\(encoded)"
    }
}
