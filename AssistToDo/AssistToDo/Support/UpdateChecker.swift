//
//  UpdateChecker.swift
//  AssistToDo
//
//  Auto-update interne : interroge l'API GitHub Releases, et si une version plus récente
//  existe, propose de l'INSTALLER directement (télécharge le .zip de l'app, remplace le
//  bundle dans son emplacement actuel, relance). Possible car l'app n'est PAS sandboxée.
//

import Foundation
import AppKit
import CryptoKit

enum UpdateChecker {
    static let repo = "Lenouw/AssistToDo"

    enum UpdateError: Error { case noAppInZip, checksumMismatch, checksumMissing, bundleMismatch }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// `manual` = déclenché depuis les Réglages (affiche aussi "à jour" / "erreur").
    static func check(manual: Bool = false) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var req = URLRequest(url: url, timeoutInterval: 12)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            guard let data,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                if manual { DispatchQueue.main.async { info("Vérification impossible", "Impossible de contacter GitHub pour le moment.") } }
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let page = (json["html_url"] as? String) ?? "https://github.com/\(repo)/releases/latest"
            let zip = assetURL(from: json, suffix: ".zip")
            let sha = assetURL(from: json, suffix: ".sha256")
            DispatchQueue.main.async {
                if isNewer(latest, than: currentVersion) {
                    promptUpdate(latest: latest, zip: zip, sha: sha, page: page)
                } else if manual {
                    info("AssistToDo est à jour", "Tu as la dernière version (\(currentVersion)).")
                }
            }
        }.resume()
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.split(separator: ".").map { Int($0) ?? 0 } }
        let pa = parts(a), pb = parts(b)
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func assetURL(from json: [String: Any], suffix: String) -> URL? {
        guard let assets = json["assets"] as? [[String: Any]] else { return nil }
        for a in assets {
            if let name = a["name"] as? String, name.hasSuffix(suffix),
               let s = a["browser_download_url"] as? String, let u = URL(string: s) { return u }
        }
        return nil
    }

    // MARK: - UI

    private static func promptUpdate(latest: String, zip: URL?, sha: URL?, page: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Mise à jour disponible (\(latest))"
        // Auto-install UNIQUEMENT si on a le .zip ET son checksum .sha256 (intégrité vérifiable).
        // Sinon repli sur la page (install manuelle) — on n'installe jamais un binaire non vérifié.
        if let zip, let sha {
            alert.informativeText = "Tu as la version \(currentVersion). Installer la nouvelle ? L'app vérifie l'intégrité, se remplace et redémarre."
            alert.addButton(withTitle: "Installer et redémarrer")
            alert.addButton(withTitle: "Plus tard")
            if alert.runModal() == .alertFirstButtonReturn { installUpdate(from: zip, sha: sha, page: page) }
        } else {
            alert.informativeText = "Tu as la version \(currentVersion). Ouvrir la page de téléchargement ?"
            alert.addButton(withTitle: "Télécharger")
            alert.addButton(withTitle: "Plus tard")
            if alert.runModal() == .alertFirstButtonReturn, let u = URL(string: page) { NSWorkspace.shared.open(u) }
        }
    }

    private static func info(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert(); a.messageText = title; a.informativeText = text; a.runModal()
    }

    // MARK: - Install

    private static func installUpdate(from zip: URL, sha: URL, page: String) {
        Task { @MainActor in
            do {
                // 1) Checksum attendu (64 hex).
                let (shaTmp, _) = try await URLSession.shared.download(from: sha)
                let expected = (try String(contentsOf: shaTmp, encoding: .utf8))
                    .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard expected.count == 64, expected.allSatisfy(\.isHexDigit) else { throw UpdateError.checksumMissing }

                // 2) Télécharge le zip puis VÉRIFIE l'intégrité avant toute install/exécution.
                let (zipTmp, _) = try await URLSession.shared.download(from: zip)
                let actual = SHA256.hash(data: try Data(contentsOf: zipTmp))
                    .map { String(format: "%02x", $0) }.joined()
                guard actual == expected else { throw UpdateError.checksumMismatch }

                // 3) Dézippe.
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("atd-update-\(UUID().uuidString)")
                let unzipped = work.appendingPathComponent("u")
                try FileManager.default.createDirectory(at: unzipped, withIntermediateDirectories: true)
                try runSync("/usr/bin/ditto", ["-xk", zipTmp.path, unzipped.path])
                guard let newApp = try newAppURL(in: unzipped) else { throw UpdateError.noAppInZip }
                // Le .app du zip doit être bien AssistToDo (même bundle id) : on n'installe pas
                // un bundle arbitraire à la place de l'app en cours.
                guard Bundle(url: newApp)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                    throw UpdateError.bundleMismatch
                }

                // 4) Script de swap : chemins passés en ARGUMENTS ($1/$2/$3), JAMAIS interpolés (anti-injection).
                //    Swap ATOMIQUE avec rollback : l'ancien bundle est mis de côté (mv), puis on copie
                //    le nouveau ; si la copie échoue, on restaure l'ancien → jamais d'app supprimée
                //    sans remplacement.
                let script = work.appendingPathComponent("swap.sh")
                let body = """
                #!/bin/bash
                PID="$1"; TARGET="$2"; NEWAPP="$3"
                while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
                BAK="$TARGET.old-$$"
                if [ -d "$TARGET" ]; then mv "$TARGET" "$BAK" || exit 1; fi
                if /usr/bin/ditto "$NEWAPP" "$TARGET"; then
                  xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null
                  rm -rf "$BAK"
                else
                  rm -rf "$TARGET"
                  [ -d "$BAK" ] && mv "$BAK" "$TARGET"
                fi
                open "$TARGET"
                """
                try body.write(to: script, atomically: true, encoding: .utf8)

                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/bash")
                p.arguments = [script.path,
                               String(ProcessInfo.processInfo.processIdentifier),
                               Bundle.main.bundleURL.path,
                               newApp.path]
                try p.run()   // enfant orphelin adopté par launchd à notre fermeture → survit + swap
                NSApp.terminate(nil)
            } catch {
                info("Mise à jour impossible", "Échec (\(error)). Ouvre la page pour installer manuellement.")
                if let u = URL(string: page) { NSWorkspace.shared.open(u) }
            }
        }
    }

    private static func newAppURL(in dir: URL) throws -> URL? {
        let items = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        return items.first { $0.pathExtension == "app" }
    }

    private static func runSync(_ launch: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launch)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
    }
}
