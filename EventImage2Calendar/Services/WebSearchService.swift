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

    /// Search DuckDuckGo and return the first non-social-media result URL.
    static func searchForEventPage(title: String, venue: String, address: String) async -> String? {
        let query = [title, venue, address]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !query.isEmpty,
              let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Extract result URLs from DuckDuckGo HTML results
        // Format: <a rel="nofollow" class="result__a" href="URL">
        let pattern = #"class="result__a"[^>]*href="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        let matches = regex.matches(in: html, range: range)

        let skipDomains = ["instagram.com", "facebook.com", "twitter.com", "x.com", "tiktok.com", "youtube.com", "reddit.com"]

        for match in matches.prefix(5) {
            guard let urlRange = Range(match.range(at: 1), in: html) else { continue }
            let resultURL = String(html[urlRange])

            // DuckDuckGo wraps URLs through a redirect — extract the actual URL
            let actualURL: String
            if resultURL.contains("duckduckgo.com") || resultURL.contains("uddg=") {
                // Extract from redirect: //duckduckgo.com/l/?uddg=ENCODED_URL&...
                if let uddgRange = resultURL.range(of: "uddg="),
                   let ampRange = resultURL[uddgRange.upperBound...].range(of: "&") {
                    let encoded = String(resultURL[uddgRange.upperBound..<ampRange.lowerBound])
                    actualURL = encoded.removingPercentEncoding ?? encoded
                } else if let uddgRange = resultURL.range(of: "uddg=") {
                    let encoded = String(resultURL[uddgRange.upperBound...])
                    actualURL = encoded.removingPercentEncoding ?? encoded
                } else {
                    continue
                }
            } else {
                actualURL = resultURL
            }

            // Skip social media sites — we want the event's own page
            if skipDomains.contains(where: { actualURL.contains($0) }) { continue }
            if actualURL.hasPrefix("http") {
                return actualURL
            }
        }
        return nil
    }
}
