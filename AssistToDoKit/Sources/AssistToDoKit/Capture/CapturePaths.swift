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

    /// Fichier SwiftData de l'app, dans un sous-dossier DÉDIÉ « AssistToDo/ ».
    /// JAMAIS le `default.store` à la racine d'Application Support : ce nom est partagé par
    /// TOUTES les apps non-sandboxées qui ne fixent pas d'URL → une autre app écrase nos données
    /// (incident vu : un store « APIRequest » a remplacé nos tâches + l'historique des captures).
    public static func storeURL() -> URL {
        #if os(iOS)
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        #endif
        let dir = base.appendingPathComponent("AssistToDo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("AssistToDo.store")
    }
}
