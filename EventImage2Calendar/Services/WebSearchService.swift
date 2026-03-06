import Foundation

enum WebSearchService {
    /// Searches Google for the event and returns the first organic result URL.
    /// Returns nil if the search fails — caller should provide a fallback.
    static func findEventURL(title: String, venue: String, address: String) async -> String? {
        let query = [title, venue, address]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://www.google.com/search?q=\(encoded)&hl=en&gl=us") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 8

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        return parseFirstOrganicResult(from: html)
    }

    /// Builds a Google search URL as a fallback when actual search parsing fails.
    static func googleSearchURL(title: String, venue: String, address: String) -> String {
        let query = [title, venue, address]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return "https://www.google.com/search?q=\(encoded)"
    }

    private static func parseFirstOrganicResult(from html: String) -> String? {
        // Try multiple patterns — Google's HTML varies by region/device/bot
        let patterns = [
            #"<a href="/url\?q=(https?://[^&"]+)"#,          // Standard redirect links
            #"<a href="(https?://(?!www\.google)[^"]+)""#,    // Direct links (non-Google)
            #"data-href="(https?://(?!www\.google)[^"]+)""#,  // Data attributes
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

            for match in matches {
                guard let range = Range(match.range(at: 1), in: html) else { continue }
                let rawURL = String(html[range])
                let decoded = rawURL.removingPercentEncoding ?? rawURL

                if isOrganicResult(decoded) {
                    return decoded
                }
            }
        }

        return nil
    }

    private static func isOrganicResult(_ url: String) -> Bool {
        let skipDomains = [
            "google.com", "googleapis.com", "googleadservices.com",
            "doubleclick.net", "gstatic.com",
            "accounts.google", "maps.google",
            "facebook.com/login", "instagram.com/accounts",
            "schema.org", "w3.org",
        ]
        return !skipDomains.contains(where: { url.contains($0) })
    }
}
