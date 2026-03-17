import Foundation
import SwiftData

enum EventStatus: String, Codable {
    case processing
    case failed
    case ready
    case added
    case dismissed
}

enum DigestStatus: String, Codable {
    case notQueued
    case queued
    case sending
    case sent
    case failed
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
    var digestStatusRaw: String = "notQueued"
    var digestQueuedAt: Date?
    var digestLastAttemptAt: Date?
    var digestSentAt: Date?
    var digestLastError: String?
    var googleCalendarURL: String?
    var isAllDay: Bool
    var eventDatesRaw: String?
    var sourceURL: String?
    var sourceText: String?
    var hasExplicitDate: Bool = true
    var hasExplicitTime: Bool = true

    static let maxRetryCount = 5
    static let stuckProcessingTimeout: TimeInterval = 300
    static let digestSendTimeout: TimeInterval = 300
    static let digestRetryDelay: TimeInterval = 300

    var status: EventStatus {
        get { EventStatus(rawValue: statusRaw) ?? .processing }
        set { statusRaw = newValue.rawValue }
    }

    var digestStatus: DigestStatus {
        get {
            if let status = DigestStatus(rawValue: digestStatusRaw) {
                return status
            }
            return sentToDigest ? .sent : .notQueued
        }
        set {
            digestStatusRaw = newValue.rawValue
            sentToDigest = newValue == .sent
        }
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

    var isDigestSendStuck: Bool {
        guard digestStatus == .sending,
              let lastAttempt = digestLastAttemptAt else {
            return false
        }
        return Date().timeIntervalSince(lastAttempt) > Self.digestSendTimeout
    }

    var shouldRetryDigestSend: Bool {
        switch digestStatus {
        case .queued:
            return true
        case .failed:
            guard let lastAttempt = digestLastAttemptAt else { return true }
            return Date().timeIntervalSince(lastAttempt) > Self.digestRetryDelay
        case .sending:
            return isDigestSendStuck
        case .notQueued, .sent:
            return false
        }
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
        self.digestStatusRaw = DigestStatus.notQueued.rawValue
        self.digestQueuedAt = nil
        self.digestLastAttemptAt = nil
        self.digestSentAt = nil
        self.digestLastError = nil
        self.googleCalendarURL = nil
        self.isAllDay = isAllDay
        self.eventDatesRaw = nil
        self.sourceURL = nil
        self.sourceText = nil
        self.hasExplicitDate = true
        self.hasExplicitTime = true
    }

    var needsDateCorrection: Bool {
        !hasExplicitDate || !hasExplicitTime
    }

    var missingFieldDescription: String {
        if !hasExplicitDate && !hasExplicitTime {
            return "Please enter the date and time."
        } else if !hasExplicitDate {
            return "Please enter the date."
        } else {
            return "Please enter the time."
        }
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
        self.hasExplicitDate = details.hasExplicitDate
        self.hasExplicitTime = details.hasExplicitTime
        self.updatedAt = Date()
        self.googleCalendarURL = CalendarService.googleCalendarURL(for: details)?.absoluteString

        if details.hasExplicitDate && details.hasExplicitTime {
            self.status = .ready
        } else {
            self.status = .failed
            self.errorMessage = missingFieldDescription
        }
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
