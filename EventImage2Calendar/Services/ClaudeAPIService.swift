import Foundation
import CoreLocation

enum ClaudeAPIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(String)
    case decodingFailed(String)
    case noEventFound

    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured. Add your Claude API key to Secrets.xcconfig."
        case .invalidResponse:
            return "Received an invalid response from the API."
        case .apiError(let message):
            return "API error: \(message)"
        case .decodingFailed(let detail):
            return "Failed to parse event details: \(detail)"
        case .noEventFound:
            return "No event details could be identified in this image."
        }
    }

    var isRetryable: Bool {
        switch self {
        case .noAPIKey, .invalidResponse, .decodingFailed, .noEventFound:
            return false
        case .apiError(let message):
            if message.hasPrefix("Network error:") { return true }
            if message.contains("HTTP 5") { return true }
            if message.contains("HTTP 429") { return true }
            return false
        }
    }

    var userFacingMessage: String {
        switch self {
        case .noAPIKey:
            return "API key not configured. Check app settings."
        case .invalidResponse:
            return "Received an unexpected response. Try again."
        case .apiError(let message):
            if message.hasPrefix("Network error:") { return "Network error. Will retry automatically." }
            if message.contains("HTTP 5") { return "Server error. Will retry automatically." }
            if message.contains("HTTP 429") { return "Too many requests. Will retry shortly." }
            if message.contains("HTTP 401") || message.contains("HTTP 403") {
                return "Authentication error. Check your API key."
            }
            return "API error occurred. Try again later."
        case .decodingFailed:
            return "Could not read event details from this image."
        case .noEventFound:
            return "No event details found in this image. Try a clearer photo."
        }
    }
}

enum ClaudeAPIService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static func extractEvent(
        imageData: Data,
        location: CLLocationCoordinate2D?,
        additionalContext: String? = nil
    ) async throws -> EventDetails {
        let events = try await extractEvents(imageData: imageData, location: location, additionalContext: additionalContext)
        guard let first = events.first else { throw ClaudeAPIError.noEventFound }
        return first
    }

    static func extractEvents(
        imageData: Data,
        location: CLLocationCoordinate2D?,
        additionalContext: String? = nil
    ) async throws -> [EventDetails] {
        let apiKey = APIKeyStorage.getAPIKey()
        guard !apiKey.isEmpty else { throw ClaudeAPIError.noAPIKey }

        let base64Image = imageData.base64EncodedString()

        let locationContext: String
        if let loc = location {
            locationContext = """
            The user is currently located at latitude \(loc.latitude), longitude \(loc.longitude). \
            Use this to help identify the city/region if the poster doesn't explicitly state it. \
            If the venue is well-known, use your knowledge to fill in the full address.
            """
        } else {
            locationContext = "No location data available."
        }

        let systemPrompt = """
        You are an expert event detail extractor. Analyze the image and extract ALL DISTINCT \
        ATTENDABLE EVENTS. Use web search to verify and complete event details when:
        - Dates or times are ambiguous or missing
        - You need to confirm venue addresses
        - The event appears to span multiple days and you need exact dates

        RULES:
        1. Every event MUST have a start date in the future (today is \(Self.todayString()), \(Self.todayDayOfWeek())). \
           If a date would resolve to the past, pick the next future occurrence.
        2. Each event with its own time and/or venue is a separate entry in the array.
        3. For events spanning multiple days (tournaments, festivals, exhibitions with no \
           single timed event), set is_multi_day: true with start/end as date-only strings.
        4. For timed events (vernissage, concert, talk, screening), set is_multi_day: false. If no \
           end time given, estimate a reasonable duration for the event type.
        5. If a poster has BOTH a timed event (e.g., opening reception) AND a date range \
           (e.g., exhibition run), extract the timed event. Mention the range in description.
        6. If you cannot determine a date, set start_datetime and end_datetime to null. \
           Do NOT default to today.

        Respond with ONLY a JSON array (even for one event), no markdown fences. Schema per object:
        {
          "title": "Event title",
          "start_datetime": "ISO 8601 (e.g. 2026-04-04T11:30:00) or date-only (2026-04-04)",
          "end_datetime": "ISO 8601 or date-only",
          "venue": "Specific venue name",
          "address": "Full address with city and postal code",
          "description": "1-3 sentences. Include source URLs if visible.",
          "timezone": "IANA timezone (e.g. Europe/Paris)",
          "is_multi_day": false,
          "event_dates": []
        }
        Set null for unknown fields. For is_multi_day events, list dates in event_dates array.
        """

        let contextBlock: String
        if let additionalContext, !additionalContext.isEmpty {
            contextBlock = """

            Additional context from the source page:
            \(additionalContext)
            """
        } else {
            contextBlock = ""
        }

        let userText = """
        Extract ALL DISTINCT ATTENDABLE EVENTS from this image.

        \(locationContext)
        \(contextBlock)
        """

        let requestBody: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 4096,
            "system": systemPrompt,
            "tools": [
                [
                    "type": "web_search_20250305",
                    "name": "web_search",
                    "max_uses": 5
                ]
            ],
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": userText
                        ]
                    ]
                ]
            ]
        ]

        return try await sendRequestMultiple(requestBody)
    }

    // MARK: - URL-based extraction (for shared URLs)

    static func extractEventFromURL(
        urlString: String,
        location: CLLocationCoordinate2D?
    ) async throws -> EventDetails {
        let apiKey = APIKeyStorage.getAPIKey()
        guard !apiKey.isEmpty else { throw ClaudeAPIError.noAPIKey }

        let locationContext: String
        if let loc = location {
            locationContext = """
            The user is located at latitude \(loc.latitude), longitude \(loc.longitude). \
            Use this to identify the city/region and pick the nearest location for touring events.
            """
        } else {
            locationContext = "No location data available."
        }

        let systemPrompt = """
        You are an expert event detail extractor. The user has shared a URL. \
        Use web search to find the event page and extract complete details.

        Today is \(Self.todayString()), \(Self.todayDayOfWeek()). All dates must be in the future.

        Respond with ONLY a JSON object, no markdown fences. Schema:
        {
          "title": "Event title",
          "start_datetime": "ISO 8601 or date-only",
          "end_datetime": "ISO 8601 or date-only",
          "venue": "Specific venue name",
          "address": "Full address with city and postal code",
          "description": "1-3 sentences. Include the source URL.",
          "timezone": "IANA timezone",
          "is_multi_day": false,
          "event_dates": []
        }
        Set null for unknown fields. For is_multi_day events, list dates in event_dates array.
        """

        let userText = """
        Extract event details from this URL: \(urlString)

        \(locationContext)
        """

        let requestBody: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 2048,
            "system": systemPrompt,
            "tools": [
                [
                    "type": "web_search_20250305",
                    "name": "web_search",
                    "max_uses": 5
                ]
            ],
            "messages": [
                [
                    "role": "user",
                    "content": userText
                ]
            ]
        ]

        return try await sendRequest(requestBody)
    }

    // MARK: - Text-based extraction (for page content scraped from URLs)

    static func extractEventFromText(
        text: String,
        sourceURL: String?,
        location: CLLocationCoordinate2D?
    ) async throws -> EventDetails {
        let apiKey = APIKeyStorage.getAPIKey()
        guard !apiKey.isEmpty else { throw ClaudeAPIError.noAPIKey }

        let locationContext: String
        if let loc = location {
            locationContext = """
            The user is located at latitude \(loc.latitude), longitude \(loc.longitude). \
            Use this to identify the city/region and pick the nearest location for touring events.
            """
        } else {
            locationContext = "No location data available."
        }

        let systemPrompt = """
        You are an expert event detail extractor. Analyze the text and extract the primary \
        attendable event. Use web search to verify and complete details when needed.

        Today is \(Self.todayString()), \(Self.todayDayOfWeek()). All dates must be in the future.

        Respond with ONLY a JSON object, no markdown fences. Schema:
        {
          "title": "Event title",
          "start_datetime": "ISO 8601 or date-only",
          "end_datetime": "ISO 8601 or date-only",
          "venue": "Specific venue name",
          "address": "Full address with city and postal code",
          "description": "1-3 sentences. Include source URL if available.",
          "timezone": "IANA timezone",
          "is_multi_day": false,
          "event_dates": []
        }
        Set null for unknown fields. For is_multi_day events, list dates in event_dates array.
        """

        let truncatedText = String(text.prefix(4000))
        let urlNote = sourceURL.map { "\nSource URL: \($0)" } ?? ""

        let userText = """
        Extract the primary attendable event from this page content.

        \(locationContext)
        \(urlNote)

        --- Page content ---
        \(truncatedText)
        """

        let requestBody: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 2048,
            "system": systemPrompt,
            "tools": [
                [
                    "type": "web_search_20250305",
                    "name": "web_search",
                    "max_uses": 3
                ]
            ],
            "messages": [
                [
                    "role": "user",
                    "content": userText
                ]
            ]
        ]

        return try await sendRequest(requestBody)
    }

    // MARK: - Shared request logic

    private static func sendRequestMultiple(_ requestBody: [String: Any]) async throws -> [EventDetails] {
        let rawText = try await sendRequestRaw(requestBody)

        // Detect if response is an array or single object
        let stripped = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Try array parsing first
        if stripped.contains("[") {
            let arrayJSON = extractJSONArray(from: rawText)
            if let data = arrayJSON.data(using: .utf8) {
                do {
                    let dtos = try JSONDecoder().decode([EventDetailsDTO].self, from: data)
                    let events = dtos.map { $0.toEventDetails() }
                        .filter { $0.title != "Untitled Event" || $0.hasExplicitDate }
                    if !events.isEmpty { return events }
                } catch {
                    SharedContainerService.writeDebugLog("Array decode failed, trying single: \(error.localizedDescription)")
                }
            }
        }

        // Fall back to single object
        let objectJSON = extractJSON(from: rawText)
        guard let data = objectJSON.data(using: .utf8) else {
            throw ClaudeAPIError.decodingFailed("Could not convert response to data")
        }

        do {
            let dto = try JSONDecoder().decode(EventDetailsDTO.self, from: data)
            if dto.title == nil && dto.venue == nil && dto.startDatetime == nil {
                throw ClaudeAPIError.noEventFound
            }
            return [dto.toEventDetails()]
        } catch let error as ClaudeAPIError {
            throw error
        } catch {
            let recovered = repairTruncatedJSON(objectJSON)
            if recovered != objectJSON, let recoveredData = recovered.data(using: .utf8),
               let dto = try? JSONDecoder().decode(EventDetailsDTO.self, from: recoveredData) {
                SharedContainerService.writeDebugLog("JSON recovered from truncation (multi)")
                return [dto.toEventDetails()]
            }
            SharedContainerService.writeDebugLog("JSON decode failed (multi). Raw: \(objectJSON.prefix(500))")
            throw ClaudeAPIError.decodingFailed(error.localizedDescription)
        }
    }

    /// Sends the HTTP request and returns the raw text from Claude's response.
    private static func sendRequestRaw(_ requestBody: [String: Any]) async throws -> String {
        let apiKey = APIKeyStorage.getAPIKey()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 60

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ClaudeAPIError.apiError("Network error: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeAPIError.apiError("HTTP \(httpResponse.statusCode): \(body)")
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        // Use LAST text block — with web_search, the final text block contains the JSON answer
        guard let textContent = claudeResponse.content.last(where: { $0.type == "text" }),
              let jsonString = textContent.text else {
            throw ClaudeAPIError.invalidResponse
        }

        return jsonString
    }

    private static func sendRequest(_ requestBody: [String: Any]) async throws -> EventDetails {
        let rawText = try await sendRequestRaw(requestBody)
        let cleanJSON = extractJSON(from: rawText)
        guard let jsonData = cleanJSON.data(using: .utf8) else {
            throw ClaudeAPIError.decodingFailed("Could not convert response to data")
        }

        do {
            let dto = try JSONDecoder().decode(EventDetailsDTO.self, from: jsonData)
            if dto.title == nil && dto.venue == nil && dto.startDatetime == nil {
                throw ClaudeAPIError.noEventFound
            }
            return dto.toEventDetails()
        } catch let error as ClaudeAPIError {
            throw error
        } catch {
            // Try truncation recovery: close open strings/objects
            let recovered = repairTruncatedJSON(cleanJSON)
            if recovered != cleanJSON, let recoveredData = recovered.data(using: .utf8),
               let dto = try? JSONDecoder().decode(EventDetailsDTO.self, from: recoveredData) {
                SharedContainerService.writeDebugLog("JSON recovered from truncation")
                return dto.toEventDetails()
            }
            SharedContainerService.writeDebugLog("JSON decode failed. Raw: \(cleanJSON.prefix(500))")
            throw ClaudeAPIError.decodingFailed(error.localizedDescription)
        }
    }

    /// Strip markdown fences, trailing commas, and extract a JSON array
    private static func extractJSONArray(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract the JSON array
        guard let start = cleaned.firstIndex(of: "["),
              let end = cleaned.lastIndex(of: "]") else {
            return cleaned
        }
        var json = String(cleaned[start...end])

        // Remove trailing commas before } or ]
        if let regex = try? NSRegularExpression(pattern: #",\s*([}\]])"#) {
            json = regex.stringByReplacingMatches(
                in: json, range: NSRange(json.startIndex..., in: json),
                withTemplate: "$1"
            )
        }

        return json
    }

    /// Strip markdown fences, trailing commas, and extract raw JSON
    private static func extractJSON(from text: String) -> String {
        var cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Strip markdown code fences
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        // Extract the JSON object
        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else {
            return cleaned
        }
        var json = String(cleaned[start...end])

        // Remove trailing commas before } or ] (common haiku issue)
        if let regex = try? NSRegularExpression(pattern: #",\s*([}\]])"#) {
            json = regex.stringByReplacingMatches(
                in: json, range: NSRange(json.startIndex..., in: json),
                withTemplate: "$1"
            )
        }

        return json
    }

    /// Attempt to repair JSON truncated by max_tokens.
    /// Drops the last incomplete key-value pair and closes the object.
    private static func repairTruncatedJSON(_ json: String) -> String {
        // If it already ends with }, it's not truncated
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("}") { return json }

        // Find the last complete key-value pair (ends with a comma or closing bracket)
        // Strategy: find the last complete value ending (", or ],)
        var repaired = trimmed

        // If we're inside a string value, close it
        // Count unescaped quotes — if odd, we're mid-string
        let quoteCount = repaired.filter { $0 == "\"" }.count
        if quoteCount % 2 != 0 {
            repaired += "\""
        }

        // Remove any trailing partial key-value
        // Find last comma that's outside a string, truncate there, close
        if let lastComma = repaired.lastIndex(of: ",") {
            let afterComma = repaired[repaired.index(after: lastComma)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // If what follows the comma doesn't look like a complete value, truncate
            if !afterComma.contains(":") || !afterComma.hasSuffix("\"") {
                repaired = String(repaired[...lastComma])
                // Remove the trailing comma
                repaired = String(repaired.dropLast())
            }
        }

        // Close any open arrays and the object
        let openBrackets = repaired.filter { $0 == "[" }.count
        let closeBrackets = repaired.filter { $0 == "]" }.count
        for _ in 0..<(openBrackets - closeBrackets) {
            repaired += "]"
        }
        let openBraces = repaired.filter { $0 == "{" }.count
        let closeBraces = repaired.filter { $0 == "}" }.count
        for _ in 0..<(openBraces - closeBraces) {
            repaired += "}"
        }

        return repaired
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }

    private static func todayDayOfWeek() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}

// MARK: - Claude Messages API response types

struct ClaudeResponse: Decodable {
    let content: [ContentBlock]

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}
