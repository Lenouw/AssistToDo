import Foundation

public enum HallucinationFilter {
    public enum Reason: Equatable { case tooShort, blacklisted, lowConfidence }
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

    public static func evaluate(transcript: String, audioDuration: TimeInterval, avgLogProb: Double) -> Verdict {
        if audioDuration < minDuration { return .reject(.tooShort) }
        let lower = transcript.lowercased()
        if blacklist.contains(where: { lower.contains($0) }) { return .reject(.blacklisted) }
        if avgLogProb < minAvgLogProb { return .reject(.lowConfidence) }
        return .accept
    }
}
