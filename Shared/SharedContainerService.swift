import Foundation

enum SharedContainerService {
    private static let appGroupID = "group.com.eventsnap.shared"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    static var pendingSharesDirectory: URL? {
        guard let container = containerURL else { return nil }
        let dir = container.appendingPathComponent("PendingShares", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Write (called by Share Extension)

    static func savePendingShare(imageData: Data?, sourceURL: String?, sourceText: String?) throws -> UUID {
        guard let dir = pendingSharesDirectory else {
            throw ShareError.noContainer
        }

        let shareID = UUID()

        var imageFileName: String?
        if let imageData {
            let fileName = "\(shareID.uuidString).jpg"
            try imageData.write(to: dir.appendingPathComponent(fileName))
            imageFileName = fileName
        }

        let sourceType: PendingShare.SourceType
        if imageData != nil {
            sourceType = .image
        } else if sourceURL != nil {
            sourceType = .url
        } else {
            sourceType = .text
        }

        let pending = PendingShare(
            id: shareID,
            createdAt: Date(),
            sourceType: sourceType,
            imageFileName: imageFileName,
            sourceURL: sourceURL,
            sourceText: sourceText
        )

        let metadataURL = dir.appendingPathComponent("\(shareID.uuidString).json")
        try JSONEncoder().encode(pending).write(to: metadataURL)

        return shareID
    }

    // MARK: - Read (called by main app)

    static func loadPendingShares() -> [(PendingShare, Data?)] {
        guard let dir = pendingSharesDirectory else { return [] }
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }

        var results: [(PendingShare, Data?)] = []
        for file in files where file.pathExtension == "json" {
            guard let jsonData = try? Data(contentsOf: file),
                  let pending = try? JSONDecoder().decode(PendingShare.self, from: jsonData) else {
                continue
            }
            var imageData: Data?
            if let imageFileName = pending.imageFileName {
                imageData = try? Data(contentsOf: dir.appendingPathComponent(imageFileName))
            }
            results.append((pending, imageData))
        }
        return results
    }

    // MARK: - Cleanup (called by main app after consuming)

    static func deletePendingShare(_ share: PendingShare) {
        guard let dir = pendingSharesDirectory else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(share.id.uuidString).json"))
        if let imageFileName = share.imageFileName {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(imageFileName))
        }
    }

    // MARK: - Debug log (written by extension, read by main app)

    private static let maxLogBytes = 1_000_000 // 1 MB
    private static let keepLogBytes = 500_000   // keep tail on rotation

    static func writeDebugLog(_ text: String) {
        guard let container = containerURL else { return }
        let logURL = container.appendingPathComponent("share_debug.log")
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[\(timestamp)] \(text)\n"

        rotateLogIfNeeded(at: logURL)

        if let handle = try? FileHandle(forWritingTo: logURL) {
            handle.seekToEndOfFile()
            handle.write(entry.data(using: .utf8) ?? Data())
            handle.closeFile()
        } else {
            try? entry.data(using: .utf8)?.write(to: logURL)
        }
    }

    private static func rotateLogIfNeeded(at logURL: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
              let size = attrs[.size] as? Int,
              size > maxLogBytes else { return }

        guard let data = try? Data(contentsOf: logURL) else { return }
        let tail = data.suffix(keepLogBytes)
        try? tail.write(to: logURL)
    }

    static func readDebugLog() -> String? {
        guard let container = containerURL else { return nil }
        let logURL = container.appendingPathComponent("share_debug.log")
        return try? String(contentsOf: logURL, encoding: .utf8)
    }

    static func clearDebugLog() {
        guard let container = containerURL else { return }
        let logURL = container.appendingPathComponent("share_debug.log")
        try? FileManager.default.removeItem(at: logURL)
    }

    enum ShareError: LocalizedError {
        case noContainer
        var errorDescription: String? { "Could not access shared container" }
    }
}
