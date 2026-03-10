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
        You are an expert event detail extractor specializing in cultural and social events. \
        Analyze the event poster image and extract the PRIMARY ATTENDABLE EVENT — the specific \
        occasion a person would go to at a particular date and time.

        CRITICAL RULES FOR EVENT IDENTIFICATION:
        1. PRIORITIZE events with SPECIFIC TIMES (e.g., "19h", "7pm", "doors open 20:00") over date ranges.
        2. A "vernissage" (opening night/reception) IS the primary event, NOT the exhibition run dates.
        3. A "launch party", "opening night", "premiere", or "kickoff" is the event, not the season/run.
        4. If a poster shows BOTH an event with a specific time AND a date range, extract the TIMED event. \
           Mention the date range in the description field only.
        5. Date ranges (e.g., "21/03 - 02/04") are exhibition/festival durations — include them in \
           the description but do NOT use them as start/end dates unless no specific timed event exists.
        6. If ONLY a date range exists with no specific timed event, set is_multi_day to true. \
           Set start_datetime to the first date and end_datetime to the last date (date-only format "YYYY-MM-DD"). \
           List each individual date in event_dates.

        CULTURAL TERMS TO RECOGNIZE:
        - "Vernissage" / "Finissage" = opening/closing reception event (typically 2-3 hours)
        - "Inauguration" = opening ceremony
        - "Soirée" = evening event
        - "Apéro" / "Apéritif" = drinks reception (typically 1.5-2 hours)
        - "Conférence" / "Table ronde" = talk/panel (typically 1.5-2 hours)

        END TIME RULES (for timed events only, not multi-day):
        - If no end time is specified, default to start time + 2 hours.
        - If the event type implies a known duration (concert = 3h, reception/vernissage = 2h, talk = 1.5h), use that.
        - NEVER set the end date to a different day unless the poster explicitly states an overnight event.

        Respond with ONLY a JSON object, no markdown fences, no other text. Use this exact schema:
        {
          "title": "Event title (include event type if applicable, e.g., 'Vernissage: OTOM Solo Show')",
          "start_datetime": "ISO 8601 datetime (e.g., 2026-03-20T19:00:00) or date-only for multi-day (e.g., 2026-05-02)",
          "end_datetime": "ISO 8601 datetime (e.g., 2026-03-20T21:00:00) or date-only for multi-day (e.g., 2026-05-03)",
          "venue": "Venue name",
          "address": "Full address including city, postal code, state/country",
          "description": "Brief description (1-3 sentences). Include exhibition/festival run dates here if different from the event date. If a website URL, ticket link, or social media link is visible on the poster, include it at the end.",
          "timezone": "IANA timezone (e.g., Europe/Paris)",
          "is_multi_day": false,
          "event_dates": ["2026-05-02", "2026-05-03"]
        }
        MULTI-DAY RULES:
        - Set is_multi_day to true ONLY when the event spans multiple days with no single specific timed event.
        - When is_multi_day is true, list ALL individual dates in event_dates array (e.g., a 2-day festival on May 2-3 → ["2026-05-02", "2026-05-03"]).
        - When is_multi_day is false, event_dates should be an empty array [].
        - For timed events (vernissage, concert, etc.), always set is_multi_day to false even if there is also a date range on the poster.

        If a field cannot be determined from the image, use your best guess based on context or set to null. \
        For dates without a year, assume the nearest future occurrence.
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
        Extract the PRIMARY ATTENDABLE EVENT from this poster image. \
        If there are multiple dates (e.g., an opening reception AND an exhibition run), \
        extract the specific timed event that someone would attend, not the date range.

        \(locationContext)
        \(contextBlock)

        Today's date is \(Self.todayString()) for reference.
        """

        let requestBody: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 1024,
            "system": systemPrompt,
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

        return try await sendRequest(requestBody)
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
            The user is currently located at latitude \(loc.latitude), longitude \(loc.longitude). \
            Use this to help identify the city/region if not evident from the URL.
            """
        } else {
            locationContext = "No location data available."
        }

        let systemPrompt = """
        You are an expert event detail extractor. The user has shared a URL that likely points to \
        an event page. Based on the URL structure, domain, and any identifiers in the path, extract \
        event details using your knowledge of common event platforms (Eventbrite, Meetup, Facebook Events, \
        Instagram, gallery websites, etc.).

        Respond with ONLY a JSON object, no markdown fences, no other text. Use this exact schema:
        {
          "title": "Event title (your best inference from the URL)",
          "start_datetime": "ISO 8601 datetime if inferable, otherwise null",
          "end_datetime": "ISO 8601 datetime if inferable, otherwise null",
          "venue": "Venue name if inferable",
          "address": "Full address if inferable",
          "description": "Brief description. Always include the source URL.",
          "timezone": "IANA timezone if inferable"
        }
        If a field cannot be determined, set to null. For dates without a year, assume the nearest future occurrence.
        """

        let userText = """
        Extract event details from this shared URL: \(urlString)

        \(locationContext)

        Today's date is \(Self.todayString()) for reference.
        """

        let requestBody: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": userText
                ]
            ]
        ]

        return try await sendRequest(requestBody)
    }

    // MARK: - Enrichment (fill in sparse details using web search results)

    static func enrichEventDetails(
        current: EventDetails,
        pageText: String,
        location: CLLocationCoordinate2D?
    ) async throws -> EventDetails {
        let apiKey = APIKeyStorage.getAPIKey()
        guard !apiKey.isEmpty else { throw ClaudeAPIError.noAPIKey }

        let systemPrompt = """
        You are enriching an event's details using additional information found on a web page. \
        The user already has a partially-extracted event. Your job is to fill in missing or vague fields \
        using the web page content provided. Do NOT change fields that already have good, specific values.

        Rules:
        - If the current venue is vague (e.g., "Cinema or Event Venue", "TBD", "Unknown"), replace it with the specific venue from the page.
        - If the address is empty or vague, fill it in with the specific address from the page.
        - If the description is short, add relevant details from the page (but keep it concise, 2-4 sentences).
        - Do NOT change the title unless the page clearly shows a better/more complete name.
        - Do NOT change dates/times unless the page clearly contradicts them with more specific information.
        - Preserve the timezone.

        Respond with ONLY a JSON object, no markdown fences. Use this schema:
        {
          "title": "...",
          "start_datetime": "ISO 8601",
          "end_datetime": "ISO 8601",
          "venue": "...",
          "address": "...",
          "description": "...",
          "timezone": "...",
          "is_multi_day": false,
          "event_dates": []
        }
        """

        let currentJSON = """
        Current event details:
        - Title: \(current.title)
        - Start: \(Self.formatDate(current.startDate))
        - End: \(Self.formatDate(current.endDate))
        - Venue: \(current.venue)
        - Address: \(current.address)
        - Description: \(current.eventDescription)
        - Timezone: \(current.timezone ?? "unknown")
        """

        let truncatedPage = String(pageText.prefix(4000))

        let userText = """
        Enrich this event using the web page content below. Fill in any vague or missing fields.

        \(currentJSON)

        --- Web page content ---
        \(truncatedPage)
        """

        let requestBody: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 1024,
            "system": systemPrompt,
            "messages": [
                [
                    "role": "user",
                    "content": userText
                ]
            ]
        ]

        return try await sendRequest(requestBody)
    }

    private static func formatDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter.string(from: date)
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
            The user is currently located at latitude \(loc.latitude), longitude \(loc.longitude). \
            Use this to help identify the city/region if not evident from the content.
            """
        } else {
            locationContext = "No location data available."
        }

        let systemPrompt = """
        You are an expert event detail extractor specializing in cultural and social events. \
        Analyze the provided web page text and extract the PRIMARY ATTENDABLE EVENT — the specific \
        occasion a person would go to at a particular date and time.

        CRITICAL RULES FOR EVENT IDENTIFICATION:
        1. PRIORITIZE events with SPECIFIC TIMES (e.g., "19h", "7pm", "doors open 20:00") over date ranges.
        2. A "vernissage" (opening night/reception) IS the primary event, NOT the exhibition run dates.
        3. A "launch party", "opening night", "premiere", or "kickoff" is the event, not the season/run.
        4. If the text mentions BOTH an event with a specific time AND a date range, extract the TIMED event. \
           Mention the date range in the description field only.
        5. Date ranges (e.g., "21/03 - 02/04") are exhibition/festival durations — include them in \
           the description but do NOT use them as start/end dates unless no specific timed event exists.
        6. If ONLY a date range exists with no specific timed event, set is_multi_day to true. \
           Set start_datetime to the first date and end_datetime to the last date (date-only format "YYYY-MM-DD"). \
           List each individual date in event_dates.

        CULTURAL TERMS TO RECOGNIZE:
        - "Vernissage" / "Finissage" = opening/closing reception event (typically 2-3 hours)
        - "Inauguration" = opening ceremony
        - "Soirée" = evening event
        - "Apéro" / "Apéritif" = drinks reception (typically 1.5-2 hours)
        - "Conférence" / "Table ronde" = talk/panel (typically 1.5-2 hours)

        END TIME RULES (for timed events only, not multi-day):
        - If no end time is specified, default to start time + 2 hours.
        - If the event type implies a known duration (concert = 3h, reception/vernissage = 2h, talk = 1.5h), use that.
        - NEVER set the end date to a different day unless explicitly stated as an overnight event.

        Respond with ONLY a JSON object, no markdown fences, no other text. Use this exact schema:
        {
          "title": "Event title (include event type if applicable, e.g., 'Vernissage: OTOM Solo Show')",
          "start_datetime": "ISO 8601 datetime (e.g., 2026-03-20T19:00:00) or date-only for multi-day (e.g., 2026-05-02)",
          "end_datetime": "ISO 8601 datetime (e.g., 2026-03-20T21:00:00) or date-only for multi-day (e.g., 2026-05-03)",
          "venue": "Venue name",
          "address": "Full address including city, postal code, state/country",
          "description": "Brief description (1-3 sentences). Include the source URL if provided.",
          "timezone": "IANA timezone (e.g., Europe/Paris)",
          "is_multi_day": false,
          "event_dates": ["2026-05-02", "2026-05-03"]
        }
        MULTI-DAY RULES:
        - Set is_multi_day to true ONLY when the event spans multiple days with no single specific timed event.
        - When is_multi_day is true, list ALL individual dates in event_dates array.
        - When is_multi_day is false, event_dates should be an empty array [].

        If a field cannot be determined from the text, use your best guess based on context or set to null. \
        For dates without a year, assume the nearest future occurrence.
        """

        let truncatedText = String(text.prefix(4000))
        let urlNote = sourceURL.map { "\nSource URL: \($0)" } ?? ""

        let userText = """
        Extract the PRIMARY ATTENDABLE EVENT from this web page content. \
        If there are multiple dates (e.g., an opening reception AND an exhibition run), \
        extract the specific timed event that someone would attend, not the date range.

        \(locationContext)
        \(urlNote)

        Today's date is \(Self.todayString()) for reference.

        --- Page content ---
        \(truncatedText)
        """

        let requestBody: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 1024,
            "system": systemPrompt,
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

    private static func sendRequest(_ requestBody: [String: Any]) async throws -> EventDetails {
        let apiKey = APIKeyStorage.getAPIKey()

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 25

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
        guard let textContent = claudeResponse.content.first(where: { $0.type == "text" }),
              let jsonString = textContent.text else {
            throw ClaudeAPIError.invalidResponse
        }

        let cleanJSON = extractJSON(from: jsonString)
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
            throw ClaudeAPIError.decodingFailed(error.localizedDescription)
        }
    }

    /// Strip markdown fences and extract raw JSON
    private static func extractJSON(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let start = trimmed.firstIndex(of: "{"),
              let end = trimmed.lastIndex(of: "}") else {
            return trimmed
        }
        return String(trimmed[start...end])
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
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
