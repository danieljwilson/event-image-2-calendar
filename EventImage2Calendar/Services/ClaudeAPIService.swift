import Foundation
import CoreLocation

enum ClaudeAPIError: LocalizedError {
    case noAPIKey
    case invalidResponse
    case apiError(String)
    case decodingFailed(String)

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
        }
    }
}

enum ClaudeAPIService {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static func extractEvent(
        imageData: Data,
        location: CLLocationCoordinate2D?
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
        You are an event detail extractor. Analyze the event poster image and extract structured details. \
        Respond with ONLY a JSON object, no markdown fences, no other text. Use this exact schema:
        {
          "title": "Event title",
          "start_datetime": "ISO 8601 datetime (e.g., 2026-03-15T19:00:00)",
          "end_datetime": "ISO 8601 datetime or null if not specified",
          "venue": "Venue name",
          "address": "Full address including city, state/country",
          "description": "Brief description of the event (1-3 sentences)",
          "timezone": "IANA timezone (e.g., America/New_York)"
        }
        If a field cannot be determined from the image, use your best guess based on context or set to null. \
        For dates without a year, assume the nearest future occurrence.
        """

        let userText = """
        Extract the event details from this poster image.

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

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw ClaudeAPIError.apiError("HTTP \(httpResponse.statusCode): \(body)")
        }

        // Parse Claude's response
        let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        guard let textContent = claudeResponse.content.first(where: { $0.type == "text" }),
              let jsonString = textContent.text else {
            throw ClaudeAPIError.invalidResponse
        }

        // Extract JSON from response (handles markdown fences)
        let cleanJSON = extractJSON(from: jsonString)
        guard let jsonData = cleanJSON.data(using: .utf8) else {
            throw ClaudeAPIError.decodingFailed("Could not convert response to data")
        }

        do {
            let dto = try JSONDecoder().decode(EventDetailsDTO.self, from: jsonData)
            return dto.toEventDetails()
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
