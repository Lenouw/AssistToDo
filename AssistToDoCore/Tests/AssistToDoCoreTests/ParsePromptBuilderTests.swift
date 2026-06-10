import XCTest
@testable import AssistToDoCore

final class ParsePromptBuilderTests: XCTestCase {
    func test_inclut_le_now_et_demande_json() {
        let now = ISO8601DateFormatter().date(from: "2026-06-10T15:30:00+02:00")!
        let sys = ParsePromptBuilder.systemPrompt(now: now)
        XCTAssertTrue(sys.contains("2026-06-10T15:30:00")) // ancre temporelle
        XCTAssertTrue(sys.lowercased().contains("json"))
        XCTAssertTrue(sys.contains("Europe/Paris"))
    }
}
