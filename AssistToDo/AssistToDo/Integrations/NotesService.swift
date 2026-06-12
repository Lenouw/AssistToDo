//
//  NotesService.swift
//  AssistToDo
//
//  Ajoute une ligne à une note Apple ciblée par titre (ex: liste de courses partagée).
//  Via NSAppleScript (sandbox + entitlement temporary-exception.apple-events com.apple.Notes).
//  Le body des notes est du HTML → on append <br> et on échappe & < >.
//

import Foundation

final class NotesService {
    static let shared = NotesService()

    enum NotesError: Error {
        case compileFailed
        case permissionDenied        // -1743 : Automation refusée (réactiver dans Réglages Système)
        case noteMissing             // note ciblée introuvable (on ne crée jamais)
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

    /// Ajoute `item` comme NOUVELLE BULLE de checklist dans la note `noteName` (existante, jamais créée).
    /// Simule le clavier (System Events) : ouvre la note → fin du document → Entrée → tape l'article.
    /// Si la dernière ligne est déjà une bulle, Entrée en crée une nouvelle (héritage du format checklist).
    /// Requiert la permission Accessibilité ; passe Notes au premier plan le temps de la frappe.
    func appendChecklistItem(_ item: String, noteName: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            try NotesService.runChecklist(item: item, noteName: noteName)
        }.value
    }

    /// Ajoute `item` à la note `noteName` (créée si absente). Synchrone et bloquant → appeler hors main thread.
    func append(item: String, noteName: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            try NotesService.run(item: item, noteName: noteName)
        }.value
    }

    private static func runChecklist(item: String, noteName: String) throws {
        let title = asEscape(noteName)
        let line = asEscape(item)
        let source = """
        tell application "Notes"
            set acc to missing value
            try
                set acc to account "iCloud"
            end try
            if acc is missing value then set acc to account 1
            if not (exists note named "\(title)" of acc) then return "MISSING"
            activate
            show note named "\(title)" of acc
        end tell
        delay 0.5
        tell application "System Events"
            tell process "Notes"
                set frontmost to true
                delay 0.2
                key code 125 using {command down}
                delay 0.15
                key code 36
                delay 0.15
                keystroke "\(line)"
            end tell
        end tell
        return "OK"
        """
        guard let script = NSAppleScript(source: source) else { throw NotesError.compileFailed }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let e = errorInfo {
            let code = (e[NSAppleScript.errorNumber] as? Int) ?? -1
            let msg = (e[NSAppleScript.errorMessage] as? String) ?? "inconnu"
            if code == -1743 || code == -25211 { throw NotesError.permissionDenied }
            throw NotesError.runFailed(code: code, message: msg)
        }
        if result.stringValue == "MISSING" { throw NotesError.noteMissing }
    }

    private static func run(item: String, noteName: String) throws {
        let title = escape(noteName)
        let line = escape(item)
        let source = """
        tell application "Notes"
            set acc to missing value
            try
                set acc to account "iCloud"
            end try
            if acc is missing value then set acc to account 1
            tell acc
                if (exists note named "\(title)") then
                    set theNote to note named "\(title)"
                    set body of theNote to (body of theNote) & "<br>" & "\(line)"
                else
                    make new note with properties {body:"\(title)" & "<br>" & "\(line)"}
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

    /// Échappe une string littérale AppleScript (frappée telle quelle au clavier) : backslash puis guillemet.
    private static func asEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Échappe le HTML (le body est interprété en HTML) + les guillemets de la string AppleScript.
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
