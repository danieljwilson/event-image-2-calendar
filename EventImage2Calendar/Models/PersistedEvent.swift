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

    var status: EventStatus {
        get { EventStatus(rawValue: statusRaw) ?? .processing }
        set { statusRaw = newValue.rawValue }
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
        imageData: Data? = nil
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
    }

    func applyExtraction(_ details: EventDetails) {
        self.title = details.title
        self.startDate = details.startDate
        self.endDate = details.endDate
        self.venue = details.venue
        self.address = details.address
        self.eventDescription = details.eventDescription
        self.timezone = details.timezone
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
            timezone: timezone
        )
    }
}
