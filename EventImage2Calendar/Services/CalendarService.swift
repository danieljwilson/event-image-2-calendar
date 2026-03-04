import UIKit

enum CalendarService {

    /// Opens Google Calendar with pre-filled event details
    static func openGoogleCalendar(event: EventDetails) {
        guard let url = googleCalendarURL(for: event) else { return }
        UIApplication.shared.open(url)
    }

    /// Constructs Google Calendar URL with event details
    static func googleCalendarURL(for event: EventDetails) -> URL? {
        var components = URLComponents(string: "https://calendar.google.com/calendar/render")!

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let startStr = dateFormatter.string(from: event.startDate)
        let endStr = dateFormatter.string(from: event.endDate)

        // Truncate description to avoid URL length issues
        let description = String(event.eventDescription.prefix(500))

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

    /// Generates .ics file content and returns a temporary file URL for sharing
    static func generateICSFile(for event: EventDetails) -> URL? {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let location = [event.venue, event.address]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")

        // Escape special characters for iCalendar format
        let escapedTitle = event.title.replacingOccurrences(of: ",", with: "\\,")
        let escapedDescription = event.eventDescription.replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
        let escapedLocation = location.replacingOccurrences(of: ",", with: "\\,")

        let icsContent = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//EventSnap//EN
        BEGIN:VEVENT
        DTSTART:\(dateFormatter.string(from: event.startDate))
        DTEND:\(dateFormatter.string(from: event.endDate))
        SUMMARY:\(escapedTitle)
        LOCATION:\(escapedLocation)
        DESCRIPTION:\(escapedDescription)
        END:VEVENT
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
