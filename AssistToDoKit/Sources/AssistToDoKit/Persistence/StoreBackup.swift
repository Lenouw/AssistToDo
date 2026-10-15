//
//  StoreBackup.swift
//  AssistToDoKit
//
//  Filet de sécurité de la base SwiftData. Deux usages :
//  1. `snapshotIfAppUpdated` : copie la base AVANT de l'ouvrir, une fois par nouvelle version
//     de l'app (c'est à ce moment-là qu'une migration de schéma peut mal tourner).
//  2. `quarantine` : si la migration échoue malgré tout, la base est DÉPLACÉE dans les
//     sauvegardes au lieu d'être effacée. On repart propre sans jamais rien détruire.
//

import Foundation

public enum StoreBackup {
    static let keep = 3
    static let lastBuildKey = "storeBackupLastBuild"

    /// Les 3 fichiers d'une base SQLite SwiftData (`x.store`, `x.store-shm`, `x.store-wal`).
    static func files(of store: URL) -> [URL] {
        [store,
         URL(fileURLWithPath: store.path + "-shm"),
         URL(fileURLWithPath: store.path + "-wal")]
    }

    static func backupsDir(for store: URL) -> URL {
        store.deletingLastPathComponent().appendingPathComponent("Sauvegardes", isDirectory: true)
    }

    /// Version courante de l'app (« 1.2.0 (7) »), sert de clé « déjà sauvegardé pour cette version ».
    public static var currentBuild: String {
        let i = Bundle.main.infoDictionary
        let v = i?["CFBundleShortVersionString"] as? String ?? "?"
        let b = i?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }

    /// Copie la base si l'app vient d'être mise à jour. Ne fait rien au premier lancement
    /// (pas de base) ni pour une version déjà sauvegardée. Garde les 3 dernières sauvegardes.
    @discardableResult
    public static func snapshotIfAppUpdated(store: URL, defaults: UserDefaults = .standard,
                                            build: String = currentBuild) -> URL? {
        guard defaults.string(forKey: lastBuildKey) != build else { return nil }
        guard FileManager.default.fileExists(atPath: store.path) else {
            defaults.set(build, forKey: lastBuildKey)
            return nil
        }
        let dest = copy(store: store, label: "avant-\(build)")
        if dest != nil { defaults.set(build, forKey: lastBuildKey) }
        return dest
    }

    /// Déplace une base illisible dans les sauvegardes (au lieu de la supprimer).
    @discardableResult
    public static func quarantine(store: URL) -> URL? {
        let dir = backupsDir(for: store).appendingPathComponent("\(stamp())-echec-migration", isDirectory: true)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for f in files(of: store) where fm.fileExists(atPath: f.path) {
                try fm.moveItem(at: f, to: dir.appendingPathComponent(f.lastPathComponent))
            }
            return dir
        } catch {
            print("StoreBackup.quarantine : \(error)")
            return nil
        }
    }

    static func copy(store: URL, label: String) -> URL? {
        let safe = label.replacingOccurrences(of: "[^A-Za-z0-9.()_-]", with: "-", options: .regularExpression)
        let dir = backupsDir(for: store).appendingPathComponent("\(stamp())-\(safe)", isDirectory: true)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            for f in files(of: store) where fm.fileExists(atPath: f.path) {
                try fm.copyItem(at: f, to: dir.appendingPathComponent(f.lastPathComponent))
            }
            prune(backupsDir(for: store))
            return dir
        } catch {
            print("StoreBackup.copy : \(error)")
            return nil
        }
    }

    /// Ne garde que les `keep` sauvegardes « avant-… » les plus récentes (les quarantaines restent).
    static func prune(_ dir: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
        let snaps = items.filter { $0.contains("-avant-") }.sorted()
        for old in snaps.dropLast(keep) {
            try? fm.removeItem(at: dir.appendingPathComponent(old))
        }
    }

    static func stamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f.string(from: Date())
    }
}
