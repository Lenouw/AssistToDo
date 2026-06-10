import XCTest
@testable import AssistToDoCore

final class HallucinationFilterTests: XCTestCase {
    func test_rejette_audio_trop_court() {
        let v = HallucinationFilter.evaluate(transcript: "acheter du pain", audioDuration: 0.5, avgLogProb: -0.2)
        XCTAssertEqual(v, .reject(.tooShort))
    }

    func test_rejette_blacklist_fr() {
        let v = HallucinationFilter.evaluate(transcript: "Sous-titres réalisés par la communauté d'Amara.org", audioDuration: 2.0, avgLogProb: -0.2)
        XCTAssertEqual(v, .reject(.blacklisted))
    }

    func test_rejette_confiance_faible() {
        let v = HallucinationFilter.evaluate(transcript: "appeler marc", audioDuration: 2.0, avgLogProb: -2.5)
        XCTAssertEqual(v, .reject(.lowConfidence))
    }

    func test_accepte_normal() {
        let v = HallucinationFilter.evaluate(transcript: "appeler le médecin dans deux heures", audioDuration: 2.5, avgLogProb: -0.3)
        XCTAssertEqual(v, .accept)
    }
}
