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
}
