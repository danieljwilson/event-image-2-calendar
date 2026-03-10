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
                    let details: EventDetails
                    if let imageData {
                        SharedContainerService.writeDebugLog("Extraction: image path (\(imageData.count) bytes)")
                        do {
                            details = try await ClaudeAPIService.extractEvent(
                                imageData: imageData, location: location
                            )
                        } catch ClaudeAPIError.noEventFound where sourceURL != nil {
                            SharedContainerService.writeDebugLog("Extraction: image found nothing, trying page content from \(sourceURL!)")
                            details = try await Self.extractFromURL(
                                sourceURL!, sourceText: sourceText, location: location
                            )
                        }
                    } else if let sourceURL {
                        SharedContainerService.writeDebugLog("Extraction: URL path for \(sourceURL)")
                        details = try await Self.extractFromURL(
                            sourceURL, sourceText: sourceText, location: location
                        )
                    } else if let sourceText, !sourceText.isEmpty {
                        SharedContainerService.writeDebugLog("Extraction: text-only path (\(sourceText.count) chars)")
                        details = try await ClaudeAPIService.extractEventFromText(
                            text: sourceText, sourceURL: nil, location: location
                        )
                    } else {
                        throw ClaudeAPIError.invalidResponse
                    }

                    // Try to enrich sparse results via web search
                    let enriched = await Self.enrichIfNeeded(details, location: location)

                    await MainActor.run {
                        let descriptor = FetchDescriptor<PersistedEvent>(
                            predicate: #Predicate { $0.id == eventID }
                        )
                        if let persisted = try? context.fetch(descriptor).first {
                            persisted.applyExtraction(enriched)

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

    // MARK: - Post-extraction enrichment via web search

    /// Check if extracted details are sparse and try to enrich via web search.
    private static func enrichIfNeeded(
        _ details: EventDetails,
        location: CLLocationCoordinate2D?
    ) async -> EventDetails {
        let vagueVenueKeywords = ["event venue", "cinema or", "tbd", "unknown", "venue in"]
        let venueIsVague = details.venue.isEmpty ||
            vagueVenueKeywords.contains(where: { details.venue.lowercased().contains($0) })
        let addressIsEmpty = details.address.isEmpty
        let descriptionIsShort = details.eventDescription.count < 80

        guard venueIsVague || addressIsEmpty || descriptionIsShort else {
            return details  // Details are already good enough
        }

        SharedContainerService.writeDebugLog("Enrichment: needed (venue=\(venueIsVague), addr=\(addressIsEmpty), desc=\(descriptionIsShort))")

        // Search for the event's own page
        guard let resultURL = await WebSearchService.searchForEventPage(
            title: details.title, venue: details.venue, address: details.address
        ) else {
            SharedContainerService.writeDebugLog("Enrichment: no search results found")
            return details
        }

        SharedContainerService.writeDebugLog("Enrichment: found \(resultURL.prefix(100))")

        // Fetch the page content
        guard let page = await fetchPageContent(from: resultURL),
              let bodyText = page.bodyText, !bodyText.isEmpty else {
            SharedContainerService.writeDebugLog("Enrichment: could not fetch page content")
            return details
        }

        let fullText = combineContext(
            pageTitle: page.pageTitle, bodyText: bodyText, ogText: page.ogText
        )

        // Ask Claude to enrich
        do {
            let enriched = try await ClaudeAPIService.enrichEventDetails(
                current: details, pageText: fullText, location: location
            )
            SharedContainerService.writeDebugLog("Enrichment: success — venue=\(enriched.venue), addr=\(enriched.address.prefix(50))")
            return enriched
        } catch {
            SharedContainerService.writeDebugLog("Enrichment: Claude error — \(error.localizedDescription)")
            return details  // Return original on failure
        }
    }

    // MARK: - URL extraction with fallback chain

    /// Full fallback chain: OG image → page text → sourceText → bare URL
    private static func extractFromURL(
        _ urlString: String,
        sourceText: String?,
        location: CLLocationCoordinate2D?
    ) async throws -> EventDetails {
        let page = await fetchPageContent(from: urlString)

        // 1. If OG image found → vision extraction + text context
        if let page, let ogImageURL = page.ogImageURL,
           let ogImageData = await downloadAndDownsample(from: ogImageURL) {
            let context = combineContext(ogText: page.ogText, sourceText: sourceText)
            SharedContainerService.writeDebugLog("Extraction: OG image (\(ogImageData.count) bytes), context=\(context.count) chars")
            return try await ClaudeAPIService.extractEvent(
                imageData: ogImageData, location: location,
                additionalContext: context.isEmpty ? nil : context
            )
        }

        // 2. If page text found (body text OR OG text) → text-based extraction
        let fullText = combineContext(
            pageTitle: page?.pageTitle, bodyText: page?.bodyText,
            ogText: page?.ogText, sourceText: sourceText
        )
        if !fullText.isEmpty {
            SharedContainerService.writeDebugLog("Extraction: page text (\(fullText.count) chars)")
            return try await ClaudeAPIService.extractEventFromText(
                text: fullText, sourceURL: urlString, location: location
            )
        }

        // 3. If we have sourceText from the share extension (and nothing from page)
        if let sourceText, !sourceText.isEmpty {
            SharedContainerService.writeDebugLog("Extraction: sourceText fallback (\(sourceText.count) chars)")
            return try await ClaudeAPIService.extractEventFromText(
                text: sourceText, sourceURL: urlString, location: location
            )
        }

        // 4. Last resort — bare URL
        SharedContainerService.writeDebugLog("Extraction: bare URL fallback")
        return try await ClaudeAPIService.extractEventFromURL(
            urlString: urlString, location: location
        )
    }

    // MARK: - Page content fetching (for URL shares)

    struct PageContent {
        var ogImageURL: String?
        var ogText: String?     // Combined OG title + description
        var bodyText: String?   // Visible text extracted from HTML body
        var pageTitle: String?  // <title> tag content
    }

    /// User-Agents to try, in order. Desktop Safari first (works for most sites),
    /// then Facebook crawler (works for Instagram/Meta sites).
    private static let userAgents = [
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
        "facebookexternalhit/1.1"
    ]

    /// Fetch page content with multi-strategy User-Agent and body text extraction.
    private static func fetchPageContent(from urlString: String) async -> PageContent? {
        guard let url = URL(string: urlString) else { return nil }

        var html: String?

        // Try each UA until we get a substantial response
        for ua in userAgents {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue(ua, forHTTPHeaderField: "User-Agent")

            guard let (data, response) = try? await URLSession.shared.data(for: request) else { continue }
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            SharedContainerService.writeDebugLog("Page fetch HTTP \(statusCode) with UA=\(ua.prefix(30))..., \(data.count) bytes")

            if statusCode == 200, let text = String(data: data, encoding: .utf8), text.count > 500 {
                html = text
                break
            }
        }

        // For Instagram URLs, also try the /embed/ variant
        if (html == nil || html!.count < 500),
           urlString.contains("instagram.com/p/") || urlString.contains("instagram.com/reel/") {
            let embedURL = urlString.components(separatedBy: "?").first.map { $0 + "embed/" } ?? urlString + "embed/"
            SharedContainerService.writeDebugLog("Trying Instagram embed: \(embedURL)")
            guard let embedRequestURL = URL(string: embedURL) else { return nil }
            var request = URLRequest(url: embedRequestURL)
            request.timeoutInterval = 10
            request.setValue(userAgents[0], forHTTPHeaderField: "User-Agent")
            if let (data, _) = try? await URLSession.shared.data(for: request),
               let text = String(data: data, encoding: .utf8), text.count > 500 {
                html = text
            }
        }

        guard let html, !html.isEmpty else {
            SharedContainerService.writeDebugLog("Page fetch failed: no usable HTML from \(urlString)")
            return nil
        }

        var content = PageContent()

        // Extract OG tags
        content.ogImageURL = extractMetaContent(from: html, property: "og:image")

        var ogParts: [String] = []
        if let title = extractMetaContent(from: html, property: "og:title") { ogParts.append(title) }
        if let desc = extractMetaContent(from: html, property: "og:description") { ogParts.append(desc) }
        if !ogParts.isEmpty {
            content.ogText = ogParts.joined(separator: "\n")
        }

        // Extract <title> tag
        if let regex = try? NSRegularExpression(pattern: #"<title[^>]*>([^<]+)</title>"#, options: .caseInsensitive),
           let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
           let range = Range(match.range(at: 1), in: html) {
            content.pageTitle = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Extract visible body text
        content.bodyText = extractVisibleText(from: html)

        SharedContainerService.writeDebugLog("Page content: ogImage=\(content.ogImageURL != nil), ogText=\(content.ogText != nil), bodyText=\(content.bodyText?.count ?? 0) chars, title=\(content.pageTitle ?? "nil")")

        return content
    }

    /// Extract a meta tag's content by property or name attribute.
    private static func extractMetaContent(from html: String, property: String) -> String? {
        let patterns = [
            #"<meta[^>]*property=["']\#(property)["'][^>]*content=["']([^"']+)["']"#,
            #"<meta[^>]*content=["']([^"']+)["'][^>]*property=["']\#(property)["']"#,
            #"<meta[^>]*name=["']\#(property)["'][^>]*content=["']([^"']+)["']"#,
            #"<meta[^>]*content=["']([^"']+)["'][^>]*name=["']\#(property)["']"#
        ]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range])
            }
        }
        return nil
    }

    /// Strip HTML tags and extract visible text content.
    private static func extractVisibleText(from html: String) -> String? {
        var text = html

        // Remove script, style, nav, footer, header blocks
        let blockPatterns = [
            #"<script[^>]*>[\s\S]*?</script>"#,
            #"<style[^>]*>[\s\S]*?</style>"#,
            #"<nav[^>]*>[\s\S]*?</nav>"#,
            #"<footer[^>]*>[\s\S]*?</footer>"#,
            #"<header[^>]*>[\s\S]*?</header>"#
        ]
        for pattern in blockPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
            }
        }

        // Strip remaining HTML tags
        if let regex = try? NSRegularExpression(pattern: "<[^>]+>") {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }

        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        // Collapse whitespace
        text = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        let trimmed = String(text.prefix(4000))
        return trimmed.count > 50 ? trimmed : nil  // Only return if meaningful content
    }

    /// Combine various text sources into a single context string for Claude.
    private static func combineContext(
        pageTitle: String? = nil,
        bodyText: String? = nil,
        ogText: String? = nil,
        sourceText: String? = nil
    ) -> String {
        var parts: [String] = []
        if let pageTitle, !pageTitle.isEmpty { parts.append("Page title: \(pageTitle)") }
        if let ogText, !ogText.isEmpty { parts.append("Page summary: \(ogText)") }
        if let sourceText, !sourceText.isEmpty { parts.append("Shared context: \(sourceText)") }
        if let bodyText, !bodyText.isEmpty { parts.append("Page content:\n\(bodyText)") }
        return parts.joined(separator: "\n\n")
    }

    /// Download an image URL and downsample it for the API.
    private static func downloadAndDownsample(from urlString: String) async -> Data? {
        // Decode HTML entities (Instagram OG URLs often have &amp; instead of &)
        let decoded = urlString
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
        guard let url = URL(string: decoded) else {
            SharedContainerService.writeDebugLog("Image download: invalid URL \(decoded.prefix(100))")
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(userAgents[0], forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request) else {
            SharedContainerService.writeDebugLog("Image download: network error for \(decoded.prefix(100))")
            return nil
        }
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        SharedContainerService.writeDebugLog("Image download: HTTP \(statusCode), \(data.count) bytes")
        guard statusCode == 200, data.count > 100 else { return nil }
        return ImageResizer.downsample(data: data)
    }
}
