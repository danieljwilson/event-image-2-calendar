import Foundation
import CoreLocation

enum ClaudeAPIError: LocalizedError {
    case authFailed
    case invalidResponse
    case apiError(String)
    case decodingFailed(String)
    case noEventFound

    var errorDescription: String? {
        switch self {
        case .authFailed:
            return "Could not authenticate with the extraction service."
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
        case .authFailed, .invalidResponse, .decodingFailed, .noEventFound:
            return false
        case .apiError(let message):
            if message.contains("Daily extraction limit") { return false }
            if message.hasPrefix("Network error:") { return true }
            if message.contains("HTTP 5") { return true }
            if message.contains("HTTP 429") { return true }
            if message.contains("HTTP 413") { return true }
            return false
        }
    }

    var userFacingMessage: String {
        switch self {
        case .authFailed:
            return "Authentication failed. Please restart the app."
        case .invalidResponse:
            return "Received an unexpected response. Try again."
        case .apiError(let message):
            if message.contains("Daily extraction limit") { return "Daily limit reached. Upgrade for more extractions." }
            if message.hasPrefix("Network error:") { return "Network error. Will retry automatically." }
            if message.contains("HTTP 5") { return "Server error. Will retry automatically." }
            if message.contains("HTTP 429") { return "Too many requests. Will retry shortly." }
            if message.contains("HTTP 413") { return "Image too large. Try a smaller photo." }
            if message.contains("HTTP 401") || message.contains("HTTP 403") {
                return "Authentication error. Please restart the app."
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
    /// The LLM model used for all extraction requests.
    /// Change this to switch providers — the Worker routes automatically based on model prefix:
    ///   gpt-*  → OpenAI Responses API
    ///   claude-*  → Anthropic Messages API
    /// After changing, ensure the model is in ALLOWED_MODELS in cloudflare-worker/src/validation.ts.
    /// Available OpenAI models: https://developers.openai.com/api/docs/models/all
    private static let extractionModel = "gpt-5.4-nano-2026-03-17"

    private static var extractEndpoint: URL { APIConfiguration.workerBaseURL.appendingPathComponent("extract") }

    static func extractEvent(
        imageData: Data,
        location: CLLocationCoordinate2D?,
        additionalContext: String? = nil,
        language: String = "English"
    ) async throws -> ExtractionOutput {
        let output = try await extractEvents(imageData: imageData, location: location, additionalContext: additionalContext, language: language)
        guard !output.events.isEmpty else { throw ClaudeAPIError.noEventFound }
        return output
    }

    static func extractEvents(
        imageData: Data,
        location: CLLocationCoordinate2D?,
        additionalContext: String? = nil,
        language: String = "English"
    ) async throws -> ExtractionOutput {
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
        ATTENDABLE EVENTS.

        THE IMAGE IS THE PRIMARY SOURCE. Extract events exactly as described in the image — \
        titles, times, venues, and descriptions come from what you see. Web search is ONLY \
        used to fill in specific missing fields, never to replace or override what the \
        image already shows.

        WEB SEARCH POLICY — every event needs three pieces of information:
        • DATE: a specific calendar date (e.g. "4 avril 2026", "March 21", "21/03"). \
          A day of week like "samedi" or "Friday" is NOT a date.
        • TIME: a start time (e.g. "14h15", "7pm"). For multi-day events like festivals \
          or tournaments, time is optional but include it if shown.
        • LOCATION: a venue name and/or address.
        ALWAYS use web search to find the event page URL for the description. \
        If ANY of date, time, or location is also missing, use the same search to \
        fill in ONLY the missing fields. Do NOT replace the event's title, time, \
        venue, or description with different information found online. For example, \
        if the image says "15h : visite point de vue sur les expositions", search \
        to find the DATE and event page URL, but keep the title, time (15h), and \
        venue from the image.

        RULES:
        1. All dates must be in the future (today is \(Self.todayString()), \(Self.todayDayOfWeek())). \
           Reject any date in the past. If the image only shows a day of week or time \
           without a specific calendar date, use web search to find the actual date. \
           Do NOT guess by picking the next occurrence of that weekday.
        2. Each event with its own time and/or venue is a separate entry in the array.
        3. For multi-day events (tournaments, festivals), set is_multi_day: true with \
           start/end as date-only strings.
        3b. When the SAME event (same title, same venue) is performed on multiple \
           specific dates (e.g. a show, concert, or ballet with several performance \
           dates), return it as a SINGLE entry with is_multi_day: true. Populate \
           event_dates with ISO 8601 datetime strings that include the performance \
           time (e.g. "2026-04-02T20:00:00"). Set start_datetime to the first \
           performance datetime and end_datetime to the END of the first performance \
           (so duration can be calculated per performance).
        4. For timed events with only ONE date (vernissage, concert, talk, screening), \
           set is_multi_day: false. If no end time given, estimate a reasonable duration.
        5. Extract ONLY attendable events (things a person would go to at a specific \
           time). An exhibition's date range or a show's run is NOT a separate event — \
           mention it in the description of the timed event (e.g. vernissage, guided \
           visit). Never create a separate entry for an exhibition's duration.
        6. DATE & TIME CERTAINTY — CRITICAL RULE: \
           A day-of-week name (lundi, mardi, mercredi, jeudi, vendredi, samedi, \
           dimanche, Monday, Tuesday, etc.) is NEVER a confirmed date. \
           "date_confirmed" must be false unless you have a numeric calendar date \
           (e.g. "4 avril", "March 21", "21/03/2026") from the image itself or from \
           a web search result. Computing "next Saturday" from "samedi" is WRONG. \
           CONSISTENCY: if the image contains multiple events and no numeric date is \
           visible anywhere in the image, then ALL events must have date_confirmed: false. \
           Do not confirm some and leave others unconfirmed from the same source. \
           ALWAYS populate start_datetime — never set it to null. Use today's date \
           (\(Self.todayString())) as a placeholder when the calendar date is unknown, \
           combined with the real time from the image. If the time is unknown but the \
           date is known, use the date with T00:00:00. \
           "time_confirmed": true only if the image shows a specific start time \
           (e.g. "15h", "14h15", "7pm", "doors open 20:00"). \
           It is MUCH better to mark a flag false (the user will be prompted to enter \
           just the missing piece) than to guess wrong.
        7. ALWAYS use web search to find a direct event page URL and include it in \
           the description. Prefer event listings, ticket pages, or venue pages.

        Respond with ONLY a JSON array (even for one event), no markdown fences. Schema per object:
        {
          "title": "Event title",
          "start_datetime": "ISO 8601 (e.g. 2026-04-04T11:30:00) or date-only (2026-04-04). NEVER null.",
          "end_datetime": "ISO 8601 or date-only",
          "venue": "Specific venue name",
          "address": "Full address with city and postal code",
          "description": "2-4 sentences. MUST include a direct event page URL.",
          "timezone": "IANA timezone (e.g. Europe/Paris)",
          "is_multi_day": false,
          "event_dates": [],
          "date_confirmed": true,
          "time_confirmed": true,
          "category": "sports | music | arts | food | tech | business | education | community | nightlife | other",
          "city": "City name (e.g. Nice, Paris, New York)"
        }
        Set null for unknown fields (except start_datetime). For is_multi_day events, \
        list dates in event_dates array (date-only for festivals, datetime for timed performances).

        OUTPUT LANGUAGE: Write the "description" field in \(language). \
        Keep the title, venue, and address in their original language as shown in the image.
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
            "model": Self.extractionModel,
            "max_tokens": 4096,
            "modality": "image",
            "system": systemPrompt,
            "tools": [Self.webSearchTool(maxUses: 5)],
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
        location: CLLocationCoordinate2D?,
        language: String = "English"
    ) async throws -> ExtractionOutput {
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

        Today is \(Self.todayString()), \(Self.todayDayOfWeek()). All dates must be in the future. \
        ALWAYS populate start_datetime with the actual event date and time as ISO 8601. \
        The start_datetime field is the ONLY field used for calendar creation. \
        If you cannot determine the date, set start_datetime to null — do NOT default to today. \
        Include the direct event page URL in the description.

        CRITICAL: Your final response MUST be ONLY a valid JSON object — no explanations, \
        no markdown, no commentary before or after the JSON. Schema:
        {
          "title": "Event title",
          "start_datetime": "ISO 8601 or date-only",
          "end_datetime": "ISO 8601 or date-only",
          "venue": "Specific venue name",
          "address": "Full address with city and postal code",
          "description": "1-3 sentences. Include direct event page URL.",
          "timezone": "IANA timezone",
          "is_multi_day": false,
          "event_dates": [],
          "category": "sports | music | arts | food | tech | business | education | community | nightlife | other",
          "city": "City name (e.g. Nice, Paris, New York)"
        }
        Set null for unknown fields. For is_multi_day events, list dates in event_dates array. \
        If you cannot find sufficient event details after searching, respond with a JSON object \
        where all fields are null (title: null, start_datetime: null, etc.).

        OUTPUT LANGUAGE: Write the "description" field in \(language). \
        Keep the title, venue, and address in their original language.
        """

        let userText = """
        Extract event details from this URL: \(urlString)

        \(locationContext)
        """

        let requestBody: [String: Any] = [
            "model": Self.extractionModel,
            "max_tokens": 2048,
            "modality": "url",
            "system": systemPrompt,
            "tools": [Self.webSearchTool(maxUses: 5)],
            "messages": [
                [
                    "role": "user",
                    "content": userText
                ]
            ]
        ]

        return try await sendRequest(requestBody)
    }

    // MARK: - Social media extraction (auth-walled URLs like Instagram/Facebook)

    static func extractEventFromSocialURL(
        urlString: String,
        captionText: String?,
        location: CLLocationCoordinate2D?,
        language: String = "English"
    ) async throws -> ExtractionOutput {
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
        You are an expert event detail extractor. The user has shared a social media link \
        (Instagram or Facebook). You CANNOT access the page directly — it requires authentication.

        STRATEGY:
        1. Look at the URL for clues (username, post ID).
        2. If caption text is provided, extract any event details (name, date, time, venue) from it.
        3. Use web search to find the actual event by searching for the event name, venue, \
           or performer mentioned in the caption or URL. Try searches like:
           - "[performer/venue from caption] event [city]"
           - "[username from URL] event"
           - Key phrases from the caption + "event" or "concert" or "show"
        4. Cross-reference what you find with any details from the caption.

        Today is \(Self.todayString()), \(Self.todayDayOfWeek()). All dates must be in the future. \
        ALWAYS populate start_datetime with the actual event date and time as ISO 8601. \
        The start_datetime field is the ONLY field used for calendar creation. \
        If you cannot determine the date, set start_datetime to null — do NOT default to today. \
        Include the direct event page URL in the description.

        CRITICAL: Your final response MUST be ONLY a valid JSON object — no explanations, \
        no markdown, no commentary before or after the JSON. Schema:
        {
          "title": "Event title",
          "start_datetime": "ISO 8601 or date-only",
          "end_datetime": "ISO 8601 or date-only",
          "venue": "Specific venue name",
          "address": "Full address with city and postal code",
          "description": "1-3 sentences. Include direct event page URL.",
          "timezone": "IANA timezone",
          "is_multi_day": false,
          "event_dates": [],
          "category": "sports | music | arts | food | tech | business | education | community | nightlife | other",
          "city": "City name (e.g. Nice, Paris, New York)"
        }
        Set null for unknown fields. For is_multi_day events, list dates in event_dates array. \
        If you cannot find sufficient event details after searching, respond with a JSON object \
        where all fields are null (title: null, start_datetime: null, etc.).

        OUTPUT LANGUAGE: Write the "description" field in \(language). \
        Keep the title, venue, and address in their original language.
        """

        let captionBlock: String
        if let captionText, !captionText.isEmpty {
            captionBlock = """

            Caption text shared with the link:
            \(String(captionText.prefix(2000)))
            """
        } else {
            captionBlock = "\nNo caption text was provided with the link."
        }

        let userText = """
        Extract event details from this social media post.

        URL: \(urlString)
        \(captionBlock)

        \(locationContext)
        """

        let requestBody: [String: Any] = [
            "model": Self.extractionModel,
            "max_tokens": 2048,
            "modality": "social",
            "system": systemPrompt,
            "tools": [Self.webSearchTool(maxUses: 5)],
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
        location: CLLocationCoordinate2D?,
        language: String = "English"
    ) async throws -> ExtractionOutput {
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

        Today is \(Self.todayString()), \(Self.todayDayOfWeek()). All dates must be in the future. \
        ALWAYS populate start_datetime with the actual event date and time as ISO 8601. \
        The start_datetime field is the ONLY field used for calendar creation. \
        If you cannot determine the date, set start_datetime to null — do NOT default to today. \
        Include the direct event page URL in the description.

        CRITICAL: Your final response MUST be ONLY a valid JSON object — no explanations, \
        no markdown, no commentary before or after the JSON. Schema:
        {
          "title": "Event title",
          "start_datetime": "ISO 8601 or date-only",
          "end_datetime": "ISO 8601 or date-only",
          "venue": "Specific venue name",
          "address": "Full address with city and postal code",
          "description": "1-3 sentences. Include direct event page URL.",
          "timezone": "IANA timezone",
          "is_multi_day": false,
          "event_dates": [],
          "category": "sports | music | arts | food | tech | business | education | community | nightlife | other",
          "city": "City name (e.g. Nice, Paris, New York)"
        }
        Set null for unknown fields. For is_multi_day events, list dates in event_dates array. \
        If you cannot find sufficient event details, respond with a JSON object \
        where all fields are null (title: null, start_datetime: null, etc.).

        OUTPUT LANGUAGE: Write the "description" field in \(language). \
        Keep the title, venue, and address in their original language.
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
            "model": Self.extractionModel,
            "max_tokens": 2048,
            "modality": "text",
            "system": systemPrompt,
            "tools": [Self.webSearchTool(maxUses: 3)],
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

    private static func sendRequestMultiple(_ requestBody: [String: Any]) async throws -> ExtractionOutput {
        let (rawText, usage) = try await sendRequestRaw(requestBody)

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
                    if !events.isEmpty { return ExtractionOutput(events: events, usage: usage) }
                } catch {
                    SharedContainerService.writeDebugLog("Array decode failed, trying single: \(error.localizedDescription)")
                }
            }
        }

        // Fall back to single object
        let objectJSON = extractJSON(from: rawText)

        // If no JSON object found, Claude responded with prose
        if !objectJSON.contains("{") {
            SharedContainerService.writeDebugLog("API: no JSON object in response — narrative text detected (multi)")
            throw ClaudeAPIError.noEventFound
        }

        guard let data = objectJSON.data(using: .utf8) else {
            throw ClaudeAPIError.decodingFailed("Could not convert response to data")
        }

        do {
            let dto = try JSONDecoder().decode(EventDetailsDTO.self, from: data)
            if dto.title == nil && dto.venue == nil && dto.startDatetime == nil {
                throw ClaudeAPIError.noEventFound
            }
            return ExtractionOutput(events: [dto.toEventDetails()], usage: usage)
        } catch let error as ClaudeAPIError {
            throw error
        } catch {
            let recovered = repairTruncatedJSON(objectJSON)
            if recovered != objectJSON, let recoveredData = recovered.data(using: .utf8),
               let dto = try? JSONDecoder().decode(EventDetailsDTO.self, from: recoveredData) {
                SharedContainerService.writeDebugLog("JSON recovered from truncation (multi)")
                return ExtractionOutput(events: [dto.toEventDetails()], usage: usage)
            }
            SharedContainerService.writeDebugLog("JSON decode failed (multi). Raw: \(objectJSON.prefix(500))")
            throw ClaudeAPIError.decodingFailed(error.localizedDescription)
        }
    }

    /// Sends the extraction request via the Worker proxy and returns raw text + usage from the response.
    private static func sendRequestRaw(_ requestBody: [String: Any]) async throws -> (String, ClaudeResponse.Usage?) {
        guard let token = await WorkerAuthService.accessToken() else {
            SharedContainerService.writeDebugLog("API: auth failed — could not obtain JWT")
            throw ClaudeAPIError.authFailed
        }

        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        let model = requestBody["model"] as? String ?? "unknown"
        let maxTokens = requestBody["max_tokens"] as? Int ?? 0
        SharedContainerService.writeDebugLog("API: request model=\(model), max_tokens=\(maxTokens), body=\(bodyData.count) bytes")
        let (data, httpResponse) = try await executeExtractRequest(bodyData: bodyData, token: token)

        // On 401, refresh the token once and retry
        if httpResponse.statusCode == 401 {
            SharedContainerService.writeDebugLog("API: 401 received, refreshing token and retrying")
            WorkerAuthService.clearCachedToken()
            guard let freshToken = await WorkerAuthService.accessToken() else {
                throw ClaudeAPIError.authFailed
            }
            let (retryData, retryResponse) = try await executeExtractRequest(bodyData: bodyData, token: freshToken)
            return try parseClaudeResponse(data: retryData, httpResponse: retryResponse)
        }

        return try parseClaudeResponse(data: data, httpResponse: httpResponse)
    }

    private static func executeExtractRequest(bodyData: Data, token: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: extractEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData
        request.timeoutInterval = 90

        SharedContainerService.writeDebugLog("API: sending extract request (\(bodyData.count) bytes)")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            SharedContainerService.writeDebugLog("API: network error: \(error)")
            throw ClaudeAPIError.apiError("Network error: \(error.localizedDescription)")
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        return (data, httpResponse)
    }

    private static func parseClaudeResponse(data: Data, httpResponse: HTTPURLResponse) throws -> (String, ClaudeResponse.Usage?) {
        SharedContainerService.writeDebugLog("API: HTTP \(httpResponse.statusCode), response \(data.count) bytes")

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            SharedContainerService.writeDebugLog("API: error body: \(String(body.prefix(500)))")
            throw ClaudeAPIError.apiError("HTTP \(httpResponse.statusCode): \(body)")
        }

        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        let blockTypes = claudeResponse.content.map { $0.type }
        SharedContainerService.writeDebugLog("API: stop_reason=\(claudeResponse.stopReason ?? "nil"), content blocks: \(blockTypes)")

        if let usage = claudeResponse.usage {
            SharedContainerService.writeDebugLog("API: tokens — input: \(usage.inputTokens), output: \(usage.outputTokens), total: \(usage.totalTokens)")
        }

        let allText = claudeResponse.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
        guard !allText.isEmpty else {
            SharedContainerService.writeDebugLog("API: no text block found in response")
            throw ClaudeAPIError.invalidResponse
        }
        let jsonString = allText.joined()

        SharedContainerService.writeDebugLog("API: response JSON (\(jsonString.count) chars): \(String(jsonString.prefix(1000)))")
        return (jsonString, claudeResponse.usage)
    }

    private static func sendRequest(_ requestBody: [String: Any]) async throws -> ExtractionOutput {
        let (rawText, usage) = try await sendRequestRaw(requestBody)
        let cleanJSON = extractJSON(from: rawText)

        // If no JSON object found, Claude responded with prose — treat as no event found
        if !cleanJSON.contains("{") {
            SharedContainerService.writeDebugLog("API: no JSON object in response — narrative text detected")
            throw ClaudeAPIError.noEventFound
        }

        guard let jsonData = cleanJSON.data(using: .utf8) else {
            throw ClaudeAPIError.decodingFailed("Could not convert response to data")
        }

        do {
            let dto = try JSONDecoder().decode(EventDetailsDTO.self, from: jsonData)
            if dto.title == nil && dto.venue == nil && dto.startDatetime == nil {
                throw ClaudeAPIError.noEventFound
            }
            return ExtractionOutput(events: [dto.toEventDetails()], usage: usage)
        } catch let error as ClaudeAPIError {
            throw error
        } catch {
            // Try truncation recovery: close open strings/objects
            let recovered = repairTruncatedJSON(cleanJSON)
            if recovered != cleanJSON, let recoveredData = recovered.data(using: .utf8),
               let dto = try? JSONDecoder().decode(EventDetailsDTO.self, from: recoveredData) {
                SharedContainerService.writeDebugLog("JSON recovered from truncation")
                return ExtractionOutput(events: [dto.toEventDetails()], usage: usage)
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

    /// Build web search tool config with user_location for localized results.
    private static func webSearchTool(maxUses: Int) -> [String: Any] {
        var tool: [String: Any] = [
            "type": "web_search_20250305",
            "name": "web_search",
            "max_uses": maxUses
        ]

        // Add user_location from device timezone for localized search results
        let tz = TimeZone.current
        let regionCode = Locale.current.region?.identifier
        var userLocation: [String: Any] = [
            "type": "approximate",
            "timezone": tz.identifier
        ]
        if let regionCode {
            userLocation["country"] = regionCode
        }
        tool["user_location"] = userLocation

        return tool
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
    let stopReason: String?
    let usage: Usage?

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
        case usage
    }

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }

    struct Usage: Decodable {
        let inputTokens: Int
        let outputTokens: Int

        enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }

        var totalTokens: Int { inputTokens + outputTokens }
    }
}

struct ExtractionOutput {
    let events: [EventDetails]
    let usage: ClaudeResponse.Usage?
}
