import UIKit
import SwiftData
import CoreLocation

@Observable
class BackgroundEventProcessor {
    let locationService = LocationService()

    @MainActor
    func processImage(_ image: UIImage, context: ModelContext) {
        guard let imageData = image.resizedForAPI() else { return }

        let event = PersistedEvent(status: .processing, imageData: imageData)
        context.insert(event)
        try? context.save()

        let eventID = event.id
        let location = locationService.currentLocation

        var bgTaskID: UIBackgroundTaskIdentifier = .invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "EventExtraction") {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }

        Task.detached {
            do {
                let details = try await ClaudeAPIService.extractEvent(
                    imageData: imageData,
                    location: location
                )

                // If the AI didn't extract a URL, search for one
                // If the AI didn't extract a URL from the poster, search for one
                let eventURL: String?
                if details.eventDescription.contains("http") {
                    eventURL = nil
                } else {
                    eventURL = await WebSearchService.findEventURL(
                        title: details.title,
                        venue: details.venue,
                        address: details.address
                    )
                }

                await MainActor.run {
                    let descriptor = FetchDescriptor<PersistedEvent>(
                        predicate: #Predicate { $0.id == eventID }
                    )
                    if let persisted = try? context.fetch(descriptor).first {
                        persisted.applyExtraction(details)

                        if !persisted.eventDescription.contains("http") {
                            let link = eventURL ?? WebSearchService.googleSearchURL(
                                title: persisted.title,
                                venue: persisted.venue,
                                address: persisted.address
                            )
                            persisted.eventDescription += "\n\n\(link)"
                        }

                        try? context.save()

                        let digestData = DigestService.EventPayload(from: persisted)
                        Task.detached {
                            await DigestService.sendToDigest(digestData)
                        }
                    }
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            } catch {
                await MainActor.run {
                    let descriptor = FetchDescriptor<PersistedEvent>(
                        predicate: #Predicate { $0.id == eventID }
                    )
                    if let persisted = try? context.fetch(descriptor).first {
                        persisted.status = .failed
                        persisted.errorMessage = error.localizedDescription
                        persisted.updatedAt = Date()
                        try? context.save()
                    }
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
        }
    }

    @MainActor
    func retryEvent(_ event: PersistedEvent, context: ModelContext) {
        guard let imageData = event.imageData else { return }

        event.status = .processing
        event.retryCount += 1
        event.errorMessage = nil
        event.updatedAt = Date()
        try? context.save()

        let eventID = event.id
        let location = locationService.currentLocation

        var bgTaskID: UIBackgroundTaskIdentifier = .invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "EventRetry") {
            UIApplication.shared.endBackgroundTask(bgTaskID)
            bgTaskID = .invalid
        }

        Task.detached {
            do {
                let details = try await ClaudeAPIService.extractEvent(
                    imageData: imageData,
                    location: location
                )

                let eventURL: String? = if details.eventDescription.contains("http") {
                    nil
                } else {
                    await WebSearchService.findEventURL(
                        title: details.title,
                        venue: details.venue,
                        address: details.address
                    )
                }

                await MainActor.run {
                    let descriptor = FetchDescriptor<PersistedEvent>(
                        predicate: #Predicate { $0.id == eventID }
                    )
                    if let persisted = try? context.fetch(descriptor).first {
                        persisted.applyExtraction(details)

                        if !persisted.eventDescription.contains("http") {
                            let link = eventURL ?? WebSearchService.googleSearchURL(
                                title: persisted.title,
                                venue: persisted.venue,
                                address: persisted.address
                            )
                            persisted.eventDescription += "\n\n\(link)"
                        }

                        try? context.save()
                    }
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            } catch {
                await MainActor.run {
                    let descriptor = FetchDescriptor<PersistedEvent>(
                        predicate: #Predicate { $0.id == eventID }
                    )
                    if let persisted = try? context.fetch(descriptor).first {
                        persisted.status = .failed
                        persisted.errorMessage = error.localizedDescription
                        persisted.updatedAt = Date()
                        try? context.save()
                    }
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
        }
    }
}
