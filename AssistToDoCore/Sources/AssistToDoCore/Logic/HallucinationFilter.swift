import Foundation

public enum HallucinationFilter {
    public enum Reason: Equatable { case tooShort, blacklisted, lowConfidence, noContent }
    public enum Verdict: Equatable { case accept, reject(Reason) }

    public static let minDuration: TimeInterval = 0.8
    public static let minAvgLogProb: Double = -1.5

    static let blacklist: [String] = [
        "sous-titres réalisés par",
        "sous-titrage",
        "merci d'avoir regardé",
        "amara.org",
        "abonnez-vous"
    ]

    /// Mots de remplissage : si la transcription n'est QUE ça, il n'y a pas de contenu réel.
    static let fillers: Set<String> = [
        "euh", "heu", "heum", "hmm", "hum", "mmh", "mm", "bah", "ben",
        "ah", "oh", "eh", "hein", "bon", "alors", "voila", "voilà"
    ]

    /// Évalué EN LOCAL, avant tout appel LLM → un rejet ne coûte rien.
    public static func evaluate(transcript: String, audioDuration: TimeInterval, avgLogProb: Double) -> Verdict {
        if audioDuration < minDuration { return .reject(.tooShort) }
        let lower = transcript.lowercased()
        // Bruit de transcription (hallucinations Whisper sur audio quasi muet). On ne rejette
        // QUE si, une fois la (les) phrase(s) de bruit retirée(s), il ne reste pas de vrai
        // contenu. Sinon une vraie tâche contenant la sous-chaîne (ex "abonnez-vous à la
        // newsletter") serait perdue silencieusement — interdit (jamais perdre une idée).
        if blacklist.contains(where: { lower.contains($0) }) {
            var stripped = lower
            for phrase in blacklist { stripped = stripped.replacingOccurrences(of: phrase, with: " ") }
            let letters: (String) -> Int = { $0.filter(\.isLetter).count }
            let before = letters(lower), after = letters(stripped)
            // Si le bruit couvre la moitié ou plus du texte → vraie hallucination, on rejette.
            // Sinon la phrase de bruit n'est qu'une petite partie d'une vraie tâche → on garde.
            if before == 0 || Double(after) / Double(before) < 0.5 { return .reject(.blacklisted) }
        }
        if avgLogProb < minAvgLogProb { return .reject(.lowConfidence) }

        // Que des mots de remplissage / aucune lettre → rien de concret, on ne dérange pas le LLM.
        let words = lower.split { !$0.isLetter }.map(String.init)
        let meaningful = words.filter { !fillers.contains($0) }
        if meaningful.isEmpty { return .reject(.noContent) }

        return .accept
    }
}
