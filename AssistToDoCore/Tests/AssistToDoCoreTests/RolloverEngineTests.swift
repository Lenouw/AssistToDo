import XCTest
@testable import AssistToDoCore

final class RolloverEngineTests: XCTestCase {
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func task(due: String, done: Bool = false, rolls: Int = 0) -> TaskRecord {
        TaskRecord(text: "t", createdAt: date("2026-06-09T10:00:00+02:00"),
                   dueDate: date(due), isDone: done, rolloverCount: rolls)
    }

    func test_tache_en_retard_non_faite_roule_a_aujourdhui() {
        let now = date("2026-06-10T09:00:00+02:00")
        let input = [task(due: "2026-06-09T10:00:00+02:00")]
        let out = RolloverEngine.apply(tasks: input, now: now, lastRolloverDay: nil)
        XCTAssertEqual(ParisCalendar.ymd(for: out.tasks[0].dueDate!), "2026-06-10")
        XCTAssertEqual(out.tasks[0].rolloverCount, 1)
        XCTAssertEqual(out.rolledDay, "2026-06-10")
    }

    func test_tache_faite_ne_roule_pas() {
        let now = date("2026-06-10T09:00:00+02:00")
        let input = [task(due: "2026-06-09T10:00:00+02:00", done: true)]
        let out = RolloverEngine.apply(tasks: input, now: now, lastRolloverDay: nil)
        XCTAssertEqual(ParisCalendar.ymd(for: out.tasks[0].dueDate!), "2026-06-09")
        XCTAssertEqual(out.tasks[0].rolloverCount, 0)
    }

    func test_idempotent_meme_jour() {
        let now = date("2026-06-10T09:00:00+02:00")
        let input = [task(due: "2026-06-09T10:00:00+02:00")]
        let out = RolloverEngine.apply(tasks: input, now: now, lastRolloverDay: "2026-06-10")
        XCTAssertEqual(ParisCalendar.ymd(for: out.tasks[0].dueDate!), "2026-06-09")
        XCTAssertEqual(out.tasks[0].rolloverCount, 0)
    }

    func test_tache_du_jour_ne_roule_pas() {
        let now = date("2026-06-10T09:00:00+02:00")
        let input = [task(due: "2026-06-10T08:00:00+02:00")]
        let out = RolloverEngine.apply(tasks: input, now: now, lastRolloverDay: nil)
        XCTAssertEqual(out.tasks[0].rolloverCount, 0)
    }
}
