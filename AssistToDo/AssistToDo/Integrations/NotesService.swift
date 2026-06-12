//
//  NotesService.swift
//  AssistToDo
//
//  Ajoute une ligne à une note Apple ciblée par titre (ex: liste de courses partagée).
//  Via NSAppleScript (sandbox + entitlement temporary-exception.apple-events com.apple.Notes).
//  Le body des notes est du HTML : on append un <div> par article (une ligne propre, sans saut vide).
//  Sans simulation clavier → ne vole jamais le focus.
//

import Foundation

final class NotesService {
    static let shared = NotesService()

    enum NotesError: Error {
        case compileFailed
        case permissionDenied        // -1743 : Automation refusée (réactiver dans Réglages Système)
        case runFailed(code: Int, message: String)
    }

    /// Liste les titres de notes (1re ligne) pour les proposer dans les Réglages.
    /// Déclenche la permission Automation au premier appel.
    func listNoteNames() async -> [String] {
        await Task.detached(priority: .userInitiated) { () -> [String] in
            let source = """
            set out to ""
            tell application "Notes"
                set acc to missing value
                try
                    set acc to account "iCloud"
                end try
                if acc is missing value then set acc to account 1
                repeat with n in notes of acc
                    set out to out & (name of n) & linefeed
                end repeat
            end tell
            return out
            """
            guard let script = NSAppleScript(source: source) else { return [] }
            var err: NSDictionary?
            let result = script.executeAndReturnError(&err)
            if err != nil { return [] }
            let raw = result.stringValue ?? ""
            let names = raw.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return Array(Set(names)).sorted()
        }.value
    }

    /// Ajoute `item` à la note `noteName` (créée si absente). Synchrone et bloquant → appeler hors main thread.
    func append(item: String, noteName: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            try NotesService.run(item: item, noteName: noteName)
        }.value
    }

    private static func run(item: String, noteName: String) throws {
        // Lookup par NOM EN CLAIR → échappement AppleScript seul (pas de HTML, sinon "Lait & Pain"
        // deviendrait "Lait &amp; Pain" et ne matcherait jamais → doublon recréé à chaque ajout).
        let titleLookup = escapeAS(noteName)
        // Contenu inséré dans le body HTML → échappement AppleScript + HTML.
        let titleHTML = escapeHTML(noteName)
        let line = escapeHTML(item)
        // Un <div> = une ligne propre dans Notes (pas de double saut comme avec <br><br>).
        let source = """
        tell application "Notes"
            set acc to missing value
            try
                set acc to account "iCloud"
            end try
            if acc is missing value then set acc to account 1
            tell acc
                if (exists note named "\(titleLookup)") then
                    set theNote to note named "\(titleLookup)"
                    set body of theNote to (body of theNote) & "<div>\(line)</div>"
                else
                    make new note with properties {body:"<div>\(titleHTML)</div><div>\(line)</div>"}
                end if
            end tell
        end tell
        """

        guard let script = NSAppleScript(source: source) else { throw NotesError.compileFailed }
        var errorInfo: NSDictionary?
        script.executeAndReturnError(&errorInfo)
        if let e = errorInfo {
            let code = (e[NSAppleScript.errorNumber] as? Int) ?? -1
            let msg = (e[NSAppleScript.errorMessage] as? String) ?? "inconnu"
            if code == -1743 { throw NotesError.permissionDenied }
            throw NotesError.runFailed(code: code, message: msg)
        }
    }

    /// Échappe pour une string littérale AppleScript : backslash D'ABORD (sinon les `\` ajoutés
    /// ensuite seraient ré-échappés), puis guillemet, puis neutralisation des sauts de ligne.
    /// À utiliser pour un NOM EN CLAIR (lookup `note named`), JAMAIS d'échappement HTML ici.
    private static func escapeAS(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\r\n", with: " ")
         .replacingOccurrences(of: "\n", with: " ")
         .replacingOccurrences(of: "\r", with: " ")
    }

    /// Échappe pour insertion dans le body HTML d'une note (lui-même dans une string AppleScript) :
    /// AppleScript d'abord (backslash, guillemet), puis entités HTML.
    private static func escapeHTML(_ s: String) -> String {
        escapeAS(s)
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
