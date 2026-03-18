import Foundation
import SwiftData

enum DigestService {
    private static let workerURL = URL(string: "https://event-digest-worker.daniel-j-wilson-587.workers.dev/events")!
    private static let flushCoordinator = DigestFlushCoordinator()

    struct EventPayload: Encodable, Sendable {
        let id: String
        let title: String
        let startDate: String
        let endDate: String
        let venue: String
        let address: String
        let description: String
        let timezone: String?
        let isAllDay: Bool
        let googleCalendarURL: String
        let createdAt: String

        init(from event: PersistedEvent) {
            let formatter = ISO8601DateFormatter()
            self.id = event.id.uuidString
            self.title = event.title
            self.startDate = formatter.string(from: event.startDate)
            self.endDate = formatter.string(from: event.endDate)
            self.venue = event.venue
            self.address = event.address
            self.description = event.eventDescription
            self.timezone = event.timezone
            self.isAllDay = event.isAllDay
            self.googleCalendarURL = event.googleCalendarURL ?? ""
            self.createdAt = formatter.string(from: event.createdAt)
        }
    }

    @MainActor
    static func queueEvent(_ event: PersistedEvent, context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "digestEnabled") else { return }
        guard event.digestStatus == .notQueued else { return }

        event.digestStatus = .queued
        event.digestQueuedAt = Date()
        event.digestLastError = nil

        saveContext(context, label: "digest-queue")
        SharedContainerService.writeDebugLog("Digest: queued event \(event.id)")
    }

    @MainActor
    static func dequeueEvent(_ event: PersistedEvent, context: ModelContext) {
        let previousStatus = event.digestStatus

        if previousStatus == .sent || previousStatus == .sending {
            let eventID = event.id.uuidString
            Task {
                await deleteFromWorker(eventID: eventID)
            }
        }

        event.digestStatus = .notQueued
        event.digestQueuedAt = nil
        event.digestLastError = nil

        saveContext(context, label: "digest-dequeue")
        SharedContainerService.writeDebugLog("Digest: dequeued event \(event.id) (was \(previousStatus))")
    }

    @MainActor
    static func flushPendingEvents(context: ModelContext) {
        Task {
            let shouldRun = await flushCoordinator.begin()
            guard shouldRun else { return }

            while true {
                let claimed = await MainActor.run {
                    claimPendingEvents(context: context)
                }

                if claimed.isEmpty { break }

                for item in claimed {
                    let result = await send(item.payload)
                    await MainActor.run {
                        applySendResult(result, for: item.eventID, context: context)
                    }
                }
            }

            await flushCoordinator.end()
        }
    }

    @MainActor
    private static func claimPendingEvents(context: ModelContext) -> [QueuedDigestEvent] {
        let descriptor = FetchDescriptor<PersistedEvent>()
        guard let events = try? context.fetch(descriptor) else { return [] }

        let candidates = events
            .filter { $0.shouldRetryDigestSend }
            .sorted { lhs, rhs in
                let lhsDate = lhs.digestQueuedAt ?? lhs.updatedAt
                let rhsDate = rhs.digestQueuedAt ?? rhs.updatedAt
                return lhsDate < rhsDate
            }

        guard !candidates.isEmpty else { return [] }

        let attemptDate = Date()
        let claimed = candidates.map { event -> QueuedDigestEvent in
            event.digestStatus = .sending
            event.digestLastAttemptAt = attemptDate
            event.digestLastError = nil

            return QueuedDigestEvent(
                eventID: event.id,
                payload: EventPayload(from: event)
            )
        }

        saveContext(context, label: "digest-claim")
        SharedContainerService.writeDebugLog("Digest: claimed \(claimed.count) queued event(s)")
        return claimed
    }

    @MainActor
    private static func applySendResult(
        _ result: DigestSendResult,
        for eventID: UUID,
        context: ModelContext
    ) {
        let descriptor = FetchDescriptor<PersistedEvent>(
            predicate: #Predicate { $0.id == eventID }
        )

        guard let event = try? context.fetch(descriptor).first else { return }

        switch result {
        case .sent:
            event.digestStatus = .sent
            event.digestSentAt = Date()
            event.digestLastError = nil
            SharedContainerService.writeDebugLog("Digest: sent event \(eventID)")
        case .failed(let message):
            event.digestStatus = .failed
            event.digestLastError = message
            SharedContainerService.writeDebugLog("Digest: failed event \(eventID): \(message)")
        }

        event.updatedAt = Date()
        saveContext(context, label: "digest-result")
    }

    private static func send(_ payload: EventPayload) async -> DigestSendResult {
        guard let accessToken = await WorkerAuthService.accessToken() else {
            return .failed("Worker auth unavailable")
        }

        var request = URLRequest(url: workerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(payload)
        request.timeoutInterval = 15

        do {
            SharedContainerService.writeDebugLog("Digest: sending event \(payload.id)")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failed("Invalid digest response")
            }

            guard (200...299).contains(httpResponse.statusCode) else {
                let body = String(data: data, encoding: .utf8) ?? "Unknown error"
                return .failed("HTTP \(httpResponse.statusCode): \(String(body.prefix(200)))")
            }

            return .sent
        } catch {
            return .failed("Network error: \(error.localizedDescription)")
        }
    }

    private static func deleteFromWorker(eventID: String) async {
        guard let accessToken = await WorkerAuthService.accessToken() else {
            SharedContainerService.writeDebugLog("Digest: delete skipped, no auth for \(eventID)")
            return
        }

        guard let deleteURL = URL(string: workerURL.absoluteString + "/\(eventID)") else { return }

        var request = URLRequest(url: deleteURL)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            SharedContainerService.writeDebugLog("Digest: delete \(eventID) → HTTP \(status)")
        } catch {
            SharedContainerService.writeDebugLog("Digest: delete \(eventID) failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private static func saveContext(_ context: ModelContext, label: String) {
        do {
            try context.save()
            SharedContainerService.writeDebugLog("SwiftData save OK (\(label))")
        } catch {
            SharedContainerService.writeDebugLog("SwiftData save FAILED (\(label)): \(error)")
        }
    }
}

private struct QueuedDigestEvent: Sendable {
    let eventID: UUID
    let payload: DigestService.EventPayload
}

private enum DigestSendResult: Sendable {
    case sent
    case failed(String)
}

private actor DigestFlushCoordinator {
    private var isRunning = false

    func begin() -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        return true
    }

    func end() {
        isRunning = false
    }
}
