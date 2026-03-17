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
            sourceText: nil,
            context: context,
            taskName: "EventExtraction",
            sendToDigest: true
        )
    }

    @MainActor
    func retryEvent(_ event: PersistedEvent, context: ModelContext) {
        guard event.canRetry else { return }
        // URL-only and text-only events won't have imageData — that's OK
        guard event.imageData != nil || event.sourceURL != nil || event.sourceText != nil else { return }

        event.status = .processing
        event.retryCount += 1
        event.errorMessage = nil
        event.updatedAt = Date()
        try? context.save()

        performExtraction(
            eventID: event.id,
            imageData: event.imageData,
            sourceURL: event.sourceURL,
            sourceText: event.sourceText,
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
            event.sourceURL = share.sourceURL
            context.insert(event)
            try? context.save()

            performExtraction(
                eventID: event.id,
                imageData: imageData,
                sourceURL: share.sourceURL,
                sourceText: share.sourceText,
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
            event.sourceURL = urlString
            event.sourceText = share.sourceText
            context.insert(event)
            try? context.save()

            performExtraction(
                eventID: event.id,
                imageData: nil,
                sourceURL: urlString,
                sourceText: share.sourceText,
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
            event.sourceText = text
            context.insert(event)
            try? context.save()

            performExtraction(
                eventID: event.id,
                imageData: nil,
                sourceURL: nil,
                sourceText: text,
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
        sourceText: String?,
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
                    var allDetails: [EventDetails]

                    if let imageData {
                        SharedContainerService.writeDebugLog("Extraction: image path (\(imageData.count) bytes)")
                        do {
                            allDetails = try await ClaudeAPIService.extractEvents(
                                imageData: imageData, location: location
                            )
                        } catch ClaudeAPIError.noEventFound where sourceURL != nil {
                            SharedContainerService.writeDebugLog("Extraction: image found nothing, trying page content from \(sourceURL!)")
                            let details = try await Self.extractFromURL(
                                sourceURL!, sourceText: sourceText, location: location
                            )
                            allDetails = [details]
                        }
                    } else if let sourceURL {
                        SharedContainerService.writeDebugLog("Extraction: URL path for \(sourceURL)")
                        let details = try await Self.extractFromURL(
                            sourceURL, sourceText: sourceText, location: location
                        )
                        allDetails = [details]
                    } else if let sourceText, !sourceText.isEmpty {
                        SharedContainerService.writeDebugLog("Extraction: text-only path (\(sourceText.count) chars)")
                        let details = try await ClaudeAPIService.extractEventFromText(
                            text: sourceText, sourceURL: nil, location: location
                        )
                        allDetails = [details]
                    } else {
                        throw ClaudeAPIError.invalidResponse
                    }

                    SharedContainerService.writeDebugLog("Extraction: found \(allDetails.count) event(s)")

                    let finalDetails = allDetails
                    await MainActor.run {
                        let descriptor = FetchDescriptor<PersistedEvent>(
                            predicate: #Predicate { $0.id == eventID }
                        )
                        guard let persisted = try? context.fetch(descriptor).first else {
                            UIApplication.shared.endBackgroundTask(bgTaskID)
                            return
                        }

                        // Apply first event to the original PersistedEvent
                        Self.applyAndFinalize(finalDetails[0], to: persisted, sendToDigest: sendToDigest)

                        // Create additional PersistedEvents for remaining events
                        for i in 1..<finalDetails.count {
                            let extra = PersistedEvent(status: .processing, imageData: imageData)
                            extra.sourceURL = sourceURL
                            context.insert(extra)
                            Self.applyAndFinalize(finalDetails[i], to: extra, sendToDigest: sendToDigest)
                        }

                        try? context.save()
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

    /// Apply extraction results to a PersistedEvent and send to digest if needed.
    private static func applyAndFinalize(_ details: EventDetails, to persisted: PersistedEvent, sendToDigest: Bool) {
        persisted.applyExtraction(details)

        if !persisted.eventDescription.contains("http") {
            let link = WebSearchService.googleSearchURL(
                title: persisted.title,
                venue: persisted.venue,
                address: persisted.address
            )
            persisted.eventDescription += "\n\n\(link)"
        }

        if sendToDigest {
            let digestData = DigestService.EventPayload(from: persisted)
            Task.detached {
                await DigestService.sendToDigest(digestData)
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

    // MARK: - URL extraction (Claude uses web search to fetch and extract)

    /// Send URL to Claude with web search — it handles page fetching internally.
    private static func extractFromURL(
        _ urlString: String,
        sourceText: String?,
        location: CLLocationCoordinate2D?
    ) async throws -> EventDetails {
        // If we have sourceText from the share extension, try text extraction first
        if let sourceText, !sourceText.isEmpty {
            SharedContainerService.writeDebugLog("Extraction: text path with source URL (\(sourceText.count) chars)")
            return try await ClaudeAPIService.extractEventFromText(
                text: sourceText, sourceURL: urlString, location: location
            )
        }

        // Let Claude web-search the URL directly
        SharedContainerService.writeDebugLog("Extraction: URL path with web search for \(urlString.prefix(80))")
        return try await ClaudeAPIService.extractEventFromURL(
            urlString: urlString, location: location
        )
    }
}
