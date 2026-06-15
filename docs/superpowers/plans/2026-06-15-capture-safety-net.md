# Capture Safety Net Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Garantir qu'aucune idée dictée n'est jamais perdue : audio sauvegardé durablement avant tout traitement, journal de captures persistant, pipeline rejouable (re-transcription + re-routage), manuel et automatique.

**Architecture:** Le journal (`CaptureRecord` + `CaptureStore`), le dossier audio durable et l'étage transcription vivent dans le package partagé `AssistToDoKit` (Mac + iPhone). Le **routage** (création EKEvent/EKReminder/Notes/local) reste spécifique à chaque plateforme et est **injecté** dans le processeur partagé via une closure. Le pipeline est une machine à états pilotée par le statut de `CaptureRecord`.

**Tech Stack:** Swift, SwiftData, WhisperKit (transcription locale), `AssistToDoCore` (parsing LLM déterministe), XCTest (tests Kit in-memory).

**Coordination iOS :** ce plan touche lourdement `AssistToDoKit` (partagé). Lire `ASSISTTODO-HANDOFF.md` avant de commencer, logger chaque tâche Kit, et prévoir des merges `feat/assisttodo-v1` ↔ `feat/ios`. Les tâches sont additives autant que possible.

---

## File Structure

- `AssistToDoKit/Sources/AssistToDoKit/Capture/CaptureStatus.swift` — **créer** : enum d'état du pipeline.
- `AssistToDoKit/Sources/AssistToDoKit/Persistence/CaptureRecord.swift` — **créer** : `@Model` SwiftData (journal).
- `AssistToDoKit/Sources/AssistToDoKit/Persistence/TaskEntity.swift` — **modifier** : ajouter `CaptureRecord` au schéma versionné.
- `AssistToDoKit/Sources/AssistToDoKit/Persistence/CaptureStore.swift` — **créer** : CRUD + requêtes par statut (+ `init(inMemory:)`).
- `AssistToDoKit/Sources/AssistToDoKit/Capture/CapturePaths.swift` — **créer** : dossier audio durable.
- `AssistToDoKit/Sources/AssistToDoKit/Capture/AudioCapture.swift` — **modifier** : écrire dans le dossier durable.
- `AssistToDoKit/Sources/AssistToDoKit/Capture/CaptureProcessor.swift` — **créer** : pipeline partagé (transcription + filtre + parse), routage injecté.
- `AssistToDoKit/Sources/AssistToDoKit/Support/PreferencesService.swift` — **modifier** : réglage rétention.
- `AssistToDo/AssistToD­o/Capture/CaptureCoordinator.swift` — **modifier** : utiliser `CaptureStore` + `CaptureProcessor`, fournir le routage Mac.
- `AssistToDo/AssistToDo/UI/CapturesView.swift` — **créer** : écran « Captures » macOS.
- `AssistToDoKit/Tests/AssistToDoKitTests/CaptureStoreTests.swift` — **créer**.
- `AssistToDoKit/Tests/AssistToDoKitTests/CaptureProcessorTests.swift` — **créer**.

L'app iPhone (`AssistToDoiOS`, branche `feat/ios`) adopte `CaptureStore`/`CaptureProcessor` + son propre écran Captures dans une tâche miroir côté iOS (hors de ce plan Mac, coordonnée via handoff).

---

## Task 1: `CaptureStatus` (états du pipeline)

**Files:**
- Create: `AssistToDoKit/Sources/AssistToDoKit/Capture/CaptureStatus.swift`
- Test: `AssistToDoKit/Tests/AssistToDoKitTests/CaptureStoreTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AssistToDoKit

final class CaptureStoreTests: XCTestCase {
    func test_status_roundtrips_through_raw() {
        XCTAssertEqual(CaptureStatus(raw: "done"), .done)
        XCTAssertEqual(CaptureStatus(raw: "failed:llm:timeout").raw, "failed:llm:timeout")
        XCTAssertEqual(CaptureStatus(raw: "garbage"), .recorded) // défaut sûr
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd AssistToDoKit && swift test --filter CaptureStoreTests/test_status_roundtrips_through_raw`
Expected: FAIL (CaptureStatus introuvable).

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// État du pipeline d'une capture. Persisté en String (`raw`) dans SwiftData.
public enum CaptureStatus: Equatable, Sendable {
    case recorded            // audio écrit, rien d'autre (point de non-perte)
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd AssistToDoKit && swift test --filter CaptureStoreTests/test_status_roundtrips_through_raw`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AssistToDoKit/Sources/AssistToDoKit/Capture/CaptureStatus.swift AssistToDoKit/Tests/AssistToDoKitTests/CaptureStoreTests.swift
git commit -m "feat(capture): CaptureStatus (états du pipeline, persistance String)"
```

---

## Task 2: Modèle `CaptureRecord` + schéma

**Files:**
- Create: `AssistToDoKit/Sources/AssistToDoKit/Persistence/CaptureRecord.swift`
- Modify: `AssistToDoKit/Sources/AssistToDoKit/Persistence/TaskEntity.swift:13-16` (ajouter au schéma)

- [ ] **Step 1: Write the failing test** (append to `CaptureStoreTests.swift`)

```swift
    func test_captureRecord_defaults_to_recorded() {
        let r = CaptureRecord(id: UUID(), createdAt: Date(), audioFilename: "a.caf", durationSec: 2)
        XCTAssertEqual(CaptureStatus(raw: r.statusRaw), .recorded)
        XCTAssertEqual(r.attempts, 0)
        XCTAssertNil(r.transcript)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd AssistToDoKit && swift test --filter CaptureStoreTests/test_captureRecord_defaults_to_recorded`
Expected: FAIL (CaptureRecord introuvable).

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import SwiftData

/// Journal d'une capture vocale. L'audio (audioFilename) est la source de vérité.
@Model
public final class CaptureRecord {
    @Attribute(.unique) public var id: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var audioFilename: String           // relatif au dossier Captures (CapturePaths)
    public var durationSec: Double
    public var statusRaw: String
    public var transcript: String?
    public var transcriptModel: String?
    public var parsedSummary: String?
    public var producedTaskIdStrings: [String]  // UUID des items créés (traçabilité + idempotence)
    public var needsEnrichment: Bool            // LLM jamais passé (créé en texte brut hors-ligne)
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
```

- [ ] **Step 4: Add `CaptureRecord` to the versioned schema**

Modify `AssistToDoKit/Sources/AssistToDoKit/Persistence/TaskEntity.swift:13-16` :

```swift
enum AssistToDoSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [TaskEntity.self, CaptureRecord.self] }
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd AssistToDoKit && swift test --filter CaptureStoreTests/test_captureRecord_defaults_to_recorded`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add AssistToDoKit/Sources/AssistToDoKit/Persistence/CaptureRecord.swift AssistToDoKit/Sources/AssistToDoKit/Persistence/TaskEntity.swift AssistToDoKit/Tests/AssistToDoKitTests/CaptureStoreTests.swift
git commit -m "feat(capture): modèle CaptureRecord (journal) + ajout au schéma SwiftData"
```

---

## Task 3: `CaptureStore` (CRUD + requêtes par statut)

**Files:**
- Create: `AssistToDoKit/Sources/AssistToDoKit/Persistence/CaptureStore.swift`
- Test: `AssistToDoKit/Tests/AssistToDoKitTests/CaptureStoreTests.swift`

> Pattern d'`init(inMemory:)` : suivre celui déjà ajouté sur `TaskStore` (seam de test in-memory). Voir `TaskStore.init(inMemory:)`.

- [ ] **Step 1: Write the failing test** (append)

```swift
    @MainActor
    func test_store_creates_and_queries_pending() throws {
        let store = try CaptureStore(inMemory: true)
        let id = store.record(audioFilename: "x.caf", durationSec: 3).id
        XCTAssertEqual(store.all().count, 1)

        store.update(id: id) { $0.status = .transcribed; $0.needsEnrichment = true }
        let pending = store.needingProcessing()
        XCTAssertEqual(pending.map(\.id), [id])

        store.update(id: id) { $0.status = .done; $0.needsEnrichment = false }
        XCTAssertTrue(store.needingProcessing().isEmpty)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd AssistToDoKit && swift test --filter CaptureStoreTests/test_store_creates_and_queries_pending`
Expected: FAIL (CaptureStore introuvable).

- [ ] **Step 3: Write minimal implementation**

```swift
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
        guard let r = captures.first(where: { $0.id == id })
            ?? (try? context.fetch(FetchDescriptor<CaptureRecord>())).flatMap({ $0.first(where: { $0.id == id }) })
        else { return }
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
        guard let r = captures.first(where: { $0.id == id }) else { return }
        context.delete(r); save(); reload()
    }

    private func save() { try? context.save() }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd AssistToDoKit && swift test --filter CaptureStoreTests`
Expected: PASS (tous).

- [ ] **Step 5: Commit**

```bash
git add AssistToDoKit/Sources/AssistToDoKit/Persistence/CaptureStore.swift AssistToDoKit/Tests/AssistToDoKitTests/CaptureStoreTests.swift
git commit -m "feat(capture): CaptureStore (journal CRUD + needingProcessing, seam in-memory)"
```

---

## Task 4: `CapturePaths` (dossier audio durable) + écriture par `AudioCapture`

**Files:**
- Create: `AssistToDoKit/Sources/AssistToDoKit/Capture/CapturePaths.swift`
- Modify: `AssistToDoKit/Sources/AssistToDoKit/Capture/AudioCapture.swift:164-165` (URL de sortie)

- [ ] **Step 1: Write the failing test** (append to CaptureStoreTests)

```swift
    func test_capturePaths_directory_is_persistent_and_exists() throws {
        let dir = try CapturePaths.directory()
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path))
        XCTAssertFalse(dir.path.contains("/tmp/"))           // pas le dossier temp
        let url = CapturePaths.url(for: "test.caf")
        XCTAssertEqual(url.lastPathComponent, "test.caf")
        XCTAssertEqual(url.deletingLastPathComponent().path, dir.path)
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd AssistToDoKit && swift test --filter CaptureStoreTests/test_capturePaths_directory_is_persistent_and_exists`
Expected: FAIL (CapturePaths introuvable).

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// Dossier durable des audios de capture (Application Support sur Mac, Documents sur iOS).
/// JAMAIS temporaryDirectory (qui se vide).
public enum CapturePaths {
    public static func directory() throws -> URL {
        #if os(iOS)
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #endif
        let dir = base.appendingPathComponent("Captures", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    public static func url(for filename: String) -> URL {
        (try? directory().appendingPathComponent(filename)) ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
    }
}
```

- [ ] **Step 4: Point `AudioCapture` to the durable folder**

Modify `AudioCapture.swift` `writeNormalizedFile` — remplacer la ligne 164-165 :

```swift
        let filename = "assisttodo-\(UUID().uuidString).caf"
        let url = CapturePaths.url(for: filename)
```

- [ ] **Step 5: Run tests + build**

Run: `cd AssistToDoKit && swift test --filter CaptureStoreTests`
Then: `cd .. && xcodebuild -project AssistToDo/AssistToDo.xcodeproj -scheme AssistToDo -configuration Debug -destination 'platform=macOS' build`
Expected: tests PASS, BUILD SUCCEEDED.

- [ ] **Step 6: Commit**

```bash
git add AssistToDoKit/Sources/AssistToDoKit/Capture/CapturePaths.swift AssistToDoKit/Sources/AssistToDoKit/Capture/AudioCapture.swift AssistToDoKit/Tests/AssistToDoKitTests/CaptureStoreTests.swift
git commit -m "feat(capture): audio écrit dans un dossier durable (CapturePaths), plus le dossier temp"
```

---

## Task 5: `CaptureProcessor` (pipeline partagé, routage injecté)

**Files:**
- Create: `AssistToDoKit/Sources/AssistToDoKit/Capture/CaptureProcessor.swift`
- Test: `AssistToDoKit/Tests/AssistToDoKitTests/CaptureProcessorTests.swift`

But : un objet partagé qui, depuis un `CaptureRecord` + le chemin audio, exécute transcription → filtre → parse, met à jour le statut, et délègue le **routage** (création des items) à une closure fournie par la plateforme. Idempotent : avant de router, on note les `producedTaskIds` précédents pour que la plateforme les supprime (re-traitement).

Interfaces injectées (protocoles, pour testabilité) :

```swift
public protocol AudioTranscribing { var isReady: Bool { get }
    func transcribe(path: String) async -> (text: String, avgLogProb: Float)? }
public protocol TaskRouting {   // implémenté par chaque plateforme (Mac: EventKit+Notes ; iOS: EventKit+in-app)
    /// Crée les items pour ces tâches routées, supprime `replacing`, retourne les nouveaux ids.
    func route(_ tasks: [RoutedTask], replacing previous: [UUID]) async -> [UUID] }
```

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import AssistToDoKit
@testable import AssistToDoCore

final class CaptureProcessorTests: XCTestCase {
    struct FakeTranscriber: AudioTranscribing {
        let ready: Bool; let text: String
        var isReady: Bool { ready }
        func transcribe(path: String) async -> (text: String, avgLogProb: Float)? {
            ready ? (text, -0.2) : nil
        }
    }
    final class FakeRouter: TaskRouting {
        var routed: [RoutedTask] = []; var replaced: [UUID] = []
        func route(_ tasks: [RoutedTask], replacing previous: [UUID]) async -> [UUID] {
            routed = tasks; replaced = previous; return tasks.map { _ in UUID() }
        }
    }

    @MainActor
    func test_transcription_failure_keeps_audio_and_marks_failed() async throws {
        let store = try CaptureStore(inMemory: true)
        let rec = store.record(audioFilename: "x.caf", durationSec: 3)
        let proc = CaptureProcessor(store: store,
                                    transcriber: FakeTranscriber(ready: false, text: ""),
                                    parser: TaskParser(client: OpenRouterClient(model: "x")),
                                    router: FakeRouter())
        await proc.process(captureId: rec.id, now: Date())
        store.reload()
        if case .failed(let stage, _) = store.all().first!.status { XCTAssertEqual(stage, "transcription") }
        else { XCTFail("devrait être failed:transcription") }
    }

    @MainActor
    func test_success_routes_and_marks_done() async throws {
        let store = try CaptureStore(inMemory: true)
        let rec = store.record(audioFilename: "x.caf", durationSec: 3)
        let router = FakeRouter()
        // parser stubbé via OpenRouterClient ne sera pas appelé : on force le filtre à accepter et on
        // simule un transcript ; le parse réel fait un fallback texte brut si le réseau échoue -> 1 item local.
        let proc = CaptureProcessor(store: store,
                                    transcriber: FakeTranscriber(ready: true, text: "Penser à appeler le plombier"),
                                    parser: TaskParser(client: OpenRouterClient(model: "x")),
                                    router: router)
        await proc.process(captureId: rec.id, now: Date())
        store.reload()
        let r = store.all().first!
        XCTAssertEqual(r.transcript, "Penser à appeler le plombier")
        XCTAssertFalse(router.routed.isEmpty)         // au moins le fallback texte brut
        XCTAssertEqual(r.status, .done)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd AssistToDoKit && swift test --filter CaptureProcessorTests`
Expected: FAIL (CaptureProcessor / protocoles introuvables).

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation
import AssistToDoCore

@MainActor
public final class CaptureProcessor {
    private let store: CaptureStore
    private let transcriber: AudioTranscribing
    private let parser: TaskParser
    private let router: TaskRouting

    public init(store: CaptureStore, transcriber: AudioTranscribing, parser: TaskParser, router: TaskRouting) {
        self.store = store; self.transcriber = transcriber; self.parser = parser; self.router = router
    }

    /// Exécute (ou rejoue) le pipeline complet pour une capture depuis son audio.
    public func process(captureId: UUID, now: Date) async {
        guard let rec = store.all().first(where: { $0.id == captureId }) else { return }
        let audioPath = CapturePaths.url(for: rec.audioFilename).path
        let previous = rec.producedTaskIds
        store.update(id: captureId) { $0.status = .transcribing; $0.attempts += 1 }

        // 1) Transcription locale
        guard transcriber.isReady, let t = await transcriber.transcribe(path: audioPath) else {
            store.update(id: captureId) { $0.status = .failed(stage: "transcription", reason: "indisponible"); $0.lastError = "transcription indisponible" }
            return
        }
        store.update(id: captureId) { $0.transcript = t.text; $0.status = .transcribed }

        // 2) Garde-fou local
        let verdict = HallucinationFilter.evaluate(transcript: t.text, audioDuration: rec.durationSec, avgLogProb: Double(t.avgLogProb))
        if case .reject = verdict {
            store.update(id: captureId) { $0.status = .done; $0.parsedSummary = "(ignoré : bruit)" }
            return
        }

        // 3) Parse LLM (fallback texte brut intégré au parser si réseau KO)
        store.update(id: captureId) { $0.status = .routing }
        let routed = await parser.parse(transcript: t.text, now: now)
        let producedSummary = routed.first?.record.text
        let needsEnrich = routed.contains { $0.record.parseStatus == .rawOnly }

        // 4) Routage injecté (plateforme) — supprime les items précédents (idempotence)
        let newIds = await router.route(routed, replacing: previous)
        store.update(id: captureId) {
            $0.producedTaskIds = newIds
            $0.parsedSummary = producedSummary
            $0.needsEnrichment = needsEnrich
            $0.status = .done
        }
    }
}
```

> Note : `TaskParser.parse(...)` doit exposer une surcharge sans `calendars/reminderLists/customRules` (valeurs par défaut déjà présentes). `HallucinationFilter` et `Destination`/`RoutedTask` viennent de `AssistToDoCore`/Kit.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd AssistToDoKit && swift test --filter CaptureProcessorTests`
Expected: PASS (le 2e test passe via fallback texte brut : sans réseau, `parser.parse` renvoie 1 item local `.rawOnly`, donc `router.routed` non vide et `status == .done`).

- [ ] **Step 5: Commit**

```bash
git add AssistToDoKit/Sources/AssistToDoKit/Capture/CaptureProcessor.swift AssistToDoKit/Tests/AssistToDoKitTests/CaptureProcessorTests.swift
git commit -m "feat(capture): CaptureProcessor (pipeline partagé rejouable, routage injecté, idempotent)"
```

---

## Task 6: Brancher le Mac sur `CaptureStore` + `CaptureProcessor`

**Files:**
- Modify: `AssistToDo/AssistToDo/Capture/CaptureCoordinator.swift`

But : conformer le routage Mac existant à `TaskRouting`, créer un `CaptureRecord` à chaque capture, faire passer le pipeline par `CaptureProcessor`. Le routage Mac = l'actuel `route()` (EventKit + NotesService + local) refactoré pour : créer les items, supprimer `replacing`, retourner les ids.

- [ ] **Step 1: Conformer le routage Mac**

Extraire l'actuel corps de `route(transcript:)` dans un type `MacTaskRouter: TaskRouting` (même logique : calendar/reminders/notes/local + `store.add`), avec en plus, au début, suppression des `previous` via `store.delete(id:)`. Signature :

```swift
func route(_ tasks: [RoutedTask], replacing previous: [UUID]) async -> [UUID]
```

- [ ] **Step 2: Créer le CaptureRecord à la capture**

Dans `end()`, après `audio.stop()` qui renvoie `result.fileURL` (désormais dans le dossier durable) :

```swift
let filename = result.fileURL?.lastPathComponent ?? ""
let rec = captureStore.record(audioFilename: filename, durationSec: result.duration)
await processor.process(captureId: rec.id, now: Date())
```

- [ ] **Step 3: Build + test manuel**

Run: `xcodebuild -project AssistToDo/AssistToDo.xcodeproj -scheme AssistToDo -configuration Debug -destination 'platform=macOS' build`
Expected: BUILD SUCCEEDED. Test : capture → tâche créée + 1 `CaptureRecord` `done` en base.

- [ ] **Step 4: Commit**

```bash
git add AssistToDo/AssistToDo/Capture/CaptureCoordinator.swift
git commit -m "refactor(capture): Mac branché sur CaptureStore + CaptureProcessor (routage Mac = TaskRouting)"
```

---

## Task 7: Re-enrichissement automatique

**Files:**
- Modify: `AssistToDo/AssistToDo/Capture/CaptureCoordinator.swift` (ou `AppDelegate`)

- [ ] **Step 1: Au lancement + au retour réseau, rejouer les captures en attente**

```swift
func reprocessPending() {
    for rec in captureStore.needingProcessing() {
        Task { await processor.process(captureId: rec.id, now: Date()) }
    }
}
```
Appeler `reprocessPending()` dans `applicationDidFinishLaunching` et sur notification de retour réseau (`NWPathMonitor`).

- [ ] **Step 2: Build + commit**

```bash
xcodebuild -project AssistToDo/AssistToDo.xcodeproj -scheme AssistToDo -configuration Debug -destination 'platform=macOS' build
git add AssistToDo/AssistToDo/Capture/CaptureCoordinator.swift AssistToDo/AssistToDo/AppDelegate.swift
git commit -m "feat(capture): re-enrichissement auto des captures en attente (lancement + retour réseau)"
```

---

## Task 8: Écran « Captures » macOS (historique + re-traitement)

**Files:**
- Create: `AssistToDo/AssistToDo/UI/CapturesView.swift`
- Modify: `AssistToDo/AssistToDo/UI/MenuBarController.swift` (entrée de menu « Captures »)

- [ ] **Step 1: Vue liste**

`CapturesView` observe `captureStore.captures` : chaque ligne montre date, statut (icône), `parsedSummary` ou `transcript`, et un bouton lecture audio (`AVAudioPlayer` sur `CapturePaths.url(for:)`). Actions par swipe/menu :
- **Re-traiter** → `processor.process(captureId:now:)`.
- **Re-router seulement** → variante `processor.reroute(captureId:)` (réutilise `transcript` existant, saute la transcription) — ajouter cette méthode à `CaptureProcessor` (copie de `process` qui part de l'état `transcribed`).
- **Écouter** / **Supprimer** (`captureStore.delete` + suppression du fichier audio).

- [ ] **Step 2: Build + test manuel**

Run: `xcodebuild ... build` ; ouvrir Captures, re-traiter la capture de l'incident → vérifier qu'elle devient un événement calendrier.

- [ ] **Step 3: Commit**

```bash
git add AssistToDo/AssistToDo/UI/CapturesView.swift AssistToDo/AssistToDo/UI/MenuBarController.swift AssistToDoKit/Sources/AssistToDoKit/Capture/CaptureProcessor.swift
git commit -m "feat(capture): écran Captures macOS (historique, écouter, re-traiter, re-router)"
```

---

## Task 9: Rétention (réglage + nettoyage)

**Files:**
- Modify: `AssistToDoKit/Sources/AssistToDoKit/Persistence/CaptureStore.swift` (purge)
- Modify: `AssistToDo/AssistToDo/UI/SettingsView.swift` (réglage)

- [ ] **Step 1: Test purge**

```swift
    @MainActor
    func test_purge_removes_done_audio_older_than_retention() throws {
        let store = try CaptureStore(inMemory: true)
        let old = store.record(audioFilename: "old.caf", durationSec: 1)
        store.update(id: old.id) { $0.status = .done; $0.createdAt = Date().addingTimeInterval(-40*86400) }
        store.purgeAudio(olderThanDays: 30)
        // métadonnée gardée, audio marqué supprimé
        XCTAssertTrue(store.all().first!.audioFilename.isEmpty)
    }
```

- [ ] **Step 2: Implémenter `purgeAudio(olderThanDays:)`** dans `CaptureStore` : pour chaque capture `.done` dont `createdAt` dépasse le délai, supprimer le fichier (`CapturePaths.url`), vider `audioFilename`. Appeler au lancement avec le réglage (`@AppStorage("captureRetentionDays")`, défaut 30 ; 0 = indéfini → ne rien purger).

- [ ] **Step 3: Réglage** dans `SettingsView` : `Stepper`/`Picker` « Garder les audios … » (7 / 30 / 90 / indéfini).

- [ ] **Step 4: Test + build + commit**

```bash
cd AssistToDoKit && swift test --filter CaptureStoreTests/test_purge_removes_done_audio_older_than_retention && cd ..
xcodebuild -project AssistToDo/AssistToDo.xcodeproj -scheme AssistToDo -configuration Debug -destination 'platform=macOS' build
git add -A && git commit -m "feat(capture): rétention audio (réglage N jours / indéfini + purge auto)"
```

---

## Task 10 (coordination) : adoption iOS

Hors de ce plan Mac. Dans le worktree `feat/ios` : merger `feat/assisttodo-v1`, conformer le routage iOS à `TaskRouting`, brancher `CaptureController` sur `CaptureStore`/`CaptureProcessor`, créer l'écran Captures iOS. Logger dans `ASSISTTODO-HANDOFF.md`.

---

## Self-Review

- **Couverture spec** : audio durable (T4) ✓ ; journal (T2/T3) ✓ ; machine à états (T1/T5) ✓ ; hors-ligne/fallback (T5, via `parser.parse` rawOnly + `needsEnrichment`) ✓ ; re-enrichissement auto (T7) ✓ ; écran Captures + re-traiter/re-router (T8) ✓ ; rétention (T9) ✓ ; local-first (aucun upload) ✓ ; idempotence (`producedTaskIds` + `replacing`) ✓.
- **Cohérence types** : `CaptureStatus`/`status`, `CaptureStore.record/update/needingProcessing/delete/purgeAudio`, `CaptureProcessor.process/reroute`, `TaskRouting.route(_:replacing:)`, `AudioTranscribing.transcribe` — cohérents entre tâches.
- **Placeholders** : aucun « TODO/TBD » ; code fourni pour les unités testables ; UI (T8) décrite précisément (action par action) car non-TDD par nature.
- **Risque** : `TaskParser.parse` doit avoir une surcharge à arguments par défaut (déjà le cas). `MacTaskRouter` réutilise le `route()` existant — refactor, pas réécriture.
