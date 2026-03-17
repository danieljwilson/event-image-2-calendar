import UIKit

enum CalendarService {

    /// Opens Google Calendar with pre-filled event details
    static func openGoogleCalendar(event: EventDetails) {
        guard let url = googleCalendarURL(for: event) else { return }
        UIApplication.shared.open(url)
    }

    /// Opens Google Calendar for multiple events with staggered delays
    static func openGoogleCalendar(events: [EventDetails]) {
        for (index, event) in events.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.5) {
                if let url = googleCalendarURL(for: event) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    /// Constructs Google Calendar URL with event details
    static func googleCalendarURL(for event: EventDetails) -> URL? {
        var components = URLComponents(string: "https://calendar.google.com/calendar/render")!

        let startStr: String
        let endStr: String

        if event.isAllDay {
            // All-day format: yyyyMMdd (end date is exclusive in Google Calendar)
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd"
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")

            startStr = dateFormatter.string(from: event.startDate)
            // Add one day to end date (Google Calendar all-day end is exclusive)
            let exclusiveEnd = Calendar.current.date(byAdding: .day, value: 1, to: event.endDate) ?? event.endDate
            endStr = dateFormatter.string(from: exclusiveEnd)
        } else {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss"
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")

            startStr = dateFormatter.string(from: event.startDate)
            endStr = dateFormatter.string(from: event.endDate)
        }

        // Convert raw URLs to clickable HTML links for Google Calendar
        let description = Self.formatDescriptionWithLinks(event.eventDescription)

        let location = [event.venue, event.address]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        components.queryItems = [
            URLQueryItem(name: "action", value: "TEMPLATE"),
            URLQueryItem(name: "text", value: event.title),
            URLQueryItem(name: "dates", value: "\(startStr)/\(endStr)"),
            URLQueryItem(name: "location", value: location),
            URLQueryItem(name: "details", value: description),
        ]

        if let tz = event.timezone {
            components.queryItems?.append(URLQueryItem(name: "ctz", value: tz))
        }

        return components.url
    }

    /// Replaces raw URLs in description with clickable HTML links for Google Calendar
    private static func formatDescriptionWithLinks(_ text: String) -> String {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        guard let detector else { return String(text.prefix(500)) }

        let nsText = text as NSString
        let matches = detector.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        guard !matches.isEmpty else { return String(text.prefix(500)) }

        var result = text
        // Replace in reverse order to preserve ranges
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result),
                  let url = match.url else { continue }
            result.replaceSubrange(range, with: "<a href=\"\(url.absoluteString)\">Link</a>")
        }

        return String(result.prefix(500))
    }

    /// Generates .ics file for a single event
    static func generateICSFile(for event: EventDetails) -> URL? {
        generateICSFile(for: [event])
    }

    /// Generates .ics file with one or more VEVENTs and returns a temporary file URL for sharing
    static func generateICSFile(for events: [EventDetails]) -> URL? {
        guard !events.isEmpty else { return nil }

        var vevents: [String] = []

        for event in events {
            let location = [event.venue, event.address]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")

            let escapedTitle = event.title.replacingOccurrences(of: ",", with: "\\,")
            let escapedDescription = event.eventDescription.replacingOccurrences(of: ",", with: "\\,")
                .replacingOccurrences(of: "\n", with: "\\n")
            let escapedLocation = location.replacingOccurrences(of: ",", with: "\\,")

            let dtStart: String
            let dtEnd: String

            if event.isAllDay {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyyMMdd"
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")

                let exclusiveEnd = Calendar.current.date(byAdding: .day, value: 1, to: event.endDate) ?? event.endDate
                dtStart = "DTSTART;VALUE=DATE:\(dateFormatter.string(from: event.startDate))"
                dtEnd = "DTEND;VALUE=DATE:\(dateFormatter.string(from: exclusiveEnd))"
            } else {
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss"
                dateFormatter.locale = Locale(identifier: "en_US_POSIX")

                dtStart = "DTSTART:\(dateFormatter.string(from: event.startDate))"
                dtEnd = "DTEND:\(dateFormatter.string(from: event.endDate))"
            }

            vevents.append("""
            BEGIN:VEVENT
            UID:\(UUID().uuidString)
            \(dtStart)
            \(dtEnd)
            SUMMARY:\(escapedTitle)
            LOCATION:\(escapedLocation)
            DESCRIPTION:\(escapedDescription)
            END:VEVENT
            """)
        }

        let icsContent = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//EventSnap//EN
        \(vevents.joined(separator: "\n"))
        END:VCALENDAR
        """

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("event.ics")

        do {
            try icsContent.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            return nil
        }
    }
}
