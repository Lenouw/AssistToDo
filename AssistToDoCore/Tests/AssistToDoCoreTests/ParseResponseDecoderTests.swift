import XCTest
@testable import AssistToDoCore

final class ParseResponseDecoderTests: XCTestCase {
    func test_decode_avec_fences_et_null_strings() throws {
        let raw = """
        ```json
        {"tasks":[
          {"text":"S'inscrire sur le site des impôts","dueDate":"2026-06-11","remindAt":null,"priority":"haut","notify":false,"tags":[]},
          {"text":"Appeler le comptable","dueDate":"2026-06-15","remindAt":null,"priority":"null","notify":false,"tags":[]}
        ]}
        ```
        """
        let tasks = try ParseResponseDecoder.decode(raw)
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks[0].text, "S'inscrire sur le site des impôts")
        XCTAssertEqual(tasks[0].dueDateRaw, "2026-06-11")
        XCTAssertEqual(tasks[0].priority, .haut)
        XCTAssertNil(tasks[1].priority) // "null" string → nil
    }

    func test_decode_remindAt_et_notify() throws {
        let raw = #"{"tasks":[{"text":"appeler","remindAt":"2026-06-10T17:30:00+02:00","dueDate":null,"priority":null,"notify":true,"tags":["perso"]}]}"#
        let tasks = try ParseResponseDecoder.decode(raw)
        XCTAssertEqual(tasks[0].remindAtRaw, "2026-06-10T17:30:00+02:00")
        XCTAssertTrue(tasks[0].notify)
        XCTAssertEqual(tasks[0].tags, ["perso"])
    }

    func test_json_invalide_jette() {
        XCTAssertThrowsError(try ParseResponseDecoder.decode("pas du json"))
    }

    func test_decode_destination_calendar_avec_duree() throws {
        let raw = #"{"tasks":[{"text":"Rdv médecin","destination":"calendar","remindAt":"2026-06-12T14:00:00+02:00","dueDate":null,"durationMinutes":30,"calendarName":"Perso","listName":null,"priority":null,"notify":true,"tags":[]}]}"#
        let tasks = try ParseResponseDecoder.decode(raw)
        XCTAssertEqual(tasks[0].destination, .calendar)
        XCTAssertEqual(tasks[0].durationMinutes, 30)
        XCTAssertEqual(tasks[0].calendarName, "Perso")
    }

    func test_decode_destination_reminders_avec_liste() throws {
        let raw = #"{"tasks":[{"text":"Acheter du lait","destination":"reminders","remindAt":null,"dueDate":"2026-06-13","listName":"Courses","priority":null,"notify":false,"tags":[]}]}"#
        let tasks = try ParseResponseDecoder.decode(raw)
        XCTAssertEqual(tasks[0].destination, .reminders)
        XCTAssertEqual(tasks[0].listName, "Courses")
    }

    func test_decode_calendar_category() throws {
        let raw = #"{"tasks":[{"text":"Réunion client","destination":"calendar","calendarCategory":"pro","remindAt":"2026-06-12T10:00:00+02:00","dueDate":null,"priority":null,"notify":true,"tags":[]}]}"#
        let tasks = try ParseResponseDecoder.decode(raw)
        XCTAssertEqual(tasks[0].calendarCategory, .pro)
    }

    func test_calendar_category_absente_ou_inconnue_donne_nil() throws {
        let raw = #"{"tasks":[{"text":"x","destination":"calendar","calendarCategory":"galaxie","remindAt":null,"dueDate":null,"priority":null,"notify":false,"tags":[]}]}"#
        let tasks = try ParseResponseDecoder.decode(raw)
        XCTAssertNil(tasks[0].calendarCategory)
    }

    func test_decode_destination_notes_avec_note() throws {
        let raw = #"{"tasks":[{"text":"Lait","destination":"notes","noteName":"Courses","remindAt":null,"dueDate":null,"priority":null,"notify":false,"tags":[]}]}"#
        let tasks = try ParseResponseDecoder.decode(raw)
        XCTAssertEqual(tasks[0].destination, .notes)
        XCTAssertEqual(tasks[0].noteName, "Courses")
    }

    func test_destination_absente_ou_inconnue_donne_local() throws {
        let raw = #"{"tasks":[{"text":"a","remindAt":null,"dueDate":null,"priority":null,"notify":false,"tags":[]},{"text":"b","destination":"galaxie","remindAt":null,"dueDate":null,"priority":null,"notify":false,"tags":[]}]}"#
        let tasks = try ParseResponseDecoder.decode(raw)
        XCTAssertEqual(tasks[0].destination, .local)   // champ absent
        XCTAssertEqual(tasks[1].destination, .local)   // valeur inconnue
    }
}
