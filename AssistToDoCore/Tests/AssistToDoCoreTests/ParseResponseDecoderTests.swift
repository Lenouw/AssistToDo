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
}
