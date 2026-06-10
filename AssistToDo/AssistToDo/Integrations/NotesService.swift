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
        case runFailed(code: Int, message: String)
    }

    /// Ajoute `item` à la note `noteName` (créée si absente). Synchrone et bloquant → appeler hors main thread.
    func append(item: String, noteName: String) async throws {
        try await Task.detached(priority: .userInitiated) {
            try NotesService.run(item: item, noteName: noteName)
        }.value
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

    /// Échappe le HTML (le body est interprété en HTML) + les guillemets de la string AppleScript.
    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
