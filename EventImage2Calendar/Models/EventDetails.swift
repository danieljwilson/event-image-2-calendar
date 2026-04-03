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
    var isAllDay: Bool
    var eventDates: [String]
    var hasExplicitDate: Bool
    var hasExplicitTime: Bool
    var category: String
    var city: String

    init(
        title: String = "",
        startDate: Date = Date(),
        endDate: Date = Date().addingTimeInterval(7200),
        venue: String = "",
        address: String = "",
        eventDescription: String = "",
        timezone: String? = nil,
        isAllDay: Bool = false,
        eventDates: [String] = [],
        hasExplicitDate: Bool = true,
        hasExplicitTime: Bool = true,
        category: String = "other",
        city: String = ""
    ) {
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.venue = venue
        self.address = address
        self.eventDescription = eventDescription
        self.timezone = timezone
        self.isAllDay = isAllDay
        self.eventDates = eventDates
        self.hasExplicitDate = hasExplicitDate
        self.hasExplicitTime = hasExplicitTime
        self.category = category
        self.city = city
    }
}

// MARK: - JSON Decoding from LLM API response

struct EventDetailsDTO: Decodable {
    let title: String?
    let startDatetime: String?
    let endDatetime: String?
    let venue: String?
    let address: String?
    let description: String?
    let timezone: String?
    let isMultiDay: Bool?
    let eventDates: [String]?
    let dateConfirmed: Bool?
    let timeConfirmed: Bool?
    let category: String?
    let city: String?

    enum CodingKeys: String, CodingKey {
        case title
        case startDatetime = "start_datetime"
        case endDatetime = "end_datetime"
        case venue
        case address
        case description
        case timezone
        case isMultiDay = "is_multi_day"
        case eventDates = "event_dates"
        case dateConfirmed = "date_confirmed"
        case timeConfirmed = "time_confirmed"
        case category
        case city
    }

    func toEventDetails() -> EventDetails {
        let eventTimeZone: TimeZone? = timezone.flatMap { TimeZone(identifier: $0) }
        let isMulti = isMultiDay ?? false

        let parsedStart = parseDate(startDatetime, eventTimeZone: eventTimeZone)
        let start = parsedStart ?? Date()
        let end: Date
        if isMulti {
            end = parseDate(endDatetime, eventTimeZone: eventTimeZone) ?? start.addingTimeInterval(86400)
        } else {
            end = parseDate(endDatetime, eventTimeZone: eventTimeZone) ?? start.addingTimeInterval(7200)
        }

        let hasDate = dateConfirmed ?? (parsedStart != nil)
        let hasTime = timeConfirmed ?? Self.hasTimeComponent(startDatetime)

        return EventDetails(
            title: title ?? "Untitled Event",
            startDate: start,
            endDate: end,
            venue: venue ?? "",
            address: address ?? "",
            eventDescription: Self.stripCiteTags(description ?? ""),
            timezone: timezone,
            isAllDay: isMulti && !Self.hasTimeComponent(startDatetime),
            eventDates: eventDates ?? [],
            hasExplicitDate: hasDate,
            hasExplicitTime: hasTime,
            category: category ?? "other",
            city: city ?? ""
        )
    }

    /// Strip `<cite>` and `</cite>` tags from LLM web search responses.
    private static func stripCiteTags(_ text: String) -> String {
        text.replacingOccurrences(of: #"<cite[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "</cite>", with: "")
    }

    /// Returns true if the datetime string contains a meaningful time component (not midnight placeholder).
    private static func hasTimeComponent(_ dateString: String?) -> Bool {
        guard let s = dateString else { return false }
        return s.contains("T") && !s.hasSuffix("T00:00:00")
    }

    private func parseDate(_ string: String?, eventTimeZone: TimeZone?) -> Date? {
        guard let string else { return nil }

        // Try ISO 8601 with explicit timezone offset
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: string) { return date }

        let tz = eventTimeZone ?? .current
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = tz

        // Try datetime formats
        for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: string) { return date }
        }

        // Try date-only format (for multi-day events)
        dateFormatter.dateFormat = "yyyy-MM-dd"
        if let date = dateFormatter.date(from: string) { return date }

        return nil
    }
}
