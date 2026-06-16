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

enum UpdateChecker {
    static let repo = "Lenouw/AssistToDo"

    enum UpdateError: Error { case noZipAsset, noAppInZip }

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
            let zip = zipAssetURL(from: json)
            DispatchQueue.main.async {
                if isNewer(latest, than: currentVersion) {
                    promptUpdate(latest: latest, zip: zip, page: page)
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

    private static func zipAssetURL(from json: [String: Any]) -> URL? {
        guard let assets = json["assets"] as? [[String: Any]] else { return nil }
        for a in assets {
            if let name = a["name"] as? String, name.hasSuffix(".zip"),
               let s = a["browser_download_url"] as? String, let u = URL(string: s) { return u }
        }
        return nil
    }

    // MARK: - UI

    private static func promptUpdate(latest: String, zip: URL?, page: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Mise à jour disponible (\(latest))"
        if zip != nil {
            alert.informativeText = "Tu as la version \(currentVersion). Installer la nouvelle ? L'app va se télécharger, remplacer et redémarrer."
            alert.addButton(withTitle: "Installer et redémarrer")
            alert.addButton(withTitle: "Plus tard")
            if alert.runModal() == .alertFirstButtonReturn, let zip { installUpdate(from: zip, page: page) }
        } else {
            // Pas d'asset .zip → repli : ouvrir la page de téléchargement.
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

    private static func installUpdate(from zip: URL, page: String) {
        Task { @MainActor in
            do {
                let (tmpZip, _) = try await URLSession.shared.download(from: zip)
                let work = FileManager.default.temporaryDirectory.appendingPathComponent("atd-update-\(UUID().uuidString)")
                let unzipped = work.appendingPathComponent("u")
                try FileManager.default.createDirectory(at: unzipped, withIntermediateDirectories: true)
                try runSync("/usr/bin/ditto", ["-xk", tmpZip.path, unzipped.path])

                guard let newApp = try newAppURL(in: unzipped) else { throw UpdateError.noAppInZip }
                let target = Bundle.main.bundleURL.path
                let pid = ProcessInfo.processInfo.processIdentifier
                let script = work.appendingPathComponent("swap.sh")
                let body = """
                #!/bin/bash
                while kill -0 \(pid) 2>/dev/null; do sleep 0.3; done
                rm -rf "\(target)"
                /usr/bin/ditto "\(newApp.path)" "\(target)"
                xattr -dr com.apple.quarantine "\(target)" 2>/dev/null
                open "\(target)"
                """
                try body.write(to: script, atomically: true, encoding: .utf8)

                // Lance le helper détaché (survit à la fermeture de l'app) puis quitte.
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/bin/bash")
                p.arguments = ["-c", "nohup bash '\(script.path)' >/dev/null 2>&1 &"]
                try p.run()
                p.waitUntilExit()
                NSApp.terminate(nil)
            } catch {
                info("Mise à jour impossible", "Échec : \(error.localizedDescription). Ouvre la page pour installer manuellement.")
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
