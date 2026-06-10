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
        {"tasks":[{"text":"...","destination":"local|reminders|calendar","remindAt":"ISO8601 avec offset ou null","dueDate":"YYYY-MM-DD ou null","durationMinutes":60,"listName":"nom de liste Rappels ou null","priority":"bas|moyen|haut ou null","notify":true|false,"tags":[]}]}
        Maintenant = \(nowStr) (Europe/Paris). Calcule les temps relatifs par rapport à cet instant.
        notify=true uniquement si une heure précise est demandée (ex "dans 2h", "à 18h").
        Découpe les phrases multi-tâches en plusieurs items. Nettoie le texte (orthographe, majuscule initiale).
        Utilise la valeur JSON null (pas la chaîne "null") quand un champ est absent.

        Champ "destination", choisis par tâche :
        - "calendar" : rendez-vous, réunion, rdv (médecin, coiffeur...), appel planifié, événement avec un horaire de début précis. Renseigne remindAt = heure de début et durationMinutes (60 si inconnu).
        - "reminders" : vraie chose à ne pas oublier avec échéance à plus de 2 heures ou un autre jour ("n'oublie pas de", "il faut que je", "pense à", "rappelle-moi de... demain/lundi"). Renseigne remindAt si heure précise, sinon dueDate.
        - "local" : note rapide sans échéance, ou rappel très court terme (moins de 2 heures : "dans 5 min", "dans 1h"), ou simple idée à capturer.
        Mots-clés explicites prioritaires sur les règles ci-dessus :
        - "dans mon calendrier", "mets ça dans l'agenda", "ajoute un événement" => calendar
        - "dans mes rappels", "dans Rappels", "dans ma liste X" => reminders (listName = "X")
        - "note rapide", "juste une note", "dans l'app" => local
        En cas de doute => "local".
        """
    }

    public static func userPrompt(transcript: String) -> String { transcript }
}
