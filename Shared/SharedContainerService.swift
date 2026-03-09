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

    enum ShareError: LocalizedError {
        case noContainer
        var errorDescription: String? { "Could not access shared container" }
    }
}
