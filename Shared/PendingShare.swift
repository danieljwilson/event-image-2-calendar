import Foundation

struct PendingShare: Codable {
    let id: UUID
    let createdAt: Date
    let sourceType: SourceType
    let imageFileName: String?
    let sourceURL: String?
    let sourceText: String?

    enum SourceType: String, Codable {
        case image
        case url
        case text
    }
}
