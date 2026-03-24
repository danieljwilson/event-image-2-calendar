import UIKit

struct FeedbackLogEntry: Codable {
    let timestamp: Date
    let appVersion: String
    let buildNumber: String
    let deviceModel: String
    let iOSVersion: String
    let messagePreview: String
    let hadScreenshot: Bool
}

enum FeedbackService {
    static let feedbackEmail = "daniel.j.wilson@gmail.com"

    static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }

    static func deviceMetadata() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let device = UIDevice.current.model
        let systemVersion = UIDevice.current.systemVersion
        let locale = Locale.current.identifier
        let timezone = TimeZone.current.identifier
        let testFlight = isTestFlight ? "Yes" : "No"
        let date = ISO8601DateFormatter().string(from: Date())

        return """
        ---
        App: Event Snap \(version) (build \(build))
        Device: \(device) (iOS \(systemVersion))
        Locale: \(locale)
        Timezone: \(timezone)
        TestFlight: \(testFlight)
        Date: \(date)
        ---
        """
    }

    static func captureScreenshot() -> Data? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let window = scene.windows.first(where: { $0.isKeyWindow })
        else { return nil }

        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { context in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }
        return image.jpegData(compressionQuality: 0.8)
    }

    // MARK: - Feedback Log

    private static let logFileName = "feedback_log.json"

    private static var logURL: URL? {
        SharedContainerService.containerURL?.appendingPathComponent(logFileName)
    }

    static func logFeedback(messagePreview: String, hadScreenshot: Bool) {
        guard let url = logURL else { return }

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        let entry = FeedbackLogEntry(
            timestamp: Date(),
            appVersion: version,
            buildNumber: build,
            deviceModel: UIDevice.current.model,
            iOSVersion: UIDevice.current.systemVersion,
            messagePreview: String(messagePreview.prefix(200)),
            hadScreenshot: hadScreenshot
        )

        var entries = readFeedbackLog()
        entries.append(entry)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            try? data.write(to: url)
        }
    }

    static func readFeedbackLog() -> [FeedbackLogEntry] {
        guard let url = logURL,
              let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([FeedbackLogEntry].self, from: data)) ?? []
    }
}
