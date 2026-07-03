//
//  ModelProvisioner.swift
//  AssistToDo
//
//  Approvisionne le modèle de transcription GGML (large-v3-turbo q8_0) depuis NOTRE release GitHub
//  (pas HuggingFace), UNE seule fois. whisper.cpp le charge ensuite par mmap (offline, ~1 s, aucune
//  compilation). Fichier unique .bin → pas de dézip. Intégrité vérifiée par SHA256.
//

import Foundation
import CryptoKit

enum ModelProvisioner {
    // Asset stable + son SHA256 attendu.
    private static let turboURL = URL(string: "https://github.com/Lenouw/AssistToDo/releases/download/models-turbo-ggml-v1/ggml-large-v3-turbo-q8_0.bin")!
    private static let turboSHA = "317eb69c11673c9de1e1f0d459b253999804ec71ac4c23c17ecf5fbe24e259a1"
    private static let turboName = "ggml-large-v3-turbo-q8_0.bin"

    private static func modelsRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("AssistToDo/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Renvoie le chemin local du `.bin` turbo, en le téléchargeant depuis notre GitHub (avec
    /// progression 0…1 + vérif SHA256) s'il n'est pas déjà là. `nil` si le provisionnement échoue.
    static func ensureTurbo(progress: @escaping @Sendable (Double) -> Void) async -> URL? {
        let dest = modelsRoot().appendingPathComponent(turboName)
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { return dest }   // déjà là → offline direct, pas de réseau

        guard let downloaded = await Downloader(dest: dest, onProgress: progress).run(url: turboURL) else { return nil }
        guard sha256File(downloaded) == turboSHA else { try? fm.removeItem(at: downloaded); return nil }
        return downloaded
    }

    private static func sha256File(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Télécharge un gros fichier avec progression fiable (delegate) et déplace le résultat SYNCHRONE
/// (le fichier temporaire d'URLSession est supprimé dès le retour du callback).
private final class Downloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let dest: URL
    private let onProgress: @Sendable (Double) -> Void
    private var cont: CheckedContinuation<URL?, Never>?

    init(dest: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.dest = dest; self.onProgress = onProgress
    }

    func run(url: URL) async -> URL? {
        await withCheckedContinuation { c in
            self.cont = c
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let ok: Bool
        if (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 {
            try? FileManager.default.removeItem(at: dest)
            ok = ((try? FileManager.default.moveItem(at: location, to: dest)) != nil)
        } else { ok = false }
        cont?.resume(returning: ok ? dest : nil); cont = nil
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard error != nil, cont != nil else { return }   // succès déjà géré dans didFinishDownloadingTo
        cont?.resume(returning: nil); cont = nil
        session.finishTasksAndInvalidate()
    }
}
