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

    func test_heure_passee_reporte_au_lendemain() {
        // il est 15:30, "à 8h" → demain 08:00 (pas aujourd'hui 08:00 déjà passé)
        let now = date("2026-06-10T15:30:00+02:00")
        let r = DateResolver.resolveRemind(text: "à 8h faire le point", now: now)
        XCTAssertEqual(r, date("2026-06-11T08:00:00+02:00"))
    }

    func test_heure_future_reste_aujourdhui() {
        // il est 15:30, "à 18h" → aujourd'hui 18:00 (inchangé)
        let now = date("2026-06-10T15:30:00+02:00")
        let r = DateResolver.resolveRemind(text: "à 18h acheter du pain", now: now)
        XCTAssertEqual(r, date("2026-06-10T18:00:00+02:00"))
    }

    func test_ce_soir_passe_reporte_au_lendemain() {
        // il est 22:00, "ce soir" (18h) déjà passé → demain 18:00
        let now = date("2026-06-10T22:00:00+02:00")
        let r = DateResolver.resolveRemind(text: "ce soir", now: now)
        XCTAssertEqual(r, date("2026-06-11T18:00:00+02:00"))
    }

    func test_delai_relatif_inchange() {
        // "dans deux heures" reste +2h même tard le soir (pas de report)
        let now = date("2026-06-10T23:00:00+02:00")
        let r = DateResolver.resolveRemind(text: "dans deux heures", now: now)
        XCTAssertEqual(r, date("2026-06-11T01:00:00+02:00"))
    }
}
