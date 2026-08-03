import XCTest
@testable import AssistToDoKit
@testable import AssistToDoCore

/// Garde-fou « écho » : le LLM recrache parfois la phrase dictée telle quelle en note locale
/// (raté d'instruction observé en prod sur « Ferme le studio le vendredi 9 septembre de 15h à 16h »).
/// Le parseur doit retenter une fois et utiliser la 2ᵉ réponse si elle est correcte.
final class TaskParserEchoTests: XCTestCase {
    /// Renvoie les réponses fournies, dans l'ordre, à chaque appel.
    final class ScriptedClient: LLMCompleting, @unchecked Sendable {
        private var responses: [String]
        private(set) var calls = 0
        init(_ responses: [String]) { self.responses = responses }
        func complete(system: String, user: String) async throws -> String {
            defer { calls += 1 }
            return responses[min(calls, responses.count - 1)]
        }
    }

    private let transcript = "Ferme le studio le vendredi 9 septembre de 15h à 16h."
    private var echoJSON: String {
        #"{"tasks":[{"text":"Ferme le studio le vendredi 9 septembre de 15h à 16h.","destination":"local"}]}"#
    }
    private var goodJSON: String {
        #"{"tasks":[{"text":"Studio fermé","destination":"calendar","calendarCategory":"studio","dueDate":"2026-09-09","remindAt":"2026-09-09T15:00:00+02:00","durationMinutes":60}]}"#
    }

    func test_echo_declenche_un_retry_et_utilise_la_bonne_reponse() async {
        let client = ScriptedClient([echoJSON, goodJSON])
        let parser = TaskParser(client: client)
        let out = await parser.parse(transcript: transcript, now: Date())
        XCTAssertEqual(client.calls, 2)                       // a bien retenté
        XCTAssertEqual(out.first?.destination, .calendar)     // événement, pas note locale
        XCTAssertEqual(out.first?.record.text, "Studio fermé")
    }

    func test_pas_de_retry_quand_la_reponse_est_bonne_du_premier_coup() async {
        let client = ScriptedClient([goodJSON])
        let parser = TaskParser(client: client)
        _ = await parser.parse(transcript: transcript, now: Date())
        XCTAssertEqual(client.calls, 1)
    }

    /// Une note sans repère temporel qui ressemble au transcript est LÉGITIME → aucun retry.
    func test_note_simple_sans_date_nest_pas_un_echo() async {
        let simple = "acheter du pain"
        let json = #"{"tasks":[{"text":"Acheter du pain","destination":"local"}]}"#
        let client = ScriptedClient([json])
        let parser = TaskParser(client: client)
        _ = await parser.parse(transcript: simple, now: Date())
        XCTAssertEqual(client.calls, 1)
    }

    /// Si le retry échoue aussi, on garde la 1ʳᵉ réponse (jamais de capture perdue).
    func test_retry_rate_on_garde_la_premiere_reponse() async {
        let client = ScriptedClient([echoJSON, echoJSON])
        let parser = TaskParser(client: client)
        let out = await parser.parse(transcript: transcript, now: Date())
        XCTAssertEqual(client.calls, 2)
        XCTAssertEqual(out.count, 1)
        XCTAssertFalse(out[0].record.text.isEmpty)
    }
}
