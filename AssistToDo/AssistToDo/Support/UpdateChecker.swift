//
//  UpdateChecker.swift
//  AssistToDo
//
//  Auto-update léger : interroge l'API GitHub Releases, compare la version locale à la
//  dernière release publiée, et propose de télécharger si plus récente. Sandbox-friendly
//  (juste network.client), sans framework ni signature/notarisation requise.
//

import Foundation
import AppKit

enum UpdateChecker {
    /// Dépôt public hébergeant les releases (DMG).
    static let repo = "Lenouw/AssistToDo"

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// `manual` = déclenché depuis les Réglages (affiche aussi "à jour" / "erreur").
    /// Au lancement, silencieux si déjà à jour.
    static func check(manual: Bool = false) {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        var req = URLRequest(url: url, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            guard let data,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                if manual { DispatchQueue.main.async { info(title: "Vérification impossible",
                                                            text: "Impossible de contacter GitHub pour le moment.") } }
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let page = (json["html_url"] as? String) ?? "https://github.com/\(repo)/releases/latest"
            DispatchQueue.main.async {
                if isNewer(latest, than: currentVersion) {
                    promptUpdate(latest: latest, url: page)
                } else if manual {
                    info(title: "AssistToDo est à jour", text: "Tu as la dernière version (\(currentVersion)).")
                }
            }
        }.resume()
    }

    /// Compare deux versions sémantiques ("1.2.0" > "1.1.5"). Tolère des longueurs différentes.
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

    private static func promptUpdate(latest: String, url: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Mise à jour disponible (\(latest))"
        alert.informativeText = "Tu as la version \(currentVersion). Télécharger la nouvelle ?"
        alert.addButton(withTitle: "Télécharger")
        alert.addButton(withTitle: "Plus tard")
        if alert.runModal() == .alertFirstButtonReturn, let u = URL(string: url) {
            NSWorkspace.shared.open(u)
        }
    }

    private static func info(title: String, text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
