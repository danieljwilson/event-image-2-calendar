import XCTest
@testable import EventImage2Calendar

final class PersistenceTests: XCTestCase {

    // MARK: - canRetry

    func testCanRetry_underMax() {
        let event = PersistedEvent()
        event.retryCount = 2
        XCTAssertTrue(event.canRetry)
    }

    func testCanRetry_atMax() {
        let event = PersistedEvent()
        event.retryCount = 5
        XCTAssertFalse(event.canRetry)
    }

    func testCanRetry_overMax() {
        let event = PersistedEvent()
        event.retryCount = 10
        XCTAssertFalse(event.canRetry)
    }

    // MARK: - hasRetryableError

    func testHasRetryableError_nil() {
        let event = PersistedEvent()
        event.errorMessage = nil
        XCTAssertFalse(event.hasRetryableError)
    }

    func testHasRetryableError_networkError() {
        let event = PersistedEvent()
        event.errorMessage = "Network error: connection timeout"
        XCTAssertTrue(event.hasRetryableError)
    }

    func testHasRetryableError_serverError() {
        let event = PersistedEvent()
        event.errorMessage = "Server error (500)"
        XCTAssertTrue(event.hasRetryableError)
    }

    func testHasRetryableError_rateLimited() {
        let event = PersistedEvent()
        event.errorMessage = "Too many requests, please try again"
        XCTAssertTrue(event.hasRetryableError)
    }

    func testHasRetryableError_nonRetryable() {
        let event = PersistedEvent()
        event.errorMessage = "Invalid image format"
        XCTAssertFalse(event.hasRetryableError)
    }

    // MARK: - needsDateCorrection

    func testNeedsDateCorrection_noDate() {
        let event = PersistedEvent()
        event.hasExplicitDate = false
        event.hasExplicitTime = true
        XCTAssertTrue(event.needsDateCorrection)
    }

    func testNeedsDateCorrection_noTime_notAllDay() {
        let event = PersistedEvent()
        event.hasExplicitDate = true
        event.hasExplicitTime = false
        event.isAllDay = false
        XCTAssertTrue(event.needsDateCorrection)
    }

    func testNeedsDateCorrection_noTime_allDay() {
        let event = PersistedEvent()
        event.hasExplicitDate = true
        event.hasExplicitTime = false
        event.isAllDay = true
        XCTAssertFalse(event.needsDateCorrection)
    }

    func testNeedsDateCorrection_complete() {
        let event = PersistedEvent()
        event.hasExplicitDate = true
        event.hasExplicitTime = true
        XCTAssertFalse(event.needsDateCorrection)
    }

    func testNeedsDateCorrection_noDateAndNoTime() {
        let event = PersistedEvent()
        event.hasExplicitDate = false
        event.hasExplicitTime = false
        event.isAllDay = false
        XCTAssertTrue(event.needsDateCorrection)
    }

    // MARK: - missingFieldDescription

    func testMissingFieldDescription_noDateNoTime() {
        let event = PersistedEvent()
        event.hasExplicitDate = false
        event.hasExplicitTime = false
        event.isAllDay = false
        XCTAssertEqual(event.missingFieldDescription, "Set the date and timing.")
    }

    func testMissingFieldDescription_noDateOnly() {
        let event = PersistedEvent()
        event.hasExplicitDate = false
        event.hasExplicitTime = true
        XCTAssertEqual(event.missingFieldDescription, "Please enter the date.")
    }

    func testMissingFieldDescription_noTimeOnly() {
        let event = PersistedEvent()
        event.hasExplicitDate = true
        event.hasExplicitTime = false
        event.isAllDay = false
        XCTAssertEqual(event.missingFieldDescription, "Set event timing.")
    }

    func testMissingFieldDescription_complete() {
        let event = PersistedEvent()
        event.hasExplicitDate = true
        event.hasExplicitTime = true
        XCTAssertEqual(event.missingFieldDescription, "Missing event details.")
    }

    // MARK: - eventDates JSON round-trip

    func testEventDates_roundTrip() {
        let event = PersistedEvent()
        let dates = ["2024-06-15", "2024-06-16", "2024-06-17"]
        event.eventDates = dates
        XCTAssertEqual(event.eventDates, dates)
    }

    func testEventDates_nilRaw() {
        let event = PersistedEvent()
        event.eventDatesRaw = nil
        XCTAssertEqual(event.eventDates, [])
    }

    func testEventDates_invalidJSON() {
        let event = PersistedEvent()
        event.eventDatesRaw = "not valid json"
        XCTAssertEqual(event.eventDates, [])
    }

    func testEventDates_emptyArray() {
        let event = PersistedEvent()
        event.eventDates = []
        XCTAssertEqual(event.eventDates, [])
    }

    // MARK: - isStuckProcessing

    func testIsStuckProcessing_recentProcessing() {
        let event = PersistedEvent(status: .processing)
        event.updatedAt = Date()
        XCTAssertFalse(event.isStuckProcessing)
    }

    func testIsStuckProcessing_oldProcessing() {
        let event = PersistedEvent(status: .processing)
        event.updatedAt = Date().addingTimeInterval(-400)
        XCTAssertTrue(event.isStuckProcessing)
    }

    func testIsStuckProcessing_failedNotStuck() {
        let event = PersistedEvent(status: .failed)
        event.updatedAt = Date().addingTimeInterval(-400)
        XCTAssertFalse(event.isStuckProcessing)
    }

    // MARK: - isPastStartDate / isPastEvent

    func testIsPastStartDate_futureEvent() {
        let event = PersistedEvent()
        event.startDate = Date().addingTimeInterval(86400)
        XCTAssertFalse(event.isPastStartDate)
    }

    func testIsPastStartDate_pastEvent() {
        let event = PersistedEvent()
        event.startDate = Date().addingTimeInterval(-86400)
        XCTAssertTrue(event.isPastStartDate)
    }

    func testIsPastEvent_failedAndPast() {
        let event = PersistedEvent(status: .failed)
        event.startDate = Date().addingTimeInterval(-86400)
        XCTAssertTrue(event.isPastEvent)
    }

    func testIsPastEvent_readyAndPast() {
        let event = PersistedEvent(status: .ready)
        event.startDate = Date().addingTimeInterval(-86400)
        XCTAssertFalse(event.isPastEvent)
    }

    // MARK: - applyExtraction

    func testApplyExtraction_futureEvent_becomesReady() {
        let event = PersistedEvent(status: .processing)
        let details = EventDetails(
            title: "Concert",
            startDate: Date().addingTimeInterval(86400),
            endDate: Date().addingTimeInterval(86400 + 7200),
            venue: "Hall",
            hasExplicitDate: true,
            hasExplicitTime: true
        )

        event.applyExtraction(details)

        XCTAssertEqual(event.status, .ready)
        XCTAssertEqual(event.title, "Concert")
        XCTAssertEqual(event.venue, "Hall")
        XCTAssertNotNil(event.googleCalendarURL)
    }

    func testApplyExtraction_missingDate_becomesFailed() {
        let event = PersistedEvent(status: .processing)
        let details = EventDetails(
            title: "TBD Event",
            startDate: Date().addingTimeInterval(86400),
            endDate: Date().addingTimeInterval(86400 + 7200),
            hasExplicitDate: false,
            hasExplicitTime: true
        )

        event.applyExtraction(details)

        XCTAssertEqual(event.status, .failed)
        XCTAssertEqual(event.errorMessage, "Please enter the date.")
    }

    func testApplyExtraction_missingTime_becomesFailed() {
        let event = PersistedEvent(status: .processing)
        let details = EventDetails(
            title: "Event",
            startDate: Date().addingTimeInterval(86400),
            endDate: Date().addingTimeInterval(86400 + 7200),
            hasExplicitDate: true,
            hasExplicitTime: false
        )

        event.applyExtraction(details)

        XCTAssertEqual(event.status, .failed)
        XCTAssertEqual(event.errorMessage, "Set event timing.")
    }

    func testApplyExtraction_pastEvent_becomesFailed() {
        let event = PersistedEvent(status: .processing)
        let details = EventDetails(
            title: "Past Concert",
            startDate: Date().addingTimeInterval(-86400),
            endDate: Date().addingTimeInterval(-86400 + 7200),
            hasExplicitDate: true,
            hasExplicitTime: true
        )

        event.applyExtraction(details)

        XCTAssertEqual(event.status, .failed)
        XCTAssertTrue(event.errorMessage?.contains("past") ?? false)
    }

    func testApplyExtraction_tokenUsage() {
        let event = PersistedEvent(status: .processing)
        let details = EventDetails(
            title: "Event",
            startDate: Date().addingTimeInterval(86400),
            endDate: Date().addingTimeInterval(86400 + 7200),
            hasExplicitDate: true,
            hasExplicitTime: true
        )

        let usage = ClaudeResponse.Usage(inputTokens: 1500, outputTokens: 300)
        event.applyExtraction(details, usage: usage)

        XCTAssertEqual(event.inputTokens, 1500)
        XCTAssertEqual(event.outputTokens, 300)
    }

    func testApplyExtraction_categoryAndCity() {
        let event = PersistedEvent(status: .processing)
        let details = EventDetails(
            title: "Art Show",
            startDate: Date().addingTimeInterval(86400),
            endDate: Date().addingTimeInterval(86400 + 7200),
            hasExplicitDate: true,
            hasExplicitTime: true,
            category: "arts",
            city: "Paris"
        )

        event.applyExtraction(details)

        XCTAssertEqual(event.category, "arts")
        XCTAssertEqual(event.city, "Paris")
    }

    // MARK: - toEventDetails round-trip

    func testToEventDetails_preservesProperties() {
        let event = PersistedEvent(
            title: "Show",
            venue: "Club",
            address: "456 Oak Ave",
            eventDescription: "A great show",
            timezone: "US/Eastern",
            isAllDay: false
        )
        event.eventDates = ["2024-06-15"]
        event.category = "music"
        event.city = "NYC"

        let details = event.toEventDetails()

        XCTAssertEqual(details.title, "Show")
        XCTAssertEqual(details.venue, "Club")
        XCTAssertEqual(details.address, "456 Oak Ave")
        XCTAssertEqual(details.eventDescription, "A great show")
        XCTAssertEqual(details.timezone, "US/Eastern")
        XCTAssertFalse(details.isAllDay)
        XCTAssertEqual(details.eventDates, ["2024-06-15"])
        XCTAssertEqual(details.category, "music")
        XCTAssertEqual(details.city, "NYC")
    }

    // MARK: - Status enum

    func testEventStatus_rawValues() {
        let event = PersistedEvent(status: .processing)
        XCTAssertEqual(event.statusRaw, "processing")

        event.status = .ready
        XCTAssertEqual(event.statusRaw, "ready")

        event.status = .failed
        XCTAssertEqual(event.statusRaw, "failed")

        event.status = .added
        XCTAssertEqual(event.statusRaw, "added")

        event.status = .dismissed
        XCTAssertEqual(event.statusRaw, "dismissed")
    }

    // MARK: - DigestStatus

    func testDigestStatus_defaultIsNotQueued() {
        let event = PersistedEvent()
        XCTAssertEqual(event.digestStatus, .notQueued)
    }

    func testDigestStatus_sentSyncsSentToDigest() {
        let event = PersistedEvent()
        event.digestStatus = .sent
        XCTAssertTrue(event.sentToDigest)

        event.digestStatus = .queued
        XCTAssertFalse(event.sentToDigest)
    }
}
