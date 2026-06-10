import Foundation

public enum ParsePromptBuilder {
    public static func systemPrompt(now: Date) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = ParisCalendar.tz
        f.formatOptions = [.withInternetDateTime]
        let nowStr = f.string(from: now)
        return """
        Tu transformes une phrase dictée en français en tâches JSON.
        Réponds UNIQUEMENT en JSON, sans texte autour, au format :
        {"tasks":[{"text":"...","remindAt":"ISO8601 avec offset ou null","dueDate":"YYYY-MM-DD ou null","priority":"bas|moyen|haut ou null","notify":true|false,"tags":[]}]}
        Maintenant = \(nowStr) (Europe/Paris). Calcule les temps relatifs par rapport à cet instant.
        notify=true uniquement si une heure précise est demandée (ex "dans 2h", "à 18h").
        Découpe les phrases multi-tâches en plusieurs items. Nettoie le texte (orthographe, majuscule initiale).
        Utilise la valeur JSON null (pas la chaîne "null") quand un champ est absent.
        """
    }

    public static func userPrompt(transcript: String) -> String { transcript }
}
