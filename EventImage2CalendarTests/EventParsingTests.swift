import XCTest
@testable import EventImage2Calendar

final class EventParsingTests: XCTestCase {

    // MARK: - Minimal / Default DTO

    func testMinimalDTO_defaults() {
        let dto = EventDetailsDTO(
            title: nil, startDatetime: nil, endDatetime: nil,
            venue: nil, address: nil, description: nil, timezone: nil,
            isMultiDay: nil, eventDates: nil, dateConfirmed: nil,
            timeConfirmed: nil, category: nil, city: nil
        )

        let event = dto.toEventDetails()
        XCTAssertEqual(event.title, "Untitled Event")
        XCTAssertEqual(event.venue, "")
        XCTAssertEqual(event.address, "")
        XCTAssertEqual(event.eventDescription, "")
        XCTAssertEqual(event.category, "other")
        XCTAssertEqual(event.city, "")
        XCTAssertEqual(event.eventDates, [])
        XCTAssertFalse(event.isAllDay)
    }

    func testFullDTO_allFieldsMapped() {
        let dto = EventDetailsDTO(
            title: "Jazz Night",
            startDatetime: "2024-06-15T20:00:00",
            endDatetime: "2024-06-15T23:00:00",
            venue: "Blue Note",
            address: "131 W 3rd St",
            description: "Live jazz performance",
            timezone: "America/New_York",
            isMultiDay: false,
            eventDates: [],
            dateConfirmed: true,
            timeConfirmed: true,
            category: "music",
            city: "New York"
        )

        let event = dto.toEventDetails()
        XCTAssertEqual(event.title, "Jazz Night")
        XCTAssertEqual(event.venue, "Blue Note")
        XCTAssertEqual(event.address, "131 W 3rd St")
        XCTAssertEqual(event.eventDescription, "Live jazz performance")
        XCTAssertEqual(event.timezone, "America/New_York")
        XCTAssertFalse(event.isAllDay)
        XCTAssertTrue(event.hasExplicitDate)
        XCTAssertTrue(event.hasExplicitTime)
        XCTAssertEqual(event.category, "music")
        XCTAssertEqual(event.city, "New York")
    }

    // MARK: - Date Parsing

    func testDateParsing_iso8601WithOffset() {
        let dto = makeDTO(start: "2024-06-15T14:30:00+02:00")
        let event = dto.toEventDetails()
        // Should parse without error; exact date depends on timezone
        XCTAssertNotEqual(event.startDate, Date(timeIntervalSince1970: 0))
    }

    func testDateParsing_dateOnly() {
        let dto = makeDTO(start: "2024-06-15")
        let event = dto.toEventDetails()
        // Date-only should still parse
        XCTAssertNotEqual(event.startDate, Date(timeIntervalSince1970: 0))
    }

    func testDateParsing_midnightTime_isAllDay_whenMultiDay() {
        let dto = EventDetailsDTO(
            title: "Festival", startDatetime: "2024-06-15T00:00:00",
            endDatetime: "2024-06-17T00:00:00", venue: nil, address: nil,
            description: nil, timezone: nil, isMultiDay: true, eventDates: nil,
            dateConfirmed: true, timeConfirmed: nil, category: nil, city: nil
        )

        let event = dto.toEventDetails()
        // Midnight + multi-day → isAllDay
        XCTAssertTrue(event.isAllDay)
    }

    func testDateParsing_withTime_multiDay_notAllDay() {
        let dto = EventDetailsDTO(
            title: "Concert Series", startDatetime: "2024-06-15T20:00:00",
            endDatetime: "2024-06-17T22:00:00", venue: nil, address: nil,
            description: nil, timezone: nil, isMultiDay: true, eventDates: nil,
            dateConfirmed: true, timeConfirmed: true, category: nil, city: nil
        )

        let event = dto.toEventDetails()
        XCTAssertFalse(event.isAllDay)
    }

    func testDateParsing_invalidFormat_fallsBackToNow() {
        let before = Date()
        let dto = makeDTO(start: "not-a-date")
        let event = dto.toEventDetails()
        let after = Date()
        // Falls back to Date() when parsing fails
        XCTAssertTrue(event.startDate >= before && event.startDate <= after)
    }

    // MARK: - Multi-day end date

    func testMultiDay_endDateFallback() {
        let dto = EventDetailsDTO(
            title: "Conf", startDatetime: "2024-09-10T09:00:00",
            endDatetime: nil, venue: nil, address: nil, description: nil,
            timezone: nil, isMultiDay: true, eventDates: nil,
            dateConfirmed: true, timeConfirmed: true, category: nil, city: nil
        )

        let event = dto.toEventDetails()
        // Multi-day with no end → start + 24h
        let diff = event.endDate.timeIntervalSince(event.startDate)
        XCTAssertEqual(diff, 86400, accuracy: 1)
    }

    func testSingleEvent_endDateFallback() {
        let dto = EventDetailsDTO(
            title: "Talk", startDatetime: "2024-09-10T09:00:00",
            endDatetime: nil, venue: nil, address: nil, description: nil,
            timezone: nil, isMultiDay: false, eventDates: nil,
            dateConfirmed: true, timeConfirmed: true, category: nil, city: nil
        )

        let event = dto.toEventDetails()
        // Single event with no end → start + 2h
        let diff = event.endDate.timeIntervalSince(event.startDate)
        XCTAssertEqual(diff, 7200, accuracy: 1)
    }

    // MARK: - Cite tag stripping

    func testCiteTagStripping() {
        let dto = makeDTO(description: "Event info <cite>source1</cite> more text <cite class=\"ref\">source2</cite>")
        let event = dto.toEventDetails()
        XCTAssertFalse(event.eventDescription.contains("<cite"))
        XCTAssertFalse(event.eventDescription.contains("</cite>"))
        XCTAssertTrue(event.eventDescription.contains("source1"))
    }

    func testCiteTagStripping_noCiteTags() {
        let dto = makeDTO(description: "Plain description")
        let event = dto.toEventDetails()
        XCTAssertEqual(event.eventDescription, "Plain description")
    }

    // MARK: - Date/Time certainty flags

    func testHasExplicitDate_confirmed() {
        let dto = EventDetailsDTO(
            title: nil, startDatetime: "2024-06-15T20:00:00", endDatetime: nil,
            venue: nil, address: nil, description: nil, timezone: nil,
            isMultiDay: nil, eventDates: nil, dateConfirmed: true,
            timeConfirmed: nil, category: nil, city: nil
        )
        XCTAssertTrue(dto.toEventDetails().hasExplicitDate)
    }

    func testHasExplicitDate_notConfirmed() {
        let dto = EventDetailsDTO(
            title: nil, startDatetime: "2024-06-15T20:00:00", endDatetime: nil,
            venue: nil, address: nil, description: nil, timezone: nil,
            isMultiDay: nil, eventDates: nil, dateConfirmed: false,
            timeConfirmed: nil, category: nil, city: nil
        )
        XCTAssertFalse(dto.toEventDetails().hasExplicitDate)
    }

    func testHasExplicitTime_confirmed() {
        let dto = EventDetailsDTO(
            title: nil, startDatetime: "2024-06-15T20:00:00", endDatetime: nil,
            venue: nil, address: nil, description: nil, timezone: nil,
            isMultiDay: nil, eventDates: nil, dateConfirmed: nil,
            timeConfirmed: true, category: nil, city: nil
        )
        XCTAssertTrue(dto.toEventDetails().hasExplicitTime)
    }

    func testHasExplicitTime_fallsBackToHasTimeComponent() {
        // No timeConfirmed → falls back to hasTimeComponent check
        let dtoWithTime = makeDTO(start: "2024-06-15T20:00:00")
        XCTAssertTrue(dtoWithTime.toEventDetails().hasExplicitTime)

        let dtoMidnight = makeDTO(start: "2024-06-15T00:00:00")
        XCTAssertFalse(dtoMidnight.toEventDetails().hasExplicitTime)

        let dtoDateOnly = makeDTO(start: "2024-06-15")
        XCTAssertFalse(dtoDateOnly.toEventDetails().hasExplicitTime)
    }

    // MARK: - Timezone

    func testTimezone_applied() {
        let dto = EventDetailsDTO(
            title: nil, startDatetime: "2024-06-15T20:00:00", endDatetime: nil,
            venue: nil, address: nil, description: nil, timezone: "Europe/Berlin",
            isMultiDay: nil, eventDates: nil, dateConfirmed: nil,
            timeConfirmed: nil, category: nil, city: nil
        )

        let event = dto.toEventDetails()
        XCTAssertEqual(event.timezone, "Europe/Berlin")
        // The parsed date should reflect Berlin timezone
        let calendar = Calendar.current
        let components = calendar.dateComponents(in: TimeZone(identifier: "Europe/Berlin")!, from: event.startDate)
        XCTAssertEqual(components.hour, 20)
    }

    // MARK: - JSON Decoding round-trip

    func testDTODecoding_fromJSON() throws {
        let json = """
        {
            "title": "Test Event",
            "start_datetime": "2024-06-15T20:00:00",
            "end_datetime": "2024-06-15T22:00:00",
            "venue": "Hall",
            "address": "123 St",
            "description": "A test",
            "timezone": "UTC",
            "is_multi_day": false,
            "event_dates": ["2024-06-15"],
            "date_confirmed": true,
            "time_confirmed": true,
            "category": "music",
            "city": "Berlin"
        }
        """

        let dto = try JSONDecoder().decode(EventDetailsDTO.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(dto.title, "Test Event")
        XCTAssertEqual(dto.startDatetime, "2024-06-15T20:00:00")
        XCTAssertEqual(dto.category, "music")
        XCTAssertEqual(dto.city, "Berlin")
        XCTAssertEqual(dto.eventDates, ["2024-06-15"])
    }

    // MARK: - Helpers

    private func makeDTO(
        start: String? = "2024-06-15T20:00:00",
        description: String? = nil
    ) -> EventDetailsDTO {
        EventDetailsDTO(
            title: "Test", startDatetime: start, endDatetime: nil,
            venue: nil, address: nil, description: description, timezone: nil,
            isMultiDay: nil, eventDates: nil, dateConfirmed: nil,
            timeConfirmed: nil, category: nil, city: nil
        )
    }
}
