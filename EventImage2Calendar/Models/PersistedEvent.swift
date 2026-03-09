import Foundation
import SwiftData

enum EventStatus: String, Codable {
    case processing
    case failed
    case ready
    case added
    case dismissed
}

@Model
final class PersistedEvent {
    var id: UUID
    var title: String
    var startDate: Date
    var endDate: Date
    var venue: String
    var address: String
    var eventDescription: String
    var timezone: String?
    var statusRaw: String
    var createdAt: Date
    var updatedAt: Date

    @Attribute(.externalStorage) var imageData: Data?

    var errorMessage: String?
    var retryCount: Int
    var sentToDigest: Bool
    var googleCalendarURL: String?
    var isAllDay: Bool
    var eventDatesRaw: String?

    static let maxRetryCount = 5
    static let stuckProcessingTimeout: TimeInterval = 300

    var status: EventStatus {
        get { EventStatus(rawValue: statusRaw) ?? .processing }
        set { statusRaw = newValue.rawValue }
    }

    var canRetry: Bool {
        retryCount < Self.maxRetryCount
    }

    var isStuckProcessing: Bool {
        status == .processing && Date().timeIntervalSince(updatedAt) > Self.stuckProcessingTimeout
    }

    var hasRetryableError: Bool {
        guard let message = errorMessage else { return false }
        if message.hasPrefix("Network error") { return true }
        if message.contains("Server error") { return true }
        if message.contains("Too many requests") { return true }
        return false
    }

    var eventDates: [String] {
        get {
            guard let raw = eventDatesRaw,
                  let data = raw.data(using: .utf8),
                  let dates = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return dates
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                eventDatesRaw = String(data: data, encoding: .utf8)
            }
        }
    }

    init(
        title: String = "",
        startDate: Date = Date(),
        endDate: Date = Date().addingTimeInterval(7200),
        venue: String = "",
        address: String = "",
        eventDescription: String = "",
        timezone: String? = nil,
        status: EventStatus = .processing,
        imageData: Data? = nil,
        isAllDay: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.venue = venue
        self.address = address
        self.eventDescription = eventDescription
        self.timezone = timezone
        self.statusRaw = status.rawValue
        self.createdAt = Date()
        self.updatedAt = Date()
        self.imageData = imageData
        self.errorMessage = nil
        self.retryCount = 0
        self.sentToDigest = false
        self.googleCalendarURL = nil
        self.isAllDay = isAllDay
        self.eventDatesRaw = nil
    }

    func applyExtraction(_ details: EventDetails) {
        self.title = details.title
        self.startDate = details.startDate
        self.endDate = details.endDate
        self.venue = details.venue
        self.address = details.address
        self.eventDescription = details.eventDescription
        self.timezone = details.timezone
        self.isAllDay = details.isAllDay
        self.eventDates = details.eventDates
        self.status = .ready
        self.updatedAt = Date()
        self.googleCalendarURL = CalendarService.googleCalendarURL(for: details)?.absoluteString
    }

    func toEventDetails() -> EventDetails {
        EventDetails(
            title: title,
            startDate: startDate,
            endDate: endDate,
            venue: venue,
            address: address,
            eventDescription: eventDescription,
            timezone: timezone,
            isAllDay: isAllDay,
            eventDates: eventDates
        )
    }
}
