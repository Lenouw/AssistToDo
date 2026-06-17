import Foundation

/// État du pipeline d'une capture. Persisté en String (`raw`) dans SwiftData.
public enum CaptureStatus: Equatable, Sendable {
    case recorded
    case transcribing
    case transcribed
    case routing
    case done
    case failed(stage: String, reason: String)   // stage ∈ transcription|llm|routing

    public var raw: String {
        switch self {
        case .recorded: return "recorded"
        case .transcribing: return "transcribing"
        case .transcribed: return "transcribed"
        case .routing: return "routing"
        case .done: return "done"
        case .failed(let s, let r): return "failed:\(s):\(r)"
        }
    }

    public init(raw: String) {
        if raw.hasPrefix("failed:") {
            let parts = raw.split(separator: ":", maxSplits: 2).map(String.init)
            self = .failed(stage: parts.count > 1 ? parts[1] : "?", reason: parts.count > 2 ? parts[2] : "?")
            return
        }
        switch raw {
        case "transcribing": self = .transcribing
        case "transcribed": self = .transcribed
        case "routing": self = .routing
        case "done": self = .done
        default: self = .recorded
        }
    }
}
