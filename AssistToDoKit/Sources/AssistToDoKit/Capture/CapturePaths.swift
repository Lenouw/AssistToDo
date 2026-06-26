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
        (try? directory().appendingPathComponent(filename))
            ?? URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
    }

    /// Fichier SwiftData de l'app.
    ///
    /// macOS (non sandboxé) : sous-dossier DÉDIÉ « AssistToDo/ ». JAMAIS le `default.store` à la
    /// racine d'Application Support : ce nom est partagé par TOUTES les apps non-sandboxées qui ne
    /// fixent pas d'URL → une autre app écrase nos données (incident : un store « APIRequest » a
    /// remplacé nos tâches + l'historique des captures).
    ///
    /// iOS (sandboxé) : AUCUNE collision possible (chaque app a son conteneur). On garde donc le
    /// store SwiftData HISTORIQUE de l'app (`Application Support/default.store`, l'emplacement par
    /// défaut quand aucune URL n'était fixée) pour NE PAS orpheliner les données déjà sur l'iPhone
    /// (cache local + journal des captures). Déplacer ce chemin ici les perdrait.
    public static func storeURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        #if os(iOS)
        return base.appendingPathComponent("default.store")
        #else
        let dir = base.appendingPathComponent("AssistToDo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("AssistToDo.store")
        #endif
    }
}
