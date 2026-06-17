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

    func test_rejette_filler_only() {
        let v = HallucinationFilter.evaluate(transcript: "euh hmm bah voilà", audioDuration: 2.0, avgLogProb: -0.2)
        XCTAssertEqual(v, .reject(.noContent))
    }

    func test_accepte_un_seul_vrai_mot() {
        let v = HallucinationFilter.evaluate(transcript: "pain", audioDuration: 2.0, avgLogProb: -0.3)
        XCTAssertEqual(v, .accept)
    }

    // Régression : une vraie tâche qui CONTIENT une sous-chaîne blacklistée ne doit pas être jetée.
    func test_accepte_vraie_tache_avec_sous_chaine_blacklist() {
        let v = HallucinationFilter.evaluate(
            transcript: "rappelle l'équipe d'écrire abonnez-vous à la newsletter sur la landing page",
            audioDuration: 3.0, avgLogProb: -0.3)
        XCTAssertEqual(v, .accept)
    }
}
