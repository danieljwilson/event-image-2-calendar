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
            Self.saveContext(context, label: "processImage-error")
            return
        }

        let event = PersistedEvent(status: .processing, imageData: imageData)
        context.insert(event)
        SharedContainerService.writeDebugLog("Inserted processing event \(event.id)")
        Self.saveContext(context, label: "processImage")

        performExtraction(
            eventID: event.id,
            imageData: imageData,
            sourceURL: nil,
            sourceText: nil,
            context: context,
            taskName: "EventExtraction"
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
        Self.saveContext(context, label: "retryEvent")

        performExtraction(
            eventID: event.id,
            imageData: event.imageData,
            sourceURL: event.sourceURL,
            sourceText: event.sourceText,
            context: context,
            taskName: "EventRetry"
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
            Self.saveContext(context, label: "sharedImage")

            performExtraction(
                eventID: event.id,
                imageData: imageData,
                sourceURL: share.sourceURL,
                sourceText: share.sourceText,
                context: context,
                taskName: "SharedImageExtraction"
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
            Self.saveContext(context, label: "sharedURL")

            performExtraction(
                eventID: event.id,
                imageData: nil,
                sourceURL: urlString,
                sourceText: share.sourceText,
                context: context,
                taskName: "SharedURLExtraction"
            )

        case .text:
            guard let text = share.sourceText else { return }
            let event = PersistedEvent(
                eventDescription: "Shared text: \(String(text.prefix(200)))",
                status: .processing
            )
            event.sourceText = text
            context.insert(event)
            Self.saveContext(context, label: "sharedText")

            performExtraction(
                eventID: event.id,
                imageData: nil,
                sourceURL: nil,
                sourceText: text,
                context: context,
                taskName: "SharedTextExtraction"
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
        taskName: String
    ) {
        let location = locationService.currentLocation
        let language = UserDefaults.standard.string(forKey: "extractionLanguage") ?? "English"

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
                                imageData: imageData, location: location, language: language
                            )
                        } catch let imageError where sourceURL != nil && Self.shouldFallbackToURL(imageError) {
                            SharedContainerService.writeDebugLog("Extraction: image failed (\(imageError)), falling back to URL extraction from \(sourceURL!)")
                            let details = try await Self.extractFromURL(
                                sourceURL!, sourceText: sourceText, location: location, language: language
                            )
                            allDetails = [details]
                        }
                    } else if let sourceURL {
                        SharedContainerService.writeDebugLog("Extraction: URL path for \(sourceURL)")
                        let details = try await Self.extractFromURL(
                            sourceURL, sourceText: sourceText, location: location, language: language
                        )
                        allDetails = [details]
                    } else if let sourceText, !sourceText.isEmpty {
                        SharedContainerService.writeDebugLog("Extraction: text-only path (\(sourceText.count) chars)")
                        let details = try await ClaudeAPIService.extractEventFromText(
                            text: sourceText, sourceURL: nil, location: location, language: language
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
                        do {
                            guard let persisted = try context.fetch(descriptor).first else {
                                SharedContainerService.writeDebugLog("SwiftData: no event matched \(eventID)")
                                UIApplication.shared.endBackgroundTask(bgTaskID)
                                return
                            }

                            Self.applyAndFinalize(finalDetails[0], to: persisted)

                            var allEvents = [persisted]
                            for i in 1..<finalDetails.count {
                                let extra = PersistedEvent(status: .processing, imageData: imageData)
                                extra.sourceURL = sourceURL
                                extra.sourceText = sourceText
                                context.insert(extra)
                                Self.applyAndFinalize(finalDetails[i], to: extra)
                                allEvents.append(extra)
                            }

                            Self.saveContext(context, label: "extraction-success")

                            for event in allEvents where event.status == .ready {
                                DigestService.queueEvent(event, context: context)
                            }
                            DigestService.flushPendingEvents(context: context)
                        } catch {
                            SharedContainerService.writeDebugLog("SwiftData fetch error: \(error)")
                        }
                        UIApplication.shared.endBackgroundTask(bgTaskID)
                    }
                    return

                } catch {
                    lastError = error
                    SharedContainerService.writeDebugLog("Extraction attempt \(attempt + 1) failed: \(error)")
                    let isRetryable = (error as? ClaudeAPIError)?.isRetryable ?? (error is URLError)
                    if !isRetryable || attempt == maxAutoRetries - 1 { break }
                    let delay = baseDelay * UInt64(1 << attempt)
                    try? await Task.sleep(nanoseconds: delay)
                }
            }

            let baseMessage: String
            if let claudeError = lastError as? ClaudeAPIError {
                baseMessage = claudeError.userFacingMessage
            } else {
                baseMessage = lastError?.localizedDescription ?? "Unknown error"
            }
            let errorMessage = Self.sourceAwareErrorMessage(
                baseMessage: baseMessage,
                imageData: imageData,
                sourceURL: sourceURL,
                sourceText: sourceText
            )

            SharedContainerService.writeDebugLog("Extraction failed after retries: \(errorMessage)")

            await MainActor.run {
                let descriptor = FetchDescriptor<PersistedEvent>(
                    predicate: #Predicate { $0.id == eventID }
                )
                do {
                    if let persisted = try context.fetch(descriptor).first {
                        persisted.status = .failed
                        persisted.errorMessage = errorMessage
                        persisted.updatedAt = Date()
                        Self.saveContext(context, label: "extraction-failure")
                    }
                } catch {
                    SharedContainerService.writeDebugLog("SwiftData fetch error (failure path): \(error)")
                }
                UIApplication.shared.endBackgroundTask(bgTaskID)
            }
        }
    }

    /// Apply extraction results to a PersistedEvent and add a search link when needed.
    private static func applyAndFinalize(_ details: EventDetails, to persisted: PersistedEvent) {
        persisted.applyExtraction(details)

        if !persisted.eventDescription.contains("http") {
            let link = WebSearchService.googleSearchURL(
                title: persisted.title,
                venue: persisted.venue,
                address: persisted.address
            )
            persisted.eventDescription += "\n\n\(link)"
        }
    }

    // MARK: - Recovery

    @MainActor
    func recoverStuckEvents(context: ModelContext) {
        let descriptor = FetchDescriptor<PersistedEvent>(
            predicate: #Predicate { $0.statusRaw == "processing" }
        )
        let events: [PersistedEvent]
        do {
            events = try context.fetch(descriptor)
        } catch {
            SharedContainerService.writeDebugLog("recoverStuckEvents fetch error: \(error)")
            return
        }
        var changed = false
        for event in events where event.isStuckProcessing {
            event.status = .failed
            event.errorMessage = "Processing timed out. Tap retry to try again."
            event.updatedAt = Date()
            changed = true
        }
        if changed { Self.saveContext(context, label: "recoverStuck") }
    }

    @MainActor
    func autoRetryEligibleEvents(context: ModelContext) {
        let descriptor = FetchDescriptor<PersistedEvent>(
            predicate: #Predicate { $0.statusRaw == "failed" }
        )
        let events: [PersistedEvent]
        do {
            events = try context.fetch(descriptor)
        } catch {
            SharedContainerService.writeDebugLog("autoRetryEligibleEvents fetch error: \(error)")
            return
        }
        for event in events where event.canRetry && event.hasRetryableError {
            retryEvent(event, context: context)
        }
    }

    // MARK: - Helpers

    private static func saveContext(_ context: ModelContext, label: String) {
        do {
            try context.save()
            SharedContainerService.writeDebugLog("SwiftData save OK (\(label))")
        } catch {
            SharedContainerService.writeDebugLog("SwiftData save FAILED (\(label)): \(error)")
        }
    }

    /// Whether an image extraction error should trigger fallback to URL extraction.
    /// Only extraction-level failures (content not parseable) warrant fallback.
    /// Auth, network, quota, and server errors do not — they'd fail on the URL path too.
    private static func shouldFallbackToURL(_ error: Error) -> Bool {
        guard let claudeError = error as? ClaudeAPIError else { return false }
        switch claudeError {
        case .noEventFound, .decodingFailed, .invalidResponse:
            return true
        case .authFailed, .apiError:
            return false
        }
    }

    /// Source-aware error message for extraction failures.
    private static func sourceAwareErrorMessage(
        baseMessage: String,
        imageData: Data?,
        sourceURL: String?,
        sourceText: String?
    ) -> String {
        // Only override decode/noEvent messages — pass through network/auth/quota messages unchanged
        let isExtractionFailure = baseMessage.contains("Could not read event details")
            || baseMessage.contains("No event details found")
        guard isExtractionFailure else { return baseMessage }

        if imageData != nil && sourceURL != nil {
            return "Could not read event details from this share."
        } else if imageData != nil {
            return baseMessage // pure image — keep original "image" wording
        } else if sourceURL != nil {
            return "Could not read event details from this link."
        } else if sourceText != nil {
            return "Could not read event details from this text."
        }
        return baseMessage
    }

    // MARK: - URL extraction (Claude uses web search to fetch and extract)

    /// Minimum character count for sourceText (after URL stripping) to be treated as page content.
    private static let substantiveTextThreshold = 50

    /// Send URL to Claude with web search — it handles page fetching internally.
    private static func extractFromURL(
        _ urlString: String,
        sourceText: String?,
        location: CLLocationCoordinate2D?,
        language: String = "English"
    ) async throws -> EventDetails {
        // Check if sourceText is substantive (not just a URL or short share boilerplate)
        if let sourceText, !sourceText.isEmpty {
            let strippedText = Self.stripURLs(from: sourceText).trimmingCharacters(in: .whitespacesAndNewlines)
            SharedContainerService.writeDebugLog(
                "Extraction: sourceText \(sourceText.count) chars, stripped \(strippedText.count) chars"
            )

            if strippedText.count >= substantiveTextThreshold {
                SharedContainerService.writeDebugLog("Extraction: text path with source URL (substantive text)")
                return try await ClaudeAPIService.extractEventFromText(
                    text: sourceText, sourceURL: urlString, location: location, language: language
                )
            } else {
                SharedContainerService.writeDebugLog(
                    "Extraction: skipping text path — stripped text below \(substantiveTextThreshold) char threshold"
                )
            }
        }

        // Let Claude web-search the URL directly
        SharedContainerService.writeDebugLog("Extraction: URL path with web search for \(urlString.prefix(80))")
        return try await ClaudeAPIService.extractEventFromURL(
            urlString: urlString, location: location, language: language
        )
    }

    /// Strip URLs from text to check if the remainder is substantive content.
    private static func stripURLs(from text: String) -> String {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}
