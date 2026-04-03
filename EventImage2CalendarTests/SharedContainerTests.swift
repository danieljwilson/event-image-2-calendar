import XCTest
@testable import EventImage2Calendar

final class SharedContainerTests: XCTestCase {

    func testPendingShare_imageType_roundTrip() throws {
        let share = PendingShare(
            id: UUID(),
            createdAt: Date(),
            sourceType: .image,
            imageFileName: "photo.jpg",
            sourceURL: nil,
            sourceText: nil
        )

        let data = try JSONEncoder().encode(share)
        let decoded = try JSONDecoder().decode(PendingShare.self, from: data)

        XCTAssertEqual(decoded.id, share.id)
        XCTAssertEqual(decoded.sourceType, .image)
        XCTAssertEqual(decoded.imageFileName, "photo.jpg")
        XCTAssertNil(decoded.sourceURL)
        XCTAssertNil(decoded.sourceText)
    }

    func testPendingShare_urlType_roundTrip() throws {
        let share = PendingShare(
            id: UUID(),
            createdAt: Date(),
            sourceType: .url,
            imageFileName: nil,
            sourceURL: "https://example.com/event",
            sourceText: "Check this out"
        )

        let data = try JSONEncoder().encode(share)
        let decoded = try JSONDecoder().decode(PendingShare.self, from: data)

        XCTAssertEqual(decoded.sourceType, .url)
        XCTAssertEqual(decoded.sourceURL, "https://example.com/event")
        XCTAssertEqual(decoded.sourceText, "Check this out")
        XCTAssertNil(decoded.imageFileName)
    }

    func testPendingShare_textType_roundTrip() throws {
        let share = PendingShare(
            id: UUID(),
            createdAt: Date(),
            sourceType: .text,
            imageFileName: nil,
            sourceURL: nil,
            sourceText: "Join us for a concert on June 15th at 8pm"
        )

        let data = try JSONEncoder().encode(share)
        let decoded = try JSONDecoder().decode(PendingShare.self, from: data)

        XCTAssertEqual(decoded.sourceType, .text)
        XCTAssertEqual(decoded.sourceText, "Join us for a concert on June 15th at 8pm")
    }

    func testSourceType_rawValues() {
        XCTAssertEqual(PendingShare.SourceType.image.rawValue, "image")
        XCTAssertEqual(PendingShare.SourceType.url.rawValue, "url")
        XCTAssertEqual(PendingShare.SourceType.text.rawValue, "text")
    }

    func testPendingShare_datePreserved() throws {
        let now = Date()
        let share = PendingShare(
            id: UUID(),
            createdAt: now,
            sourceType: .image,
            imageFileName: "test.jpg",
            sourceURL: nil,
            sourceText: nil
        )

        let data = try JSONEncoder().encode(share)
        let decoded = try JSONDecoder().decode(PendingShare.self, from: data)

        XCTAssertEqual(decoded.createdAt.timeIntervalSince1970, now.timeIntervalSince1970, accuracy: 0.001)
    }
}
