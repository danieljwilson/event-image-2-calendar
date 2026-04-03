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
        let deviceModel = UIDevice.current.model
        let iOSVersion = UIDevice.current.systemVersion

        var bgTaskID: UIBackgroundTaskIdentifier = .invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: taskName) {
            SharedContainerService.writeDebugLog("BG TASK EXPIRED: \(taskName) for event \(eventID)")
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }

        Task.detached {
            SharedContainerService.writeDebugLog(
                "Extraction START: event=\(eventID), image=\(imageData?.count ?? 0) bytes, " +
                "url=\(sourceURL ?? "nil"), text=\(sourceText?.count ?? 0) chars, " +
                "location=\(location.map { "\($0.latitude),\($0.longitude)" } ?? "nil"), language=\(language)"
            )
            let extractionStart = CFAbsoluteTimeGetCurrent()

            let maxAutoRetries = 3
            let baseDelay: UInt64 = 2_000_000_000
            var lastError: Error?

            for attempt in 0..<maxAutoRetries {
                do {
                    var output: ExtractionOutput

                    if let imageData {
                        SharedContainerService.writeDebugLog("Extraction: image path (\(imageData.count) bytes)")
                        do {
                            output = try await ClaudeAPIService.extractEvents(
                                imageData: imageData, location: location, language: language
                            )
                        } catch let imageError where sourceURL != nil && Self.shouldFallbackToURL(imageError) {
                            SharedContainerService.writeDebugLog("Extraction: image failed (\(imageError)), falling back to URL extraction from \(sourceURL!)")
                            output = try await Self.extractFromURL(
                                sourceURL!, sourceText: sourceText, location: location, language: language
                            )
                        }
                    } else if let sourceURL {
                        SharedContainerService.writeDebugLog("Extraction: URL path for \(sourceURL)")
                        output = try await Self.extractFromURL(
                            sourceURL, sourceText: sourceText, location: location, language: language
                        )
                    } else if let sourceText, !sourceText.isEmpty {
                        SharedContainerService.writeDebugLog("Extraction: text-only path (\(sourceText.count) chars)")
                        output = try await ClaudeAPIService.extractEventFromText(
                            text: sourceText, sourceURL: nil, location: location, language: language
                        )
                    } else {
                        throw ClaudeAPIError.invalidResponse
                    }

                    let allDetails = output.events
                    let usage = output.usage
                    let elapsed = CFAbsoluteTimeGetCurrent() - extractionStart
                    SharedContainerService.writeDebugLog("Extraction: found \(allDetails.count) event(s) in \(String(format: "%.1f", elapsed))s")
                    if let usage {
                        SharedContainerService.writeDebugLog("Extraction: tokens — input: \(usage.inputTokens), output: \(usage.outputTokens)")
                    }
                    let isoFormatter = ISO8601DateFormatter()
                    for (i, detail) in allDetails.enumerated() {
                        SharedContainerService.writeDebugLog(
                            "  Event[\(i)]: \"\(detail.title)\" @ \(detail.venue), " +
                            "date=\(isoFormatter.string(from: detail.startDate)), " +
                            "dateOK=\(detail.hasExplicitDate), timeOK=\(detail.hasExplicitTime)"
                        )
                    }

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

                            // Store full usage on first event only (one API call → multiple events)
                            Self.applyAndFinalize(finalDetails[0], to: persisted, usage: usage)

                            var allEvents = [persisted]
                            for i in 1..<finalDetails.count {
                                let extra = PersistedEvent(status: .processing, imageData: imageData)
                                extra.sourceURL = sourceURL
                                extra.sourceText = sourceText
                                context.insert(extra)
                                Self.applyAndFinalize(finalDetails[i], to: extra, usage: nil)
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

            let failElapsed = CFAbsoluteTimeGetCurrent() - extractionStart
            let isRetryable = (lastError as? ClaudeAPIError)?.isRetryable ?? false
            SharedContainerService.writeDebugLog(
                "Extraction FAILED: event=\(eventID), elapsed=\(String(format: "%.1f", failElapsed))s, " +
                "retryable=\(isRetryable), " +
                "error=\(String(describing: lastError)), message=\(errorMessage)"
            )

            // Report error to Worker for remote dashboard visibility
            let errorType: String
            if let claudeError = lastError as? ClaudeAPIError {
                switch claudeError {
                case .authFailed: errorType = "authFailed"
                case .invalidResponse: errorType = "invalidResponse"
                case .apiError: errorType = "apiError"
                case .decodingFailed: errorType = "decodingFailed"
                case .noEventFound: errorType = "noEventFound"
                }
            } else if lastError is URLError {
                errorType = "urlError"
            } else {
                errorType = "unknown"
            }

            let sourceType: String
            if imageData != nil && sourceURL != nil && Self.isSocialMediaURL(sourceURL!) {
                sourceType = "social"
            } else if imageData != nil {
                sourceType = "image"
            } else if sourceURL != nil {
                sourceType = "url"
            } else {
                sourceType = "text"
            }

            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

            WorkerAuthService.reportError(WorkerAuthService.ErrorReport(
                eventId: eventID.uuidString,
                errorType: errorType,
                errorMessage: lastError?.localizedDescription ?? "Unknown error",
                sourceType: sourceType,
                imageSizeBytes: imageData?.count,
                attemptCount: maxAutoRetries,
                elapsedSeconds: failElapsed,
                isRetryable: isRetryable,
                appVersion: version,
                buildNumber: build,
                deviceModel: deviceModel,
                iOSVersion: iOSVersion
            ))

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
    private static func applyAndFinalize(_ details: EventDetails, to persisted: PersistedEvent, usage: ClaudeResponse.Usage?) {
        persisted.applyExtraction(details, usage: usage)

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

    // MARK: - Social media detection

    private static let socialMediaDomains = ["instagram.com", "facebook.com", "fb.com", "fb.me"]

    private static func isSocialMediaURL(_ urlString: String) -> Bool {
        let lowered = urlString.lowercased()
        return socialMediaDomains.contains { lowered.contains($0) }
    }

    // MARK: - Social media metadata prefetch

    private struct SocialMediaMetadata {
        var title: String?
        var description: String?
        var imageURL: String?
    }

    /// Fetch OG meta tags from a social media URL using Facebook crawler UA.
    /// Instagram/Facebook serve full OG metadata to this UA since Meta owns both.
    private static func fetchSocialMediaMetadata(from urlString: String) async -> SocialMediaMetadata? {
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("facebookexternalhit/1.1", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        var metadata = SocialMediaMetadata()
        metadata.title = extractMetaContent(from: html, property: "og:title")
        metadata.description = extractMetaContent(from: html, property: "og:description")
        metadata.imageURL = extractMetaContent(from: html, property: "og:image")
        return metadata
    }

    /// Parse an OG meta tag value from HTML.
    private static func extractMetaContent(from html: String, property: String) -> String? {
        let patterns = [
            "property=\"\(property)\"\\s+content=\"([^\"]*?)\"",
            "content=\"([^\"]*?)\"\\s+property=\"\(property)\""
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let value = String(html[range])
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }

    /// Download and downsample an OG image for vision extraction.
    private static func downloadOGImage(from urlString: String) async -> Data? {
        guard let url = URL(string: urlString) else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }
        return ImageResizer.downsample(data: data)
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

        // Social media pages are auth-walled; give actionable fallback advice
        if let url = sourceURL, isSocialMediaURL(url) {
            return "Could not find event details from this post. Try sharing the image directly, or screenshot the post."
        }

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

    /// Minimum character count for social media captions to be treated as page content.
    private static let socialMediaTextThreshold = 15

    /// Send URL to Claude with web search — it handles page fetching internally.
    private static func extractFromURL(
        _ urlString: String,
        sourceText: String?,
        location: CLLocationCoordinate2D?,
        language: String = "English"
    ) async throws -> ExtractionOutput {
        let isSocial = isSocialMediaURL(urlString)
        let threshold = isSocial ? socialMediaTextThreshold : substantiveTextThreshold

        // Check if sourceText is substantive (not just a URL or short share boilerplate)
        if let sourceText, !sourceText.isEmpty {
            let strippedText = Self.stripURLs(from: sourceText).trimmingCharacters(in: .whitespacesAndNewlines)
            SharedContainerService.writeDebugLog(
                "Extraction: sourceText \(sourceText.count) chars, stripped \(strippedText.count) chars (threshold: \(threshold), social: \(isSocial))"
            )

            if strippedText.count >= threshold {
                SharedContainerService.writeDebugLog("Extraction: text path with source URL (substantive text)")
                return try await ClaudeAPIService.extractEventFromText(
                    text: sourceText, sourceURL: urlString, location: location, language: language
                )
            } else {
                SharedContainerService.writeDebugLog(
                    "Extraction: skipping text path — stripped text below \(threshold) char threshold"
                )
            }
        }

        // Social media pages are auth-walled — prefetch OG metadata for context
        if isSocial {
            SharedContainerService.writeDebugLog("Extraction: fetching OG metadata for \(urlString.prefix(80))")
            if let metadata = await fetchSocialMediaMetadata(from: urlString) {
                SharedContainerService.writeDebugLog(
                    "OG metadata: title=\(metadata.title?.prefix(100) ?? "nil"), " +
                    "desc=\(metadata.description?.prefix(100) ?? "nil"), " +
                    "image=\(metadata.imageURL != nil)"
                )

                // Best path: OG image → vision extraction (most powerful)
                if let ogImageURL = metadata.imageURL,
                   let imageData = await downloadOGImage(from: ogImageURL) {
                    SharedContainerService.writeDebugLog("Extraction: OG image (\(imageData.count) bytes), using vision path")
                    var context = ""
                    if let title = metadata.title { context += "Post title: \(title)\n" }
                    if let desc = metadata.description { context += "Post caption: \(desc)\n" }
                    context += "Source: \(urlString)"

                    let output = try await ClaudeAPIService.extractEvents(
                        imageData: imageData, location: location,
                        additionalContext: context, language: language
                    )
                    guard !output.events.isEmpty else { throw ClaudeAPIError.noEventFound }
                    return output
                }

                // Fallback: OG text only → text extraction
                let ogText = [metadata.title, metadata.description].compactMap { $0 }.joined(separator: "\n")
                if !ogText.isEmpty {
                    SharedContainerService.writeDebugLog("Extraction: OG text only (\(ogText.count) chars)")
                    return try await ClaudeAPIService.extractEventFromText(
                        text: ogText, sourceURL: urlString, location: location, language: language
                    )
                }
            } else {
                SharedContainerService.writeDebugLog("Extraction: OG metadata fetch failed")
            }

            // Last resort: social-aware extraction with just URL (rarely succeeds)
            SharedContainerService.writeDebugLog("Extraction: social media fallback for \(urlString.prefix(80))")
            return try await ClaudeAPIService.extractEventFromSocialURL(
                urlString: urlString, captionText: sourceText, location: location, language: language
            )
        }

        // Non-social: let Claude web-search the URL directly
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
