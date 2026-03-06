import Foundation

enum WebSearchService {
    /// Searches DuckDuckGo for the event and returns the first organic result URL.
    static func findEventURL(title: String, venue: String, address: String) async -> String? {
        let query = [title, venue, address]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://html.duckduckgo.com/html/?q=\(encoded)") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        return parseFirstOrganicResult(from: html)
    }

    private static func parseFirstOrganicResult(from html: String) -> String? {
        // DuckDuckGo HTML lite result links: class="result__a" href="//duckduckgo.com/l/?uddg=ENCODED_URL&..."
        // Skip ad results which are in <div class="result--ad"> sections
        let pattern = #"class="result__a" href="([^"]+)""#

        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        for match in matches {
            guard let range = Range(match.range(at: 1), in: html) else { continue }
            let href = String(html[range])

            // Decode the DuckDuckGo redirect URL to get the actual destination
            if let actualURL = decodeDDGRedirect(href) {
                // Skip ad/sponsored domains
                if isOrganicResult(actualURL) {
                    return actualURL
                }
            }
        }

        return nil
    }

    private static func decodeDDGRedirect(_ href: String) -> String? {
        let fullURL: String
        if href.hasPrefix("//") {
            fullURL = "https:\(href)"
        } else if href.hasPrefix("/") {
            fullURL = "https://duckduckgo.com\(href)"
        } else {
            fullURL = href
        }

        // Extract the actual URL from DuckDuckGo's redirect: ?uddg=ENCODED_URL
        if let components = URLComponents(string: fullURL),
           let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value {
            return uddg
        }

        // Direct URL (not a redirect)
        if fullURL.hasPrefix("http") && !fullURL.contains("duckduckgo.com") {
            return fullURL
        }

        return nil
    }

    private static func isOrganicResult(_ url: String) -> Bool {
        let adDomains = ["ad.doubleclick.net", "googleadservices.com", "bing.com/aclick"]
        return !adDomains.contains(where: { url.contains($0) })
    }
}
