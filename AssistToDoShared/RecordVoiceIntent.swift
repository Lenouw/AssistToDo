//
//  RecordVoiceIntent.swift
//  Partagé entre l'app iOS et l'extension widget.
//
//  Intent unique réutilisé par TOUS les déclencheurs : Action Button, Siri/Shortcuts,
//  Control Center (iOS 18) et widgets. `openAppWhenRun` ouvre l'app au premier plan ;
//  l'app démarre l'enregistrement micro (impossible en arrière-plan).
//

import AppIntents

public struct RecordVoiceIntent: AppIntent {
    public static var title: LocalizedStringResource = "Nouvelle note vocale"
    public static var description = IntentDescription("Lance la capture vocale dans AssistToDo.")
    // L'app doit passer au premier plan pour accéder au micro.
    public static var openAppWhenRun: Bool = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        // perform() s'exécute dans le processus de l'app (openAppWhenRun) : on lève un drapeau
        // que l'app consomme dès qu'elle devient active pour démarrer la capture.
        PendingCapture.flag()
        return .result()
    }
}

/// Pont léger intent → app via UserDefaults (même processus quand openAppWhenRun=true).
public enum PendingCapture {
    private static let key = "pendingVoiceCapture"
    public static func flag() { UserDefaults.standard.set(true, forKey: key) }
    /// Retourne true une seule fois si une capture est en attente, puis remet à zéro.
    public static func consume() -> Bool {
        let v = UserDefaults.standard.bool(forKey: key)
        if v { UserDefaults.standard.set(false, forKey: key) }
        return v
    }
}
