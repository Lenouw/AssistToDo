import Foundation
import SwiftData

@MainActor
public final class CaptureStore: ObservableObject {
    public let container: ModelContainer
    private var context: ModelContext { container.mainContext }

    @Published public private(set) var captures: [CaptureRecord] = []

    public init(inMemory: Bool = false) throws {
        let schema = Schema(versionedSchema: AssistToDoSchemaV1.self)
        let config = inMemory
            ? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            : ModelConfiguration(schema: schema, url: CapturePaths.storeURL())
        container = try ModelContainer(for: schema, configurations: config)
        reload()
    }

    /// Partage le ModelContainer d'un autre store (TaskStore) au lieu d'ouvrir une 2ᵉ connexion
    /// sur le MÊME fichier. Deux containers sur un même .store = course au verrou SQLite au
    /// démarrage → échec INTERMITTENT d'ouverture (incident device 2026-07-02 : journal des
    /// captures en repli mémoire silencieux, captures « disparues »). Un seul container = fiable.
    public init(sharing container: ModelContainer) {
        self.container = container
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

    /// Captures à (re)traiter automatiquement : jamais traitées (modèle pas prêt à la capture),
    /// échec transcription/LLM/routage, ou texte brut à enrichir.
    ///
    /// ⚠️ GARDE-FOUS (incident 2026-07-02) : le rejeu automatique est limité aux captures RÉCENTES
    /// (< 48 h) et peu tentées (< 3). Sans ça, de VIEUX audios de test (« ferme le studio demain… »)
    /// ont été rejoués des jours plus tard → création d'événements calendrier fantômes à chaque
    /// ouverture de l'app. Les captures plus anciennes restent rejouables MANUELLEMENT (écran
    /// Captures), jamais automatiquement.
    public func needingProcessing() -> [CaptureRecord] {
        let cutoff = Date().addingTimeInterval(-48 * 3600)
        return captures.filter { r in
            guard r.createdAt > cutoff, r.attempts < 3 else { return false }
            if r.needsEnrichment { return true }
            switch r.status {
            case .recorded:
                // Audio capté alors que le modèle de transcription n'était pas encore prêt
                // (lancement à froid) → à transcrire dès que possible. Aucune idée perdue.
                return true
            case .failed(let stage, _):
                return stage == "transcription" || stage == "llm" || stage == "routing"
            default:
                return false
            }
        }
    }

    public func delete(id: UUID) {
        let all = (try? context.fetch(FetchDescriptor<CaptureRecord>())) ?? []
        guard let r = all.first(where: { $0.id == id }) else { return }
        context.delete(r); save(); reload()
    }

    /// Supprime le FICHIER audio des captures `done` plus vieilles que `days` (la métadonnée reste).
    /// `days <= 0` = rétention indéfinie (ne purge rien).
    public func purgeAudio(olderThanDays days: Int) {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let all = (try? context.fetch(FetchDescriptor<CaptureRecord>())) ?? []
        var changed = false
        for r in all where r.status == .done && r.createdAt < cutoff && !r.audioFilename.isEmpty {
            try? FileManager.default.removeItem(at: CapturePaths.url(for: r.audioFilename))
            r.audioFilename = ""
            changed = true
        }
        if changed { save(); reload() }
    }

    private func save() { try? context.save() }
}
