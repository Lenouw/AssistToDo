# AssistToDo v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App macOS native de capture vocale éclair de tâches : raccourci maintenu → parole transcrite (offline) → parsée par LLM en tâches structurées (date/heure/priorité/tags/notif) → liste du jour avec rollover quotidien et rappels locaux.

**Architecture :** Deux cibles. (1) `AssistToDoCore`, package SwiftPM pur Foundation contenant toute la logique métier testable (modèles, parsing LLM, résolution déterministe des dates, rollover idempotent, garde-fous hallucination) — testé en CLI via `swift test`. (2) App Xcode AppKit/SwiftUI (`.accessory`) qui consomme le core et porte tout l'I/O système : hotkey, audio, WhisperKit, NSPanel HUD, SwiftData, notifications. La logique fragile (TZ/dates/rollover) est verrouillée par des tests unitaires ; l'UI et l'audio sont en build + vérification manuelle.

**Tech Stack :** Swift, SwiftUI, AppKit, SwiftData, WhisperKit, KeyboardShortcuts (sindresorhus), UserNotifications, OpenRouter (`google/gemini-2.5-flash`). Cible macOS 15.5, MacBook Air Apple Silicon.

**Référence du design :** `docs/superpowers/specs/2026-06-10-assisttodo-design.md` (à lire avant de commencer).

---

## File Structure

### Package `AssistToDoCore` (SwiftPM, logique pure, testable CLI)
```
AssistToDoCore/
  Package.swift
  Sources/AssistToDoCore/
    Models/
      TaskRecord.swift          // struct métier (pas SwiftData), Codable
      ParsedTask.swift          // sortie du parsing LLM
      Priority.swift            // enum bas/moyen/haut
    Parsing/
      ParsePromptBuilder.swift  // construit system+user prompt pour OpenRouter
      ParseResponseDecoder.swift// JSON LLM (strip fences, "null"→nil) → [ParsedTask]
    Dates/
      DateResolver.swift        // intention LLM + now + TZ → Date exacte, vérif cohérence
      ParisCalendar.swift       // helpers Europe/Paris (today, startOfDay, weekday)
    Logic/
      RolloverEngine.swift      // rollover idempotent pur (sur [TaskRecord])
      HallucinationFilter.swift // durée min, blacklist FR, seuil confiance
  Tests/AssistToDoCoreTests/
    DateResolverTests.swift
    ParisCalendarTests.swift
    ParseResponseDecoderTests.swift
    RolloverEngineTests.swift
    HallucinationFilterTests.swift
```

### App Xcode `AssistToDo` (cible .app)
```
AssistToDo/
  AssistToDoApp.swift           // @main, NSApplicationDelegateAdaptor, .accessory
  AppDelegate.swift             // cycle de vie, wiring des managers
  Persistence/
    TaskEntity.swift            // @Model SwiftData + VersionedSchema
    SwiftDataTaskStore.swift    // adapte TaskEntity <-> TaskRecord, applique RolloverEngine
  Capture/
    HotkeyManager.swift         // KeyboardShortcuts keyDown/keyUp
    AudioCapture.swift          // AVAudioEngine, tap, niveau RMS, VAD, reconfig device
    Transcriber.swift           // WhisperKit streaming + état "prêt"
  Parsing/
    OpenRouterClient.swift      // POST chat/completions, timeout, clé Keychain
    TaskParser.swift            // orchestre OpenRouterClient + ParseResponseDecoder + DateResolver, fallback brut
  Notifications/
    NotificationManager.swift   // UNUserNotificationCenter schedule/cancel
  UI/
    CapturePanelController.swift// NSPanel non-activating, écran sous curseur
    HUDView.swift               // pastille état, ondes, texte streaming, globe
    ToastController.swift       // aperçu 3s, undo, édition sur interaction
    ToastView.swift
    ListWindowController.swift
    ListView.swift
    MenuBarController.swift     // NSStatusItem + badge
    OnboardingView.swift        // permissions micro+notif, login item, hotkey, clé API
  Support/
    KeychainStore.swift         // clé OpenRouter
    Settings.swift              // UserDefaults (modèle Whisper, hotkey)
    BuildInfo.swift             // date de build affichée
  Resources/
    AssistToDo.entitlements     // micro, app sandbox off (TCC), etc.
    Info.plist                  // LSUIElement=YES, NSMicrophoneUsageDescription
```

---

## Phase 0 — Scaffold

### Task 0.1: Créer le package AssistToDoCore

**Files:**
- Create: `AssistToDoCore/Package.swift`
- Create: `AssistToDoCore/Sources/AssistToDoCore/Placeholder.swift`

- [ ] **Step 1: Écrire `Package.swift`**

```swift
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AssistToDoCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AssistToDoCore", targets: ["AssistToDoCore"])
    ],
    targets: [
        .target(name: "AssistToDoCore"),
        .testTarget(name: "AssistToDoCoreTests", dependencies: ["AssistToDoCore"])
    ]
)
```

- [ ] **Step 2: Fichier placeholder pour compiler**

```swift
// Placeholder.swift
public enum AssistToDoCore {
    public static let version = "0.1.0"
}
```

- [ ] **Step 3: Vérifier que ça build**

Run: `cd AssistToDoCore && swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**

```bash
git add AssistToDoCore
git commit -m "chore: scaffold AssistToDoCore SwiftPM package"
```

---

## Phase 1 — Cœur métier (TDD)

### Task 1.1: Priority + TaskRecord + ParsedTask

**Files:**
- Create: `AssistToDoCore/Sources/AssistToDoCore/Models/Priority.swift`
- Create: `AssistToDoCore/Sources/AssistToDoCore/Models/TaskRecord.swift`
- Create: `AssistToDoCore/Sources/AssistToDoCore/Models/ParsedTask.swift`

- [ ] **Step 1: `Priority.swift`**

```swift
import Foundation

public enum Priority: String, Codable, Sendable, CaseIterable {
    case bas, moyen, haut
}
```

- [ ] **Step 2: `ParsedTask.swift`** (sortie du LLM, avant résolution date)

```swift
import Foundation

public struct ParsedTask: Equatable, Sendable {
    public var text: String
    public var remindAtRaw: String?   // ISO8601 brut renvoyé par le LLM (peut être faux)
    public var dueDateRaw: String?    // "YYYY-MM-DD" brut
    public var priority: Priority?
    public var notify: Bool
    public var tags: [String]

    public init(text: String, remindAtRaw: String? = nil, dueDateRaw: String? = nil,
                priority: Priority? = nil, notify: Bool = false, tags: [String] = []) {
        self.text = text; self.remindAtRaw = remindAtRaw; self.dueDateRaw = dueDateRaw
        self.priority = priority; self.notify = notify; self.tags = tags
    }
}
```

- [ ] **Step 3: `TaskRecord.swift`** (modèle métier persistable)

```swift
import Foundation

public struct TaskRecord: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var createdAt: Date
    public var dueDate: Date?
    public var remindAt: Date?
    public var notify: Bool
    public var notificationId: String?
    public var priority: Priority?
    public var tags: [String]
    public var isDone: Bool
    public var doneAt: Date?
    public var rolloverCount: Int
    public var rawTranscript: String
    public var parseStatus: ParseStatus

    public enum ParseStatus: String, Codable, Sendable { case parsed, rawOnly, pending }

    public init(id: UUID = UUID(), text: String, createdAt: Date, dueDate: Date? = nil,
                remindAt: Date? = nil, notify: Bool = false, notificationId: String? = nil,
                priority: Priority? = nil, tags: [String] = [], isDone: Bool = false,
                doneAt: Date? = nil, rolloverCount: Int = 0, rawTranscript: String = "",
                parseStatus: ParseStatus = .parsed) {
        self.id = id; self.text = text; self.createdAt = createdAt; self.dueDate = dueDate
        self.remindAt = remindAt; self.notify = notify; self.notificationId = notificationId
        self.priority = priority; self.tags = tags; self.isDone = isDone; self.doneAt = doneAt
        self.rolloverCount = rolloverCount; self.rawTranscript = rawTranscript; self.parseStatus = parseStatus
    }
}
```

- [ ] **Step 4: Build**

Run: `cd AssistToDoCore && swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add AssistToDoCore/Sources/AssistToDoCore/Models
git commit -m "feat(core): add Priority, ParsedTask, TaskRecord models"
```

### Task 1.2: ParisCalendar (helpers TZ) — TDD

**Files:**
- Create: `AssistToDoCore/Sources/AssistToDoCore/Dates/ParisCalendar.swift`
- Test: `AssistToDoCore/Tests/AssistToDoCoreTests/ParisCalendarTests.swift`

- [ ] **Step 1: Écrire les tests d'abord**

```swift
import XCTest
@testable import AssistToDoCore

final class ParisCalendarTests: XCTestCase {
    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter(); return f.date(from: iso)!
    }

    func test_today_ete_UTCplus2() {
        // 2026-06-10T23:30:00Z = 2026-06-11 01:30 Paris (été) → jour Paris = 11
        let now = date("2026-06-10T23:30:00Z")
        XCTAssertEqual(ParisCalendar.ymd(for: now), "2026-06-11")
    }

    func test_today_hiver_UTCplus1() {
        // 2026-01-10T23:30:00Z = 2026-01-11 00:30 Paris (hiver) → jour Paris = 11
        let now = date("2026-01-10T23:30:00Z")
        XCTAssertEqual(ParisCalendar.ymd(for: now), "2026-01-11")
    }

    func test_weekday_monday() {
        // 2026-06-15 est un lundi
        let d = date("2026-06-15T10:00:00+02:00")
        XCTAssertEqual(ParisCalendar.weekday(for: d), 2) // 1=dim..7=sam (Calendar)
    }
}
```

- [ ] **Step 2: Lancer, vérifier l'échec**

Run: `cd AssistToDoCore && swift test --filter ParisCalendarTests`
Expected: FAIL (`ParisCalendar` non défini)

- [ ] **Step 3: Implémenter `ParisCalendar.swift`**

```swift
import Foundation

public enum ParisCalendar {
    public static let tz = TimeZone(identifier: "Europe/Paris")!

    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = tz; return c
    }

    /// "YYYY-MM-DD" en wall-clock Paris.
    public static func ymd(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = tz; f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// 1=dimanche .. 7=samedi (convention Calendar).
    public static func weekday(for date: Date) -> Int {
        calendar.component(.weekday, from: date)
    }

    /// Minuit Paris du jour de `date`.
    public static func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
}
```

- [ ] **Step 4: Lancer, vérifier le succès**

Run: `cd AssistToDoCore && swift test --filter ParisCalendarTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add AssistToDoCore/Sources/AssistToDoCore/Dates/ParisCalendar.swift AssistToDoCore/Tests/AssistToDoCoreTests/ParisCalendarTests.swift
git commit -m "feat(core): ParisCalendar TZ helpers with summer/winter tests"
```

### Task 1.3: DateResolver — TDD

Résout l'intention en date/heure exacte Europe/Paris. Le LLM renvoie un `remindAtRaw`/`dueDateRaw` indicatif, mais on **recalcule** et on **corrige** à partir du texte quand un motif est reconnu, et on vérifie la cohérence.

**Files:**
- Create: `AssistToDoCore/Sources/AssistToDoCore/Dates/DateResolver.swift`
- Test: `AssistToDoCore/Tests/AssistToDoCoreTests/DateResolverTests.swift`

- [ ] **Step 1: Écrire les tests**

```swift
import XCTest
@testable import AssistToDoCore

final class DateResolverTests: XCTestCase {
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func test_dans_deux_heures() {
        let now = date("2026-06-10T15:30:00+02:00")
        let r = DateResolver.resolveRemind(text: "appeler le médecin dans deux heures", now: now)
        XCTAssertEqual(r, date("2026-06-10T17:30:00+02:00"))
    }

    func test_dans_une_demi_heure() {
        let now = date("2026-06-10T15:30:00+02:00")
        let r = DateResolver.resolveRemind(text: "dans une demi heure", now: now)
        XCTAssertEqual(r, date("2026-06-10T16:00:00+02:00"))
    }

    func test_a_dix_huit_heures() {
        let now = date("2026-06-10T15:30:00+02:00")
        let r = DateResolver.resolveRemind(text: "à 18h acheter du pain", now: now)
        XCTAssertEqual(r, date("2026-06-10T18:00:00+02:00"))
    }

    func test_lundi_prochain_donne_un_lundi() {
        let now = date("2026-06-10T15:30:00+02:00") // mercredi
        let due = DateResolver.resolveDueDate(text: "lundi prochain envoyer le dossier", now: now)
        XCTAssertEqual(ParisCalendar.ymd(for: due!), "2026-06-15")
        XCTAssertEqual(ParisCalendar.weekday(for: due!), 2) // lundi
    }

    func test_demain() {
        let now = date("2026-06-10T15:30:00+02:00")
        let due = DateResolver.resolveDueDate(text: "demain", now: now)
        XCTAssertEqual(ParisCalendar.ymd(for: due!), "2026-06-11")
    }

    func test_ce_soir_donne_18h() {
        let now = date("2026-06-10T15:30:00+02:00")
        let r = DateResolver.resolveRemind(text: "ce soir", now: now)
        XCTAssertEqual(r, date("2026-06-10T18:00:00+02:00"))
    }

    func test_aucun_motif_retourne_nil() {
        let now = date("2026-06-10T15:30:00+02:00")
        XCTAssertNil(DateResolver.resolveRemind(text: "acheter du pain", now: now))
    }
}
```

- [ ] **Step 2: Lancer, vérifier l'échec**

Run: `cd AssistToDoCore && swift test --filter DateResolverTests`
Expected: FAIL (`DateResolver` non défini)

- [ ] **Step 3: Implémenter `DateResolver.swift`**

```swift
import Foundation

/// Résout des intentions temporelles FR en Date exacte (Europe/Paris).
/// Déterministe : le LLM propose, ce code décide.
public enum DateResolver {
    private static let cal = ParisCalendar.calendar

    private static let weekdays: [String: Int] = [ // 1=dim..7=sam
        "dimanche": 1, "lundi": 2, "mardi": 3, "mercredi": 4,
        "jeudi": 5, "vendredi": 6, "samedi": 7
    ]

    /// Heure de rappel précise si un motif d'heure/délai est présent, sinon nil.
    public static func resolveRemind(text: String, now: Date) -> Date? {
        let t = text.lowercased()

        // "dans X minutes / heures" (gère "une demi heure", chiffres en lettres simples)
        if let delay = parseRelativeDelay(t) {
            return now.addingTimeInterval(delay)
        }
        // "à 18h", "à 9h30"
        if let hm = parseClock(t) {
            return setTime(now: now, hour: hm.0, minute: hm.1)
        }
        // "ce soir" → 18:00
        if t.contains("ce soir") || t.contains("ce soir-là") {
            return setTime(now: now, hour: 18, minute: 0)
        }
        // "ce midi" → 12:00
        if t.contains("ce midi") || t.contains("à midi") {
            return setTime(now: now, hour: 12, minute: 0)
        }
        return nil
    }

    /// Date d'échéance (jour) si un motif de jour est présent, sinon nil.
    public static func resolveDueDate(text: String, now: Date) -> Date? {
        let t = text.lowercased()
        if t.contains("après-demain") || t.contains("apres-demain") {
            return cal.date(byAdding: .day, value: 2, to: ParisCalendar.startOfDay(for: now))
        }
        if t.contains("demain") {
            return cal.date(byAdding: .day, value: 1, to: ParisCalendar.startOfDay(for: now))
        }
        if t.contains("aujourd'hui") || t.contains("aujourdhui") {
            return ParisCalendar.startOfDay(for: now)
        }
        for (name, wd) in weekdays where t.contains(name) {
            return nextWeekday(wd, after: now)
        }
        return nil
    }

    // MARK: - Helpers

    private static func parseRelativeDelay(_ t: String) -> TimeInterval? {
        guard t.contains("dans ") else { return nil }
        if t.contains("demi heure") || t.contains("demi-heure") { return 30 * 60 }
        // nombre en chiffres
        if let n = firstInt(in: t) {
            if t.contains("heure") { return Double(n) * 3600 }
            if t.contains("minute") { return Double(n) * 60 }
        }
        // nombres en lettres usuels
        let words: [String: Int] = ["une": 1, "un": 1, "deux": 2, "trois": 3, "quatre": 4,
                                    "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10]
        for (w, n) in words where t.contains(" \(w) ") {
            if t.contains("heure") { return Double(n) * 3600 }
            if t.contains("minute") { return Double(n) * 60 }
        }
        return nil
    }

    private static func parseClock(_ t: String) -> (Int, Int)? {
        // motifs "18h", "9h30", "18 h", "18:30"
        let pattern = #"(\d{1,2})\s*[h:]\s*(\d{0,2})"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
        let hStr = (t as NSString).substring(with: m.range(at: 1))
        let mStr = (t as NSString).substring(with: m.range(at: 2))
        guard let h = Int(hStr), h < 24 else { return nil }
        let min = Int(mStr) ?? 0
        guard min < 60 else { return nil }
        return (h, min)
    }

    private static func firstInt(in t: String) -> Int? {
        let pattern = #"(\d{1,3})"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
        return Int((t as NSString).substring(with: m.range(at: 1)))
    }

    private static func setTime(now: Date, hour: Int, minute: Int) -> Date {
        cal.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
    }

    /// Prochain jour de semaine strictement après aujourd'hui (Paris).
    private static func nextWeekday(_ target: Int, after now: Date) -> Date {
        let start = ParisCalendar.startOfDay(for: now)
        for offset in 1...7 {
            if let d = cal.date(byAdding: .day, value: offset, to: start),
               ParisCalendar.weekday(for: d) == target {
                return d
            }
        }
        return start
    }
}
```

- [ ] **Step 4: Lancer, vérifier le succès**

Run: `cd AssistToDoCore && swift test --filter DateResolverTests`
Expected: PASS (7 tests)

- [ ] **Step 5: Commit**

```bash
git add AssistToDoCore/Sources/AssistToDoCore/Dates/DateResolver.swift AssistToDoCore/Tests/AssistToDoCoreTests/DateResolverTests.swift
git commit -m "feat(core): deterministic French date/time resolver (Europe/Paris)"
```

### Task 1.4: ParseResponseDecoder — TDD

Décode la réponse JSON du LLM (avec fences ```json, `"null"` strings) en `[ParsedTask]`.

**Files:**
- Create: `AssistToDoCore/Sources/AssistToDoCore/Parsing/ParseResponseDecoder.swift`
- Test: `AssistToDoCore/Tests/AssistToDoCoreTests/ParseResponseDecoderTests.swift`

- [ ] **Step 1: Écrire les tests**

```swift
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
```

- [ ] **Step 2: Lancer, vérifier l'échec**

Run: `cd AssistToDoCore && swift test --filter ParseResponseDecoderTests`
Expected: FAIL

- [ ] **Step 3: Implémenter `ParseResponseDecoder.swift`**

```swift
import Foundation

public enum ParseResponseDecoder {
    struct Wrapper: Decodable { let tasks: [RawTask] }
    struct RawTask: Decodable {
        let text: String
        let remindAt: String?
        let dueDate: String?
        let priority: String?
        let notify: Bool?
        let tags: [String]?
    }

    public enum DecodeError: Error { case noJSON }

    public static func decode(_ raw: String) throws -> [ParsedTask] {
        let json = stripFences(raw)
        guard let data = json.data(using: .utf8) else { throw DecodeError.noJSON }
        let wrapper = try JSONDecoder().decode(Wrapper.self, from: data)
        return wrapper.tasks.map { rt in
            ParsedTask(
                text: rt.text,
                remindAtRaw: nullable(rt.remindAt),
                dueDateRaw: nullable(rt.dueDate),
                priority: Priority(rawValue: nullable(rt.priority) ?? ""),
                notify: rt.notify ?? false,
                tags: rt.tags ?? []
            )
        }
    }

    /// Garde la sous-chaîne entre la première { et la dernière }.
    private static func stripFences(_ s: String) -> String {
        guard let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") else { return s }
        return String(s[start...end])
    }

    /// Traite la string "null" (et vide) comme nil.
    private static func nullable(_ s: String?) -> String? {
        guard let s, !s.isEmpty, s.lowercased() != "null" else { return nil }
        return s
    }
}
```

- [ ] **Step 4: Lancer, vérifier le succès**

Run: `cd AssistToDoCore && swift test --filter ParseResponseDecoderTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add AssistToDoCore/Sources/AssistToDoCore/Parsing/ParseResponseDecoder.swift AssistToDoCore/Tests/AssistToDoCoreTests/ParseResponseDecoderTests.swift
git commit -m "feat(core): decode LLM JSON (fences + null-string handling)"
```

### Task 1.5: ParsePromptBuilder

**Files:**
- Create: `AssistToDoCore/Sources/AssistToDoCore/Parsing/ParsePromptBuilder.swift`
- Test: `AssistToDoCore/Tests/AssistToDoCoreTests/ParsePromptBuilderTests.swift`

- [ ] **Step 1: Test**

```swift
import XCTest
@testable import AssistToDoCore

final class ParsePromptBuilderTests: XCTestCase {
    func test_inclut_le_now_et_demande_json() {
        let now = ISO8601DateFormatter().date(from: "2026-06-10T15:30:00+02:00")!
        let sys = ParsePromptBuilder.systemPrompt(now: now)
        XCTAssertTrue(sys.contains("2026-06-10T15:30:00")) // ancre temporelle
        XCTAssertTrue(sys.lowercased().contains("json"))
        XCTAssertTrue(sys.contains("Europe/Paris"))
    }
}
```

- [ ] **Step 2: Lancer, échec**

Run: `cd AssistToDoCore && swift test --filter ParsePromptBuilderTests`
Expected: FAIL

- [ ] **Step 3: Implémenter**

```swift
import Foundation

public enum ParsePromptBuilder {
    public static func systemPrompt(now: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = ParisCalendar.tz
        f.formatOptions = [.withInternetDateTime]
        let nowStr = f.string(from: now)
        return """
        Tu transformes une phrase dictée en français en tâches JSON.
        Réponds UNIQUEMENT en JSON, sans texte autour, au format :
        {"tasks":[{"text":"...","remindAt":"ISO8601 avec offset ou null","dueDate":"YYYY-MM-DD ou null","priority":"bas|moyen|haut ou null","notify":true|false,"tags":[]}]}
        Maintenant = \(nowStr) (Europe/Paris). Calcule les temps relatifs par rapport à cet instant.
        notify=true uniquement si une heure précise est demandée (ex "dans 2h", "à 18h").
        Découpe les phrases multi-tâches en plusieurs items. Nettoie le texte (orthographe, majuscule initiale).
        Utilise la valeur JSON null (pas la chaîne "null") quand un champ est absent.
        """
    }

    public static func userPrompt(transcript: String) -> String { transcript }
}
```

- [ ] **Step 4: Lancer, succès**

Run: `cd AssistToDoCore && swift test --filter ParsePromptBuilderTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add AssistToDoCore/Sources/AssistToDoCore/Parsing/ParsePromptBuilder.swift AssistToDoCore/Tests/AssistToDoCoreTests/ParsePromptBuilderTests.swift
git commit -m "feat(core): OpenRouter prompt builder with Paris time anchor"
```

### Task 1.6: HallucinationFilter — TDD

**Files:**
- Create: `AssistToDoCore/Sources/AssistToDoCore/Logic/HallucinationFilter.swift`
- Test: `AssistToDoCore/Tests/AssistToDoCoreTests/HallucinationFilterTests.swift`

- [ ] **Step 1: Tests**

```swift
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
```

- [ ] **Step 2: Lancer, échec**

Run: `cd AssistToDoCore && swift test --filter HallucinationFilterTests`
Expected: FAIL

- [ ] **Step 3: Implémenter**

```swift
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
```

- [ ] **Step 4: Lancer, succès**

Run: `cd AssistToDoCore && swift test --filter HallucinationFilterTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add AssistToDoCore/Sources/AssistToDoCore/Logic/HallucinationFilter.swift AssistToDoCore/Tests/AssistToDoCoreTests/HallucinationFilterTests.swift
git commit -m "feat(core): hallucination filter (duration, FR blacklist, confidence)"
```

### Task 1.7: RolloverEngine — TDD

Rollover idempotent pur. Opère sur `[TaskRecord]` + une date "maintenant" + un set des jours déjà roulés. Retourne les tâches mises à jour + le nouveau jour roulé.

**Files:**
- Create: `AssistToDoCore/Sources/AssistToDoCore/Logic/RolloverEngine.swift`
- Test: `AssistToDoCore/Tests/AssistToDoCoreTests/RolloverEngineTests.swift`

- [ ] **Step 1: Tests**

```swift
import XCTest
@testable import AssistToDoCore

final class RolloverEngineTests: XCTestCase {
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func task(due: String, done: Bool = false, rolls: Int = 0) -> TaskRecord {
        TaskRecord(text: "t", createdAt: date("2026-06-09T10:00:00+02:00"),
                   dueDate: date(due), isDone: done, rolloverCount: rolls)
    }

    func test_tache_en_retard_non_faite_roule_a_aujourdhui() {
        let now = date("2026-06-10T09:00:00+02:00")
        let input = [task(due: "2026-06-09T10:00:00+02:00")]
        let out = RolloverEngine.apply(tasks: input, now: now, lastRolloverDay: nil)
        XCTAssertEqual(ParisCalendar.ymd(for: out.tasks[0].dueDate!), "2026-06-10")
        XCTAssertEqual(out.tasks[0].rolloverCount, 1)
        XCTAssertEqual(out.rolledDay, "2026-06-10")
    }

    func test_tache_faite_ne_roule_pas() {
        let now = date("2026-06-10T09:00:00+02:00")
        let input = [task(due: "2026-06-09T10:00:00+02:00", done: true)]
        let out = RolloverEngine.apply(tasks: input, now: now, lastRolloverDay: nil)
        XCTAssertEqual(ParisCalendar.ymd(for: out.tasks[0].dueDate!), "2026-06-09")
        XCTAssertEqual(out.tasks[0].rolloverCount, 0)
    }

    func test_idempotent_meme_jour() {
        let now = date("2026-06-10T09:00:00+02:00")
        let input = [task(due: "2026-06-09T10:00:00+02:00")]
        let out = RolloverEngine.apply(tasks: input, now: now, lastRolloverDay: "2026-06-10")
        // déjà roulé aujourd'hui → aucun changement
        XCTAssertEqual(ParisCalendar.ymd(for: out.tasks[0].dueDate!), "2026-06-09")
        XCTAssertEqual(out.tasks[0].rolloverCount, 0)
    }

    func test_tache_du_jour_ne_roule_pas() {
        let now = date("2026-06-10T09:00:00+02:00")
        let input = [task(due: "2026-06-10T08:00:00+02:00")]
        let out = RolloverEngine.apply(tasks: input, now: now, lastRolloverDay: nil)
        XCTAssertEqual(out.tasks[0].rolloverCount, 0)
    }
}
```

- [ ] **Step 2: Lancer, échec**

Run: `cd AssistToDoCore && swift test --filter RolloverEngineTests`
Expected: FAIL

- [ ] **Step 3: Implémenter**

```swift
import Foundation

public enum RolloverEngine {
    public struct Result: Equatable {
        public let tasks: [TaskRecord]
        public let rolledDay: String?  // jour Paris pour lequel le rollover a été appliqué
    }

    /// Avance à aujourd'hui (Paris) toute tâche non faite dont la dueDate est antérieure.
    /// Idempotent : si `lastRolloverDay` == aujourd'hui, ne fait rien.
    public static func apply(tasks: [TaskRecord], now: Date, lastRolloverDay: String?) -> Result {
        let today = ParisCalendar.ymd(for: now)
        if lastRolloverDay == today {
            return Result(tasks: tasks, rolledDay: today)
        }
        let todayStart = ParisCalendar.startOfDay(for: now)
        var changed = false
        let updated = tasks.map { t -> TaskRecord in
            guard !t.isDone, let due = t.dueDate, due < todayStart else { return t }
            var copy = t
            copy.dueDate = todayStart
            copy.rolloverCount += 1
            changed = true
            return copy
        }
        return Result(tasks: updated, rolledDay: changed ? today : lastRolloverDay)
    }
}
```

- [ ] **Step 4: Lancer, succès**

Run: `cd AssistToDoCore && swift test --filter RolloverEngineTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add AssistToDoCore/Sources/AssistToDoCore/Logic/RolloverEngine.swift AssistToDoCore/Tests/AssistToDoCoreTests/RolloverEngineTests.swift
git commit -m "feat(core): idempotent rollover engine (Europe/Paris)"
```

### Task 1.8: Vérifier toute la suite de tests core

- [ ] **Step 1: Lancer toute la suite**

Run: `cd AssistToDoCore && swift test`
Expected: PASS (tous les tests, ~22)

- [ ] **Step 2: Commit (si ajustements)**

```bash
git add -A && git commit -m "test(core): full suite green" || echo "rien à committer"
```

---

## Phase 2 — App Xcode (build + vérification manuelle)

> Note : la création du projet Xcode et l'ajout des dépendances SwiftPM (WhisperKit, KeyboardShortcuts) se font dans l'IDE. Chaque task ci-dessous se vérifie en lançant l'app (`⌘R`) et en observant le comportement décrit, pas par des tests unitaires (I/O système non testable en CLI).

### Task 2.1: Créer le projet app + intégrer le core

**Files:**
- Create: projet Xcode `AssistToDo.xcodeproj` (cible app macOS, SwiftUI)
- Create: `AssistToDo/AssistToDoApp.swift`, `AssistToDo/AppDelegate.swift`
- Create: `AssistToDo/Support/BuildInfo.swift`
- Modify: `Info.plist` (LSUIElement=YES)

- [ ] **Step 1:** Dans Xcode, New Project → macOS → App → SwiftUI, nom `AssistToDo`, dans le dossier racine. Ajouter le package local `AssistToDoCore` (File → Add Package Dependencies → Add Local) et les packages distants `https://github.com/argmaxinc/WhisperKit` et `https://github.com/sindresorhus/KeyboardShortcuts`.

- [ ] **Step 2:** `Info.plist` : ajouter `Application is agent (UIElement)` = `YES` (LSUIElement). Ajouter `Privacy - Microphone Usage Description` = "AssistToDo enregistre votre voix pour créer des tâches.".

- [ ] **Step 3:** `BuildInfo.swift` :

```swift
import Foundation
enum BuildInfo {
    static let date: String = {
        let f = DateFormatter(); f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.locale = Locale(identifier: "fr_FR"); f.dateFormat = "d MMM HH:mm"
        return f.string(from: Date())
    }()
}
```

- [ ] **Step 4:** `AssistToDoApp.swift` minimal qui pose l'app en `.accessory` via AppDelegate, sans fenêtre principale.

```swift
import SwiftUI
@main
struct AssistToDoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { Settings { EmptyView() } }
}
```

```swift
import AppKit
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
```

- [ ] **Step 5: Vérifier** : `⌘R`. L'app lance sans icône Dock ni fenêtre. Pas de crash. `import AssistToDoCore` compile (ajouter un `_ = AssistToDoCore.version` temporaire dans `applicationDidFinishLaunching` pour le prouver, puis retirer).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(app): scaffold .accessory app linking AssistToDoCore"
```

### Task 2.2: MenuBarController + persistance SwiftData + liste

**Files:**
- Create: `AssistToDo/Persistence/TaskEntity.swift`, `AssistToDo/Persistence/SwiftDataTaskStore.swift`
- Create: `AssistToDo/UI/MenuBarController.swift`, `AssistToDo/UI/ListWindowController.swift`, `AssistToDo/UI/ListView.swift`

- [ ] **Step 1:** `TaskEntity.swift` : `@Model` miroir de `TaskRecord`, avec `VersionedSchema` v1, + conversions `toRecord()` / `init(record:)`.
- [ ] **Step 2:** `SwiftDataTaskStore.swift` : ouvre le `ModelContainer`, expose `allTasks()`, `add(_ records:)`, `toggleDone(id:)`, `runRolloverIfNeeded()` (lit `lastRolloverDay` depuis UserDefaults, appelle `RolloverEngine.apply`, persiste, met à jour UserDefaults).
- [ ] **Step 3:** `MenuBarController.swift` : `NSStatusItem`, titre = badge (nb tâches non faites du jour), menu → ouvre la liste, item Réglages, item Quitter.
- [ ] **Step 4:** `ListView.swift` : liste SwiftUI des tâches du jour, cases à cocher (toggle → `toggleDone`), barré quand fait, affichage heure/priorité/tags, repère "zombie" si `rolloverCount >= 3`. Affiche `BuildInfo.date` en bas en petit.
- [ ] **Step 5: Vérifier** : `⌘R`. Insérer manuellement 2 `TaskRecord` au lancement (code temporaire). Le badge menu-bar montre le compte. Ouvrir la liste, cocher une tâche → barrée + badge décrémente. Relancer l'app → l'état persiste (SwiftData). Retirer le code d'insertion temporaire.
- [ ] **Step 6: Vérifier rollover** : créer une tâche avec `dueDate` = hier, relancer → elle apparaît aujourd'hui, `rolloverCount` = 1. Relancer encore → pas de double incrément (idempotent).
- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat(app): SwiftData store, menu bar, day list with rollover"
```

### Task 2.3: HotkeyManager + CapturePanel + HUDView (sans audio)

**Files:**
- Create: `AssistToDo/Capture/HotkeyManager.swift`
- Create: `AssistToDo/UI/CapturePanelController.swift`, `AssistToDo/UI/HUDView.swift`

- [ ] **Step 1:** `HotkeyManager.swift` : déclare `KeyboardShortcuts.Name("capture")`, défaut `⌃⌥Space`. S'abonne à `onKeyDown` et `onKeyUp` et expose deux closures `onPressStart` / `onPressEnd`. (cf. design : keyUp global vérifié supporté)
- [ ] **Step 2:** `CapturePanelController.swift` : `NSPanel` `.nonactivatingPanel`, `isFloatingPanel = true`, `level = .floating`, sans titre, non-key par défaut. Positionne au centre de l'écran **contenant le curseur** (`NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }`). Méthodes `show()` / `hide()`. Pré-crée le panel une fois (réutilisé).
- [ ] **Step 3:** `HUDView.swift` : SwiftUI hébergé via `NSHostingView`. Affiche : pastille d'état (`.notReady` gris / `.ready` vert / `.listening` animé / `.transcribing`) avec **libellé texte** (accessibilité), zone d'ondes (placeholder statique pour l'instant), zone texte streaming (vide pour l'instant), icône globe (gris pour l'instant). État piloté par un `@ObservedObject` `CaptureViewModel`.
- [ ] **Step 4: Vérifier** : `⌘R`. Maintien `⌃⌥Space` → le HUD apparaît au centre de l'écran sous la souris en < ~100 ms, **sans voler le focus** (vérifier : garder une autre app active avec un curseur de texte clignotant, le curseur ne doit pas disparaître). Relâcher → le HUD se ferme. Multi-écran : déplacer la souris sur l'autre écran, redéclencher → HUD sur le bon écran.
- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(app): global hotkey + non-activating capture panel + HUD shell"
```

### Task 2.4: AudioCapture + ondes live + VAD

**Files:**
- Create: `AssistToDo/Capture/AudioCapture.swift`

- [ ] **Step 1:** `AudioCapture.swift` : `AVAudioEngine`, installe un tap sur `inputNode`. Calcule le **niveau RMS** par buffer (pour les ondes) publié via Combine `@Published var level: Float`. Accumule un flag `didDetectSpeech` (VAD simple : un buffer dépasse un seuil RMS). Démarre sur `start()` (appelé au keyDown), `stop()` au keyUp retourne `(buffers, duration, didDetectSpeech)`. Gère `AVAudioEngineConfigurationChange` (notification) en reconfigurant le tap sans crash.
- [ ] **Step 2:** Brancher `level` aux ondes du `HUDView` (remplacer le placeholder par une vraie waveform animée pilotée par `level`).
- [ ] **Step 3:** Demander la permission micro **uniquement** si pas encore accordée, et le faire à l'onboarding (Task 2.7) — ici, supposer accordée pour tester (l'accorder à la main au 1er prompt système).
- [ ] **Step 4: Vérifier** : `⌘R`, maintien du raccourci, parler → les ondes du HUD bougent en rythme avec la voix. Rester silencieux → ondes plates. Relâcher après silence → log console "didDetectSpeech=false". Brancher des AirPods pendant le maintien → pas de crash.
- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat(app): live audio capture, RMS waveform, VAD"
```

### Task 2.5: Transcriber (WhisperKit streaming) + état prêt + garde-fous

**Files:**
- Create: `AssistToDo/Capture/Transcriber.swift`
- Create: `AssistToDo/Support/Settings.swift`

- [ ] **Step 1:** `Settings.swift` : `whisperModel` (défaut `"base"`) dans UserDefaults.
- [ ] **Step 2:** `Transcriber.swift` : initialise `WhisperKit` avec le modèle choisi **au lancement de l'app** (pré-chargement), publie `@Published var isReady`. Méthode streaming : pendant la capture, transcrit en continu et publie `@Published var partialText` (branché au HUD). À la finalisation (keyUp), retourne le texte final + `avgLogProb`. Applique `HallucinationFilter.evaluate(transcript:audioDuration:avgLogProb:)`.
- [ ] **Step 3:** La pastille "Prêt" du HUD = `audioReady && transcriber.isReady`. Tant que le modèle charge, pastille grise + libellé "Chargement…".
- [ ] **Step 4:** Brancher `partialText` → zone texte streaming du HUD (le texte apparaît au fil de la parole).
- [ ] **Step 5: Vérifier** : `⌘R`. Au lancement, attendre que la pastille passe verte (modèle chargé). Maintien + parler une phrase FR → le texte s'affiche en streaming dans le HUD. Relâcher → texte final loggé. Tester une phrase d'1 mot très courte → rejet `tooShort` loggé. Mesurer à la main la latence relâche→texte final (noter pour le benchmark Task 3.1).
- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat(app): WhisperKit streaming transcriber + readiness + guards"
```

### Task 2.6: OpenRouterClient + TaskParser + Toast + commit de tâche

**Files:**
- Create: `AssistToDo/Parsing/OpenRouterClient.swift`, `AssistToDo/Parsing/TaskParser.swift`
- Create: `AssistToDo/Support/KeychainStore.swift`
- Create: `AssistToDo/UI/ToastController.swift`, `AssistToDo/UI/ToastView.swift`
- Create: `AssistToDo/Notifications/NotificationManager.swift`

- [ ] **Step 1:** `KeychainStore.swift` : get/set de `OPENROUTER_API_KEY` (Keychain). Au premier lancement en dev, lire la clé depuis l'env/`.env` si présente et la pousser en Keychain (helper de dev), sinon saisie à l'onboarding.
- [ ] **Step 2:** `OpenRouterClient.swift` : `POST https://openrouter.ai/api/v1/chat/completions`, modèle `google/gemini-2.5-flash`, `temperature: 0`, timeout 8s, header `Authorization: Bearer <clé>`. Retourne le `content` string. Erreur réseau → throw.
- [ ] **Step 3:** `TaskParser.swift` : orchestre — `ParsePromptBuilder.systemPrompt(now:)` + transcript → `OpenRouterClient` → `ParseResponseDecoder.decode` → pour chaque `ParsedTask`, construire un `TaskRecord` : `dueDate`/`remindAt` = **`DateResolver` d'abord** (déterministe) sinon parse du `*Raw` LLM en fallback ; `parseStatus = .parsed`. Si l'appel échoue/timeout → un seul `TaskRecord` brut (`text = transcript`, `parseStatus = .rawOnly`, `notify = false`). **Jamais d'exception propagée qui perdrait la tâche.**
- [ ] **Step 4:** `NotificationManager.swift` : `requestAuthorization` (appelé à l'onboarding), `schedule(for record:)` si `record.notify && record.remindAt` futur → crée une `UNCalendarNotificationTrigger`/`UNTimeIntervalNotificationTrigger`, stocke l'id dans `record.notificationId`. `cancel(id:)`.
- [ ] **Step 5:** `ToastController.swift` + `ToastView.swift` : à la fin du flow, afficher en haut-droite un toast ~3s listant la/les tâche(s) + date/heure résolue (+ icône cloche si notify). Non-key par défaut → auto-commit (insert via `SwiftDataTaskStore.add`) à 3s. Clic/hover → éditable (devient key, focus assumé). Re-presser le raccourci dans la fenêtre des 3s → undo (ne pas committer / supprimer). Toast rouge si `HallucinationFilter` a rejeté pour `tooShort`/`blacklisted` ("Rien entendu / transcription ratée"), toast orange si audio gardé sans transcription.
- [ ] **Step 6:** Câbler le flow complet dans `AppDelegate` : keyDown → `AudioCapture.start` + `CapturePanel.show` ; keyUp → `CapturePanel.hide` + `AudioCapture.stop` → si pas de speech → toast rouge ; sinon `Transcriber` finalise → filtre → `TaskParser.parse` → `NotificationManager.schedule` → `ToastController.show`.
- [ ] **Step 7: Vérifier** (le test d'intégration clé) : `⌘R`. Maintien, dire « rappelle-moi d'appeler le médecin dans deux heures, c'est important ». Relâcher. Attendu : toast en haut-droite « Appeler le médecin · 🔔 17:30 · priorité haut », auto-commit après 3s, la tâche apparaît dans la liste, et une notification macOS arrive ~2h plus tard (pour tester vite, dire « dans une minute »). Tester offline (couper le wifi) : la tâche est quand même créée en texte brut. Tester l'undo : re-presser le raccourci pendant le toast → pas de tâche créée.
- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "feat(app): OpenRouter parsing, deterministic dates, notifications, toast commit"
```

### Task 2.7: Onboarding + login item + saisie clé

**Files:**
- Create: `AssistToDo/UI/OnboardingView.swift`

- [ ] **Step 1:** `OnboardingView.swift` : fenêtre affichée au premier lancement (flag `didOnboard` en UserDefaults). Étapes : (1) explique le raccourci + permet de le changer (`KeyboardShortcuts.Recorder`), (2) demande la permission micro (`AVCaptureDevice.requestAccess`), (3) demande la permission notifications (`NotificationManager.requestAuthorization`), (4) propose "Ouvrir au démarrage" (`SMAppService.mainApp.register()`), (5) champ pour coller la clé OpenRouter → Keychain.
- [ ] **Step 2:** `ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "capture")` pendant la capture pour éviter l'App Nap de l'AVAudioEngine.
- [ ] **Step 3: Vérifier** : supprimer le flag `didOnboard` (ou réinstaller propre), relancer → l'onboarding s'affiche, accorder micro + notifs, activer le login item, coller la clé. Vérifier ensuite qu'une capture complète marche de bout en bout sans re-demander de permission. Vérifier dans Réglages Système → Général → Ouverture que l'app est listée.
- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat(app): onboarding (permissions, login item, API key)"
```

---

## Phase 3 — Finitions & validation

### Task 3.1: Benchmark des modèles Whisper sur le MacBook Air réel

- [ ] **Step 1:** Ajouter un sélecteur de modèle dans les Réglages (`tiny`/`base`/`small`).
- [ ] **Step 2:** Pour chaque modèle, dicter 3 phrases types FR (courte, moyenne, avec heure) et noter : latence relâche→texte, justesse FR, RAM (Activity Monitor). Consigner dans `docs/superpowers/benchmarks-whisper.md`.
- [ ] **Step 3:** Choisir le modèle par défaut selon le compromis sur **ton** Air. Mettre à jour `Settings` + le spec si différent de `base`.
- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "perf: whisper model benchmark on target Air, set default"
```

### Task 3.2: Validation rollover été/hiver de bout en bout

- [ ] **Step 1:** Vérifier que `swift test` couvre déjà été (UTC+2) et hiver (UTC+1) (Tasks 1.2/1.7). 
- [ ] **Step 2:** Test manuel : régler l'horloge système à 23:58 un soir d'été, laisser passer minuit app ouverte → la liste roule à minuit. Fermer l'app avant minuit, rouvrir le lendemain → roule au lancement. Remettre l'horloge.
- [ ] **Step 3: Commit** (si correctifs)

```bash
git add -A && git commit -m "test: end-to-end rollover validation summer/winter" || echo "rien à committer"
```

### Task 3.3: Désinstallation propre (règle CLAUDE.md app native)

- [ ] **Step 1:** Vérifier que l'app ne modifie aucun `defaults` système global ni process système. Tout est dans son conteneur SwiftData + UserDefaults app + Keychain.
- [ ] **Step 2:** Documenter dans le README la procédure de désinstallation (supprimer l'app, retirer le login item, où vit le store, comment purger la clé Keychain).
- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "docs: clean uninstall procedure"
```

### Task 3.4: Mise à jour du suivi projet

- [ ] **Step 1:** Mettre à jour `CONTEXT.md` (sections « Ce qu'on a fait », « Où on en est », cocher les tâches).
- [ ] **Step 2: Commit**

```bash
git add CONTEXT.md && git commit -m "docs: update CONTEXT.md after v1"
```

---

## Notes d'implémentation transverses

- **Timezone** : tout calcul de date/heure passe par `ParisCalendar` / `DateResolver`. Jamais `Calendar.current` ni `Date()` comparé en UTC implicite. (règle CLAUDE.md, incidents DST passés)
- **Données sensibles** : aucune valeur (clé API incluse) n'est jamais en dur dans le code ni inventée. Clé en Keychain, fournie par l'utilisateur. (règle CLAUDE.md)
- **OpenRouter** : modèle `google/gemini-2.5-flash` vérifié via l'API le 2026-06-10. Si changement de modèle, re-tester l'ID avant intégration.
- **Pas de tiret long** dans les textes visibles (toasts, libellés, onboarding). (règle CLAUDE.md)
- **App native** : aucun `killall` de process système ; désinstallation sans trace (Task 3.3).
- **Verification before completion** : aucune task marquée faite sans la vérification décrite (test vert ou comportement observé).
```
