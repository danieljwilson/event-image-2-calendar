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
        // Resolve the event timezone for parsing dates without offset
        let eventTimeZone: TimeZone? = timezone.flatMap { TimeZone(identifier: $0) }

        let start = parseDate(startDatetime, eventTimeZone: eventTimeZone) ?? Date()
        let end = parseDate(endDatetime, eventTimeZone: eventTimeZone) ?? start.addingTimeInterval(7200)

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

    private func parseDate(_ string: String?, eventTimeZone: TimeZone?) -> Date? {
        guard let string else { return nil }

        // Try ISO 8601 with explicit timezone offset (e.g., 2026-03-20T19:00:00+01:00)
        // These are already unambiguous, so parse as-is
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: string) { return date }

        // For dates WITHOUT timezone offset, interpret in the event's timezone
        // (e.g., "2026-03-20T19:00:00" with timezone "Europe/Paris" means 19:00 Paris time)
        let tz = eventTimeZone ?? .current
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = tz

        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: string) { return date }
        }

        return nil
    }
}
