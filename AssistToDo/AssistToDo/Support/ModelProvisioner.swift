//
//  ModelProvisioner.swift
//  AssistToDo
//
//  Approvisionne le modèle de transcription « small » depuis NOTRE release GitHub (pas HuggingFace),
//  UNE seule fois, vers un dossier stable. Ensuite WhisperKit le charge en offline total
//  (download:false). L'app reste légère (le modèle n'est PAS bundlé → auto-updates rapides).
//

import Foundation
import CryptoKit

enum ModelProvisioner {
    // Asset stable (indépendant des versions de l'app) + son SHA256 attendu (intégrité).
    private static let smallURL = URL(string: "https://github.com/Lenouw/AssistToDo/releases/download/models-small-v1/whisper-small.zip")!
    private static let smallSHA = "df739138a4e8cdea6f56f0712747bda3b9199f2b15272de29897f3ad24944788"

    /// Dossier local des modèles provisionnés (hors cache HuggingFace).
    private static func modelsRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("AssistToDo/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Renvoie (modelFolder, tokenizerFolder) pour « small », en le téléchargeant depuis GitHub +
    /// vérifiant le SHA256 s'il n'est pas déjà là. `nil` si le provisionnement échoue.
    static func ensureSmall() async -> (modelFolder: String, tokenizerFolder: URL)? {
        let dir = modelsRoot().appendingPathComponent("whisper-small", isDirectory: true)
        let model = dir.appendingPathComponent("model/openai_whisper-small", isDirectory: true)
        let tokenizer = dir.appendingPathComponent("tokenizer", isDirectory: true)
        let fm = FileManager.default

        // Déjà présent (fichiers clés) → offline direct, pas de réseau.
        if fm.fileExists(atPath: model.appendingPathComponent("config.json").path),
           fm.fileExists(atPath: tokenizer.appendingPathComponent("tokenizer.json").path) {
            return (model.path, tokenizer)
        }

        // Télécharge le zip depuis GitHub.
        let zip: URL
        do {
            let (tmp, resp) = try await URLSession.shared.download(from: smallURL)
            guard (resp as? HTTPURLResponse)?.statusCode == 200 else { try? fm.removeItem(at: tmp); return nil }
            zip = tmp
        } catch { return nil }

        // Vérifie l'intégrité (SHA256 en streaming, pas tout en mémoire).
        guard sha256File(zip) == smallSHA else { try? fm.removeItem(at: zip); return nil }

        // Dézippe dans le dossier stable.
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-xk", zip.path, dir.path]
        do { try p.run(); p.waitUntilExit() } catch { return nil }
        try? fm.removeItem(at: zip)

        guard fm.fileExists(atPath: model.appendingPathComponent("config.json").path) else { return nil }
        return (model.path, tokenizer)
    }

    private static func sha256File(_ url: URL) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var hasher = SHA256()
        while let chunk = try? h.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
