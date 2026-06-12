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

    func test_injecte_les_regles_personnalisees() {
        let now = ISO8601DateFormatter().date(from: "2026-06-10T15:30:00+02:00")!
        let sys = ParsePromptBuilder.systemPrompt(now: now,
            customRules: "Les rdv kiné vont dans l'agenda commun. Fermeture du studio => agenda studio.")
        XCTAssertTrue(sys.contains("kiné"))
        XCTAssertTrue(sys.contains("studio"))
    }

    func test_inclut_la_regle_echeance_molle() {
        let now = ISO8601DateFormatter().date(from: "2026-06-13T10:00:00+02:00")!
        let sys = ParsePromptBuilder.systemPrompt(now: now)
        // Bug A : une échéance molle ("avant/pour/d'ici [date]") doit rester local et conserver la date dans le texte.
        XCTAssertTrue(sys.contains("ÉCHÉANCE MOLLE"))
        XCTAssertTrue(sys.contains("CONSERVE la mention d'échéance"))
    }

    func test_injecte_les_calendriers_et_listes() {
        let now = ISO8601DateFormatter().date(from: "2026-06-10T15:30:00+02:00")!
        let sys = ParsePromptBuilder.systemPrompt(now: now,
                                                  calendars: ["Perso", "BoulouFlo", "Marion et Flo"],
                                                  reminderLists: ["Courses"])
        XCTAssertTrue(sys.contains("BoulouFlo"))
        XCTAssertTrue(sys.contains("Marion et Flo"))
        XCTAssertTrue(sys.contains("Courses"))
        XCTAssertTrue(sys.contains("calendarName"))
    }
}
