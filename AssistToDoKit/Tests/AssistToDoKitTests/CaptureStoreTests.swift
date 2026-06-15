import XCTest
@testable import AssistToDoKit

final class CaptureStoreTests: XCTestCase {
    func test_status_roundtrips_through_raw() {
        XCTAssertEqual(CaptureStatus(raw: "done"), .done)
        XCTAssertEqual(CaptureStatus(raw: "failed:llm:timeout").raw, "failed:llm:timeout")
        XCTAssertEqual(CaptureStatus(raw: "garbage"), .recorded) // défaut sûr
    }
}
