import Foundation

enum DigestService {
    private static let workerURL = URL(string: "https://event-digest-worker.daniel-j-wilson-587.workers.dev/events")!

    struct EventPayload: Encodable {
        let id: String
        let title: String
        let startDate: String
        let endDate: String
        let venue: String
        let address: String
        let description: String
        let timezone: String?
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
            self.googleCalendarURL = event.googleCalendarURL ?? ""
            self.createdAt = formatter.string(from: event.createdAt)
        }
    }

    static func sendToDigest(_ payload: EventPayload) async {
        guard let accessToken = await WorkerAuthService.accessToken() else { return }

        var request = URLRequest(url: workerURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONEncoder().encode(payload)
        request.timeoutInterval = 15

        // Fire-and-forget: digest is a convenience, not critical path
        _ = try? await URLSession.shared.data(for: request)
    }
}
