import Foundation
import SwiftData

@MainActor
public final class CaptureStore: ObservableObject {
    public let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    @Published public private(set) var captures: [CaptureRecord] = []

    public init(inMemory: Bool = false) throws {
        let schema = Schema(versionedSchema: AssistToDoSchemaV1.self)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: schema, configurations: config)
        reload()
    }

    public func reload() {
        captures = (try? context.fetch(FetchDescriptor<CaptureRecord>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))) ?? []
    }

    @discardableResult
    public func record(audioFilename: String, durationSec: Double) -> CaptureRecord {
        let r = CaptureRecord(id: UUID(), createdAt: Date(), audioFilename: audioFilename, durationSec: durationSec)
        context.insert(r); save(); reload()
        return r
    }

    public func update(id: UUID, _ mutate: (CaptureRecord) -> Void) {
        let all = (try? context.fetch(FetchDescriptor<CaptureRecord>())) ?? []
        guard let r = all.first(where: { $0.id == id }) else { return }
        mutate(r); save(); reload()
    }

    /// Captures à (re)traiter automatiquement : échec LLM/routage, ou texte brut à enrichir.
    public func needingProcessing() -> [CaptureRecord] {
        captures.filter { r in
            if r.needsEnrichment { return true }
            if case .failed(let stage, _) = r.status, stage == "llm" || stage == "routing" { return true }
            return false
        }
    }

    public func delete(id: UUID) {
        let all = (try? context.fetch(FetchDescriptor<CaptureRecord>())) ?? []
        guard let r = all.first(where: { $0.id == id }) else { return }
        context.delete(r); save(); reload()
    }

    private func save() { try? context.save() }
}
