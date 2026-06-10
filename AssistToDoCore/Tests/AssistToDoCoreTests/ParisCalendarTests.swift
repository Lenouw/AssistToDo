import XCTest
@testable import AssistToDoCore

final class ParisCalendarTests: XCTestCase {
    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter(); return f.date(from: iso)!
    }

    func test_today_ete_UTCplus2() {
        // 2026-06-10T23:30:00Z = 2026-06-11 01:30 Paris (été) → jour Paris = 11
        let now = date("2026-06-10T23:30:00Z")
        XCTAssertEqual(ParisCalendar.ymd(for: now), "2026-06-11")
    }

    func test_today_hiver_UTCplus1() {
        // 2026-01-10T23:30:00Z = 2026-01-11 00:30 Paris (hiver) → jour Paris = 11
        let now = date("2026-01-10T23:30:00Z")
        XCTAssertEqual(ParisCalendar.ymd(for: now), "2026-01-11")
    }

    func test_weekday_monday() {
        // 2026-06-15 est un lundi
        let d = date("2026-06-15T10:00:00+02:00")
        XCTAssertEqual(ParisCalendar.weekday(for: d), 2) // 1=dim..7=sam (Calendar)
    }
}
