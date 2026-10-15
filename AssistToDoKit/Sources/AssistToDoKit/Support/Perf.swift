//
//  Perf.swift
//  AssistToDoKit
//
//  Mesure du démarrage et de la capture. Deux sorties :
//  - os_signpost (sous-système com.assisttodo, catégorie Perf) pour Instruments ;
//  - un journal des derniers passages (Application Support/Perf/runs.json), affiché dans
//    l'app (Réglages > Mesures) : l'iPhone ne peut pas toujours être lu depuis le Mac.
//
//  Toutes les dates sont en millisecondes depuis le lancement du processus.
//

import Foundation
import os

public enum PerfStep: String, Codable, CaseIterable, Sendable {
    // Lancement
    case processStart, appInitStart, storeOpened, appInitEnd, firstFrame, foreground
    case modelProvisioned, modelInitStart, modelInitEnd, modelWarm
    // Capture
    case trigger, sheetShown, micPermission, audioEngineStarted, micFirstBuffer
    case captureStop, transcriptionStart, transcriptionEnd, routingEnd

    /// Libellé lisible par Florian dans l'écran Mesures.
    public var label: String {
        switch self {
        case .processStart:       return "Processus lancé"
        case .appInitStart:       return "Démarrage du code de l'app"
        case .storeOpened:        return "Base de données ouverte"
        case .appInitEnd:         return "App initialisée"
        case .firstFrame:         return "App affichée"
        case .foreground:         return "App au premier plan"
        case .modelProvisioned:   return "Fichier du modèle trouvé"
        case .modelInitStart:     return "Chargement du modèle (début)"
        case .modelInitEnd:       return "Modèle prêt"
        case .modelWarm:          return "Modèle préchauffé"
        case .trigger:            return "Signal de capture reçu"
        case .sheetShown:         return "Écran de capture ouvert"
        case .micPermission:      return "Autorisation micro vérifiée"
        case .audioEngineStarted: return "Moteur audio démarré"
        case .micFirstBuffer:     return "Micro enregistre vraiment"
        case .captureStop:        return "Fin de dictée"
        case .transcriptionStart: return "Transcription (début)"
        case .transcriptionEnd:   return "Transcription finie"
        case .routingEnd:         return "Routage OpenRouter fini"
        }
    }
}

public struct PerfEntry: Codable, Hashable, Sendable {
    public let step: PerfStep
    public let ms: Double            // depuis le lancement du processus
    public let note: String?
}

public struct PerfRun: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let trigger: String       // « bouton », « URL », « intent »…
    public let cold: Bool            // l'app venait d'être lancée par ce signal
    public let prewarmed: Bool       // processus préchauffé par iOS avant le tap
    public let referenceMs: Double   // origine du tableau : lancement (froid) ou tap (app en mémoire)
    public var entries: [PerfEntry]
    public var outcome: String?

    /// Temps d'une étape depuis l'origine (tap ou lancement), nil si absente.
    public func elapsed(_ step: PerfStep) -> Double? {
        entries.first { $0.step == step }.map { $0.ms - referenceMs }
    }
}

public enum Perf {
    private static let signposter = OSSignposter(subsystem: "com.assisttodo", category: "Perf")
    private static let lock = NSLock()
    nonisolated(unsafe) private static var launchEntries: [PerfEntry] = []
    nonisolated(unsafe) private static var current: PerfRun?
    nonisolated(unsafe) private static var markedOnce: Set<PerfStep> = []

    /// Instant de lancement du processus (sysctl), à défaut le premier appel à Perf.
    public static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        if sysctl(&mib, 4, &info, &size, nil, 0) == 0 {
            let tv = info.kp_proc.p_un.__p_starttime
            return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
        }
        return Date()
    }()

    /// iOS peut lancer le processus à l'avance (préchauffage) : le lancement n'est alors pas le tap.
    public static let prewarmed = ProcessInfo.processInfo.environment["ActivePrewarm"] == "1"

    public static func nowMs() -> Double { Date().timeIntervalSince(processStart) * 1000 }

    /// Repère ponctuel. `once` : ignoré s'il a déjà été posé dans ce processus (premier rendu…).
    public static func mark(_ step: PerfStep, note: String? = nil, once: Bool = false) {
        let ms = nowMs()
        signposter.emitEvent("step", "\(step.rawValue, privacy: .public) \(ms, format: .fixed(precision: 0)) ms")
        lock.lock(); defer { lock.unlock() }
        if once {
            guard !markedOnce.contains(step) else { return }
            markedOnce.insert(step)
        }
        let e = PerfEntry(step: step, ms: ms, note: note)
        if current != nil {
            if !(current!.entries.contains { $0.step == step }) { current!.entries.append(e) }
        } else {
            launchEntries.append(e)
        }
    }

    /// Intervalle mesuré (signpost begin/end) + deux repères dans le journal.
    @discardableResult
    public static func measure<T>(_ start: PerfStep, _ end: PerfStep, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval("interval", id: signposter.makeSignpostID(), "\(start.rawValue, privacy: .public)")
        mark(start)
        defer { mark(end); signposter.endInterval("interval", state) }
        return try body()
    }

    /// Ouvre un passage de capture. Froid = signal reçu moins de 10 s après le démarrage du code.
    public static func beginCapture(trigger: String, modelReady: Bool) {
        let ms = nowMs()
        lock.lock()
        let appStart = launchEntries.first { $0.step == .appInitStart }?.ms ?? 0
        let cold = ms - appStart < 10_000 && !(markedOnce.contains(.trigger))
        let reference: Double = cold ? (prewarmed ? appStart : 0) : ms
        var entries: [PerfEntry] = cold ? [PerfEntry(step: .processStart, ms: 0, note: nil)] + launchEntries : []
        entries.append(PerfEntry(step: .trigger, ms: ms, note: trigger))
        if modelReady && !cold { entries.append(PerfEntry(step: .modelInitEnd, ms: ms, note: "déjà prêt")) }
        markedOnce.insert(.trigger)
        current = PerfRun(id: UUID(), date: Date(), trigger: trigger, cold: cold, prewarmed: prewarmed,
                          referenceMs: reference, entries: entries, outcome: nil)
        lock.unlock()
        signposter.emitEvent("capture", "trigger \(trigger, privacy: .public) cold=\(cold)")
    }

    /// Clôt le passage en cours et l'ajoute au journal (20 derniers conservés).
    public static func finishCapture(outcome: String) {
        lock.lock()
        guard var run = current else { lock.unlock(); return }
        current = nil
        lock.unlock()
        run.outcome = outcome
        var runs = loadRuns()
        runs.insert(run, at: 0)
        save(Array(runs.prefix(20)))
    }

    /// Le passage en cours a-t-il déjà ce repère ? (pour ne marquer que la 1ʳᵉ trame audio)
    public static func currentHas(_ step: PerfStep) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return current?.entries.contains { $0.step == step } ?? false
    }

    // MARK: - Journal

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Perf", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("runs.json")
    }

    public static func loadRuns() -> [PerfRun] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([PerfRun].self, from: data)) ?? []
    }

    public static func clearRuns() { try? FileManager.default.removeItem(at: fileURL) }

    private static func save(_ runs: [PerfRun]) {
        if let data = try? JSONEncoder().encode(runs) { try? data.write(to: fileURL, options: .atomic) }
    }

    /// Tableau texte d'un passage (pour « Copier » dans l'écran Mesures).
    public static func text(_ run: PerfRun) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "fr_FR"); df.timeZone = TimeZone(identifier: "Europe/Paris")
        df.dateFormat = "d MMM HH:mm:ss"
        var lines = ["\(df.string(from: run.date)), \(run.cold ? "à froid" : "app en mémoire"), signal : \(run.trigger)\(run.prewarmed ? ", préchauffée par iOS" : "")"]
        for e in run.entries.sorted(by: { $0.ms < $1.ms }) {
            let t = Int((e.ms - run.referenceMs).rounded())
            lines.append("\(e.step.label) : \(t) ms\(e.note.map { " (\($0))" } ?? "")")
        }
        if let o = run.outcome { lines.append("Résultat : \(o)") }
        return lines.joined(separator: "\n")
    }
}
