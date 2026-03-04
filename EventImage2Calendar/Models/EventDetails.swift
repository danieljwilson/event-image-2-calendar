import Foundation

@Observable
class EventDetails {
    var title: String
    var startDate: Date
    var endDate: Date
    var venue: String
    var address: String
    var eventDescription: String
    var timezone: String?

    init(
        title: String = "",
        startDate: Date = Date(),
        endDate: Date = Date().addingTimeInterval(7200),
        venue: String = "",
        address: String = "",
        eventDescription: String = "",
        timezone: String? = nil
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.venue = venue
        self.address = address
        self.eventDescription = eventDescription
        self.timezone = timezone
    }
}

// MARK: - JSON Decoding from Claude API response

struct EventDetailsDTO: Decodable {
    let title: String?
    let startDatetime: String?
    let endDatetime: String?
    let venue: String?
    let address: String?
    let description: String?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case title
        case startDatetime = "start_datetime"
        case endDatetime = "end_datetime"
        case venue
        case address
        case description
        case timezone
    }

    func toEventDetails() -> EventDetails {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]

        // Try multiple date formats for resilience
        let start = parseDate(startDatetime) ?? Date()
        let end = parseDate(endDatetime) ?? start.addingTimeInterval(7200)

        return EventDetails(
            title: title ?? "Untitled Event",
            startDate: start,
            endDate: end,
            venue: venue ?? "",
            address: address ?? "",
            eventDescription: description ?? "",
            timezone: timezone
        )
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }

        // Try ISO 8601 with timezone
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: string) { return date }

        // Try ISO 8601 without timezone
        isoFormatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        if let date = isoFormatter.date(from: string) { return date }

        // Try common date format without T separator
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: string) { return date }
        }

        return nil
    }
}
