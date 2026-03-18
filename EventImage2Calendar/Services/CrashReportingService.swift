import Foundation
import MetricKit

final class CrashReportingService: NSObject, MXMetricManagerSubscriber {
    private static let maxReports = 20

    override init() {
        super.init()
        MXMetricManager.shared.add(self)
    }

    deinit {
        MXMetricManager.shared.remove(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            persist(payload.jsonRepresentation())
        }
    }

    private func persist(_ data: Data) {
        guard let dir = crashReportsDirectory() else { return }

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "crash_\(timestamp).json"
        let fileURL = dir.appendingPathComponent(filename)

        do {
            try data.write(to: fileURL)
        } catch {
            SharedContainerService.writeDebugLog("CrashReporting: failed to write report: \(error.localizedDescription)")
            return
        }

        pruneOldReports(in: dir)
    }

    private func pruneOldReports(in directory: URL) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        let sorted = files.sorted { a, b in
            let dateA = (try? a.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            let dateB = (try? b.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return dateA < dateB
        }

        let excess = sorted.count - Self.maxReports
        guard excess > 0 else { return }
        for file in sorted.prefix(excess) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func crashReportsDirectory() -> URL? {
        guard let container = SharedContainerService.containerURL else { return nil }
        let dir = container.appendingPathComponent("crash_reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
