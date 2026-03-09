import UIKit
import SwiftData
import CoreLocation

@Observable
class BackgroundEventProcessor {
    let locationService = LocationService()

    @MainActor
    func processImage(_ image: UIImage, context: ModelContext) {
        let imageData: Data
        do {
            imageData = try image.resizedForAPIValidated()
        } catch {
            let event = PersistedEvent(status: .failed, imageData: image.resizedForAPI())
            event.errorMessage = error.localizedDescription
            context.insert(event)
            try? context.save()
            return
        }

        let event = PersistedEvent(status: .processing, imageData: imageData)
        context.insert(event)
        try? context.save()

        performExtraction(
            eventID: event.id,
            imageData: imageData,
            sourceURL: nil,
            context: context,
            taskName: "EventExtraction",
            sendToDigest: true
        )
    }

    @MainActor
    func retryEvent(_ event: PersistedEvent, context: ModelContext) {
        guard event.canRetry else { return }
        guard let imageData = event.imageData else { return }

        event.status = .processing
        event.retryCount += 1
        event.errorMessage = nil
        event.updatedAt = Date()
        try? context.save()

        performExtraction(
            eventID: event.id,
            imageData: imageData,
            sourceURL: nil,
            context: context,
            taskName: "EventRetry",
            sendToDigest: false
        )
    }

    @MainActor
    func processSharedItem(_ share: PendingShare, imageData: Data?, context: ModelContext) {
        switch share.sourceType {
        case .image:
            guard let imageData else { return }
            let event = PersistedEvent(status: .processing, imageData: imageData)
            context.insert(event)
            try? context.save()

            performExtraction(
                eventID: event.id,
                imageData: imageData,
                sourceURL: nil,
                context: context,
                taskName: "SharedImageExtraction",
                sendToDigest: true
            )

        case .url:
            guard let urlString = share.sourceURL else { return }
            let event = PersistedEvent(
                eventDescription: "Source: \(urlString)",
                status: .processing
            )
            context.insert(event)
            try? context.save()

            performExtraction(
                eventID: event.id,
                imageData: nil,
                sourceURL: urlString,
                context: context,
                taskName: "SharedURLExtraction",
                sendToDigest: true
            )

        case .text:
            guard let text = share.sourceText else { return }
            let event = PersistedEvent(
                eventDescription: "Shared text: \(String(text.prefix(200)))",
                status: .processing
            )
            context.insert(event)
            try? context.save()

            performExtraction(
                eventID: event.id,
                imageData: nil,
                sourceURL: nil,
                context: context,
                taskName: "SharedTextExtraction",
                sendToDigest: true
            )
        }
    }

    // MARK: - Shared extraction logic

    @MainActor
    private func performExtraction(
        eventID: UUID,
        imageData: Data?,
        sourceURL: String?,
        context: ModelContext,
        taskName: String,
        sendToDigest: Bool
    ) {
        let location = locationService.currentLocation

        var bgTaskID: UIBackgroundTaskIdentifier = .invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: taskName) {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }

        Task.detached {
            let maxAutoRetries = 3
            let baseDelay: UInt64 = 2_000_000_000
            var lastError: Error?

            for attempt in 0..<maxAutoRetries {
                do {
                    let details: EventDetails
                    if let imageData {
                        details = try await ClaudeAPIService.extractEvent(
                            imageData: imageData, location: location
                        )
                    } else if let sourceURL {
                        details = try await ClaudeAPIService.extractEventFromURL(
                            urlString: sourceURL, location: location
                        )
                    } else {
                        throw ClaudeAPIError.invalidResponse
                    }

                    await MainActor.run {
                        let descriptor = FetchDescriptor<PersistedEvent>(
                            predicate: #Predicate { $0.id == eventID }
                        )
                        if let persisted = try? context.fetch(descriptor).first {
                            persisted.applyExtraction(details)

                            if !persisted.eventDescription.contains("http") {
                                let link = WebSearchService.googleSearchURL(
                                    title: persisted.title,
                                    venue: persisted.venue,
                                    address: persisted.address
                                )
                                persisted.eventDescription += "\n\n\(link)"
                            }

                            try? context.save()

                            if sendToDigest {
                                let digestData = DigestService.EventPayload(from: persisted)
                                Task.detached {
                                    await DigestService.sendToDigest(digestData)
                                }
                            }
                        }
                        UIApplication.shared.endBackgroundTask(bgTaskID)
                    }
                    return

                } catch {
                    lastError = error
                    let isRetryable = (error as? ClaudeAPIError)?.isRetryable ?? (error is URLError)
                    if !isRetryable || attempt == maxAutoRetries - 1 { break }
                    let delay = baseDelay * UInt64(1 << attempt)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }

            let errorMessage: String
            if let claudeError = lastError as? ClaudeAPIError {
                errorMessage = claudeError.userFacingMessage
            } else {
                errorMessage = lastError?.localizedDescription ?? "Unknown error"
            }

            await MainActor.run {
                let descriptor = FetchDescriptor<PersistedEvent>(
                    predicate: #Predicate { $0.id == eventID }
                )
                if let persisted = try? context.fetch(descriptor).first {
                    persisted.status = .failed
                    persisted.errorMessage = errorMessage
                    persisted.updatedAt = Date()
                    try? context.save()
                }
                UIApplication.shared.endBackgroundTask(bgTaskID)
            }
        }
    }

    // MARK: - Recovery

    @MainActor
    func recoverStuckEvents(context: ModelContext) {
        let descriptor = FetchDescriptor<PersistedEvent>(
            predicate: #Predicate { $0.statusRaw == "processing" }
        )
        guard let events = try? context.fetch(descriptor) else { return }
        var changed = false
        for event in events where event.isStuckProcessing {
            event.status = .failed
            event.errorMessage = "Processing timed out. Tap retry to try again."
            event.updatedAt = Date()
            changed = true
        }
        if changed { try? context.save() }
    }

    @MainActor
    func autoRetryEligibleEvents(context: ModelContext) {
        let descriptor = FetchDescriptor<PersistedEvent>(
            predicate: #Predicate { $0.statusRaw == "failed" }
        )
        guard let events = try? context.fetch(descriptor) else { return }
        for event in events where event.canRetry && event.hasRetryableError {
            retryEvent(event, context: context)
        }
    }
}
