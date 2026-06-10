import XCTest
@testable import AssistToDoCore

final class DateResolverTests: XCTestCase {
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func test_dans_deux_heures() {
        let now = date("2026-06-10T15:30:00+02:00")
        let r = DateResolver.resolveRemind(text: "appeler le médecin dans deux heures", now: now)
        XCTAssertEqual(r, date("2026-06-10T17:30:00+02:00"))
    }

    func test_dans_une_demi_heure() {
        let now = date("2026-06-10T15:30:00+02:00")
        let r = DateResolver.resolveRemind(text: "dans une demi heure", now: now)
        XCTAssertEqual(r, date("2026-06-10T16:00:00+02:00"))
    }

    func test_a_dix_huit_heures() {
        let now = date("2026-06-10T15:30:00+02:00")
        let r = DateResolver.resolveRemind(text: "à 18h acheter du pain", now: now)
        XCTAssertEqual(r, date("2026-06-10T18:00:00+02:00"))
    }

    func test_lundi_prochain_donne_un_lundi() {
        let now = date("2026-06-10T15:30:00+02:00") // mercredi
        let due = DateResolver.resolveDueDate(text: "lundi prochain envoyer le dossier", now: now)
        XCTAssertEqual(ParisCalendar.ymd(for: due!), "2026-06-15")
        XCTAssertEqual(ParisCalendar.weekday(for: due!), 2) // lundi
    }

    func test_demain() {
        let now = date("2026-06-10T15:30:00+02:00")
        let due = DateResolver.resolveDueDate(text: "demain", now: now)
        XCTAssertEqual(ParisCalendar.ymd(for: due!), "2026-06-11")
    }

    func test_ce_soir_donne_18h() {
        let now = date("2026-06-10T15:30:00+02:00")
        let r = DateResolver.resolveRemind(text: "ce soir", now: now)
        XCTAssertEqual(r, date("2026-06-10T18:00:00+02:00"))
    }

    func test_aucun_motif_retourne_nil() {
        let now = date("2026-06-10T15:30:00+02:00")
        XCTAssertNil(DateResolver.resolveRemind(text: "acheter du pain", now: now))
    }
}
