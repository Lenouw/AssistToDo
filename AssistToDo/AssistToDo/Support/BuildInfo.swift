//
//  BuildInfo.swift
//  AssistToDo
//

import Foundation

enum BuildInfo {
    /// Date de build lisible (Europe/Paris), affichée dans l'UI pour vérifier la version testée.
    static let date: String = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM HH:mm"
        return f.string(from: Date())
    }()
}
