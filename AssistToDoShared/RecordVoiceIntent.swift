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
        // Siri, Raccourcis, bouton Action mappé sur le raccourci : perform() tourne dans l'app.
        // Deux signaux : le drapeau (lu au passage au premier plan, cas du lancement à froid) ET
        // une notification immédiate (cas de l'app déjà ouverte : pas de changement de scenePhase,
        // le drapeau seul attendait la prochaine ouverture et le micro ne démarrait pas).
        PendingCapture.flag()
        await MainActor.run { NotificationCenter.default.post(name: PendingCapture.requested, object: nil) }
        return .result()
    }
}

/// Pont intent → app. Le Centre de contrôle et le widget passent par l'URL `assisttodo://capture`
/// (ouverte par le système, reçue par l'app dans tous les cas). Le drapeau UserDefaults ne sert
/// qu'aux intents exécutés DANS l'app : écrit depuis l'extension widget, il resterait invisible
/// pour l'app (UserDefaults.standard n'est pas partagé entre processus sans App Group).
public enum PendingCapture {
    public static let url = URL(string: "assisttodo://capture")!
    public static let requested = Notification.Name("assisttodo.captureRequested")
    private static let key = "pendingVoiceCapture"
    public static func flag() { UserDefaults.standard.set(true, forKey: key) }
    /// Retourne true une seule fois si une capture est en attente, puis remet à zéro.
    public static func consume() -> Bool {
        let v = UserDefaults.standard.bool(forKey: key)
        if v { UserDefaults.standard.set(false, forKey: key) }
        return v
    }
}
