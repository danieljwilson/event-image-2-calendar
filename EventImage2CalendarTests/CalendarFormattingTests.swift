import XCTest
@testable import EventImage2Calendar

final class CalendarFormattingTests: XCTestCase {

    // MARK: - Google Calendar URL

    func testGoogleCalendarURL_timedEvent() {
        let event = EventDetails(
            title: "Concert",
            startDate: date(2024, 6, 15, 20, 0),
            endDate: date(2024, 6, 15, 23, 0),
            venue: "Jazz Club",
            address: "123 Main St"
        )

        let url = CalendarService.googleCalendarURL(for: event)
        XCTAssertNotNil(url)

        let components = URLComponents(url: url!, resolvingAgainstBaseURL: false)!
        let query = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })

        XCTAssertEqual(query["action"], "TEMPLATE")
        XCTAssertEqual(query["text"], "Concert")
        XCTAssertEqual(query["location"], "Jazz Club, 123 Main St")
        XCTAssertTrue(query["dates"]!.contains("T"))
    }

    func testGoogleCalendarURL_allDayEvent() {
        let event = EventDetails(
            title: "Festival",
            startDate: date(2024, 7, 4, 0, 0),
            endDate: date(2024, 7, 4, 0, 0),
            isAllDay: true
        )

        let url = CalendarService.googleCalendarURL(for: event)!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let query = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })

        let dates = query["dates"]!
        // All-day format: yyyyMMdd/yyyyMMdd, end is exclusive (+1 day)
        XCTAssertEqual(dates, "20240704/20240705")
    }

    func testGoogleCalendarURL_multiDayAllDay() {
        let event = EventDetails(
            title: "Conference",
            startDate: date(2024, 9, 10, 0, 0),
            endDate: date(2024, 9, 12, 0, 0),
            isAllDay: true
        )

        let url = CalendarService.googleCalendarURL(for: event)!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let query = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })

        XCTAssertEqual(query["dates"], "20240910/20240913")
    }

    func testGoogleCalendarURL_withTimezone() {
        let event = EventDetails(
            title: "Meeting",
            startDate: date(2024, 3, 1, 14, 0),
            endDate: date(2024, 3, 1, 15, 0),
            timezone: "Europe/Berlin"
        )

        let url = CalendarService.googleCalendarURL(for: event)!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let query = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })

        XCTAssertEqual(query["ctz"], "Europe/Berlin")
    }

    func testGoogleCalendarURL_noVenue() {
        let event = EventDetails(title: "Call", startDate: Date(), endDate: Date())

        let url = CalendarService.googleCalendarURL(for: event)!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let query = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })

        XCTAssertEqual(query["location"], "")
    }

    func testGoogleCalendarURL_specialCharacters() {
        let event = EventDetails(
            title: "Art & Music: Live!",
            startDate: date(2024, 5, 1, 19, 0),
            endDate: date(2024, 5, 1, 22, 0),
            venue: "Café Müller"
        )

        let url = CalendarService.googleCalendarURL(for: event)
        XCTAssertNotNil(url)
        // URLComponents handles percent-encoding automatically
        XCTAssertTrue(url!.absoluteString.contains("Art"))
    }

    // MARK: - ICS Generation

    func testICSGeneration_emptyArray() {
        let url = CalendarService.generateICSFile(for: [])
        XCTAssertNil(url)
    }

    func testICSGeneration_singleTimedEvent() throws {
        let event = EventDetails(
            title: "Show",
            startDate: date(2024, 8, 20, 20, 0),
            endDate: date(2024, 8, 20, 22, 0),
            venue: "Theater"
        )

        let url = try XCTUnwrap(CalendarService.generateICSFile(for: event))
        let content = try String(contentsOf: url)

        XCTAssertTrue(content.contains("BEGIN:VCALENDAR"))
        XCTAssertTrue(content.contains("END:VCALENDAR"))
        XCTAssertTrue(content.contains("BEGIN:VEVENT"))
        XCTAssertTrue(content.contains("SUMMARY:Show"))
        XCTAssertTrue(content.contains("DTSTART:"))
        XCTAssertTrue(content.contains("DTEND:"))
        XCTAssertFalse(content.contains("VALUE=DATE"))
    }

    func testICSGeneration_allDayEvent() throws {
        let event = EventDetails(
            title: "Holiday",
            startDate: date(2024, 12, 25, 0, 0),
            endDate: date(2024, 12, 25, 0, 0),
            isAllDay: true
        )

        let url = try XCTUnwrap(CalendarService.generateICSFile(for: event))
        let content = try String(contentsOf: url)

        XCTAssertTrue(content.contains("DTSTART;VALUE=DATE:20241225"))
        XCTAssertTrue(content.contains("DTEND;VALUE=DATE:20241226"))
    }

    func testICSGeneration_multipleEvents() throws {
        let events = [
            EventDetails(title: "Event 1", startDate: date(2024, 1, 1, 10, 0), endDate: date(2024, 1, 1, 12, 0)),
            EventDetails(title: "Event 2", startDate: date(2024, 1, 2, 14, 0), endDate: date(2024, 1, 2, 16, 0)),
        ]

        let url = try XCTUnwrap(CalendarService.generateICSFile(for: events))
        let content = try String(contentsOf: url)

        let veventCount = content.components(separatedBy: "BEGIN:VEVENT").count - 1
        XCTAssertEqual(veventCount, 2)
        XCTAssertTrue(content.contains("SUMMARY:Event 1"))
        XCTAssertTrue(content.contains("SUMMARY:Event 2"))
    }

    func testICSGeneration_commaEscaping() throws {
        let event = EventDetails(
            title: "Dinner, Dance",
            startDate: date(2024, 6, 1, 19, 0),
            endDate: date(2024, 6, 1, 23, 0),
            venue: "Hall, Building A",
            eventDescription: "Line 1\nLine 2"
        )

        let url = try XCTUnwrap(CalendarService.generateICSFile(for: event))
        let content = try String(contentsOf: url)

        XCTAssertTrue(content.contains("SUMMARY:Dinner\\, Dance"))
        XCTAssertTrue(content.contains("LOCATION:Hall\\, Building A"))
        XCTAssertTrue(content.contains("DESCRIPTION:Line 1\\nLine 2"))
    }

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar.current.date(from: components)!
    }
}
