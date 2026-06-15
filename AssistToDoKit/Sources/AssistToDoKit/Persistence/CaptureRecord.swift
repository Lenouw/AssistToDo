import Foundation
import SwiftData

/// Journal d'une capture vocale. L'audio (audioFilename) est la source de vérité.
@Model
public final class CaptureRecord {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var audioFilename: String
    public var durationSec: Double
    public var statusRaw: String
    public var transcript: String?
    public var transcriptModel: String?
    public var parsedSummary: String?
    public var producedTaskIdStrings: [String]
    public var needsEnrichment: Bool
    public var lastError: String?
    public var attempts: Int

    public init(id: UUID, createdAt: Date, audioFilename: String, durationSec: Double) {
        self.id = id; self.createdAt = createdAt; self.updatedAt = createdAt
        self.audioFilename = audioFilename; self.durationSec = durationSec
        self.statusRaw = CaptureStatus.recorded.raw
        self.transcript = nil; self.transcriptModel = nil; self.parsedSummary = nil
        self.producedTaskIdStrings = []; self.needsEnrichment = false
        self.lastError = nil; self.attempts = 0
    }

    public var status: CaptureStatus {
        get { CaptureStatus(raw: statusRaw) }
        set { statusRaw = newValue.raw; updatedAt = Date() }
    }
    public var producedTaskIds: [UUID] {
        get { producedTaskIdStrings.compactMap(UUID.init) }
        set { producedTaskIdStrings = newValue.map(\.uuidString) }
    }
}
