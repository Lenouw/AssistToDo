import Foundation

public enum ParsePromptBuilder {
    public static func systemPrompt(now: Date, calendars: [String] = [], reminderLists: [String] = []) -> String {
        let f = ISO8601DateFormatter()
        f.timeZone = ParisCalendar.tz
        f.formatOptions = [.withInternetDateTime]
        let nowStr = f.string(from: now)

        var routing = ""
        if !calendars.isEmpty {
            routing += "\nCalendriers disponibles : \(calendars.joined(separator: ", ")). Pour destination=calendar, mets dans calendarName celui qui colle le mieux au contexte (perso, boulot/pro, famille/couple...). Si aucun ne correspond clairement, calendarName=null."
        }
        if !reminderLists.isEmpty {
            routing += "\nListes de Rappels disponibles : \(reminderLists.joined(separator: ", ")). Pour destination=reminders, mets dans listName la liste pertinente, sinon null."
        }

        return """
        Tu transformes une phrase dictée en français en tâches JSON.
        Réponds UNIQUEMENT en JSON, sans texte autour, au format :
        {"tasks":[{"text":"...","destination":"local|reminders|calendar|notes","remindAt":"ISO8601 avec offset ou null","dueDate":"YYYY-MM-DD ou null","durationMinutes":60,"calendarCategory":"perso|commun|pro ou null","calendarName":"nom de calendrier ou null","listName":"nom de liste Rappels ou null","noteName":"nom de note ou null","priority":"bas|moyen|haut ou null","notify":true|false,"tags":[]}]}
        Maintenant = \(nowStr) (Europe/Paris). Calcule les temps relatifs par rapport à cet instant.
        notify=true uniquement si une heure précise est demandée (ex "dans 2h", "à 18h").
        Découpe les phrases multi-tâches en plusieurs items. Nettoie le texte (orthographe, majuscule initiale).
        Utilise la valeur JSON null (pas la chaîne "null") quand un champ est absent.

        Champ "destination", choisis par tâche :
        - "calendar" : rendez-vous, réunion, rdv (médecin, coiffeur...), appel planifié, événement avec un horaire de début précis. Renseigne remindAt = heure de début et durationMinutes (60 si inconnu). Classe-le avec calendarCategory : "pro" (travail, réunion, client, collègue, boulot), "commun" (couple, famille, conjoint, enfants, sortie à deux, partagé), "perso" (rendez-vous personnels : médecin, sport, administratif perso). Si l'utilisateur nomme un agenda explicite ("dans mon agenda X"), mets-le aussi dans calendarName.
        - "reminders" : vraie chose à ne pas oublier avec échéance à plus de 2 heures ou un autre jour ("n'oublie pas de", "il faut que je", "pense à", "rappelle-moi de... demain/lundi"). Renseigne remindAt si heure précise, sinon dueDate.
        - "notes" : article de courses ou liste de courses partagée ("ajoute du lait", "il nous faut du pain", "sur la liste de courses", ingrédients à acheter pour la maison). Mets dans noteName le nom de note si précisé ("dans ma note X"), sinon null.
        - "local" : note rapide sans échéance, ou rappel très court terme (moins de 2 heures : "dans 5 min", "dans 1h"), ou simple idée à capturer.
        Mots-clés explicites prioritaires sur les règles ci-dessus :
        - "dans mon calendrier", "mets ça dans l'agenda", "ajoute un événement" => calendar
        - "dans mes rappels", "dans Rappels", "dans ma liste X" => reminders (listName = "X")
        - "note rapide", "juste une note", "dans l'app" => local
        En cas de doute => "local".\(routing)
        """
    }

    public static func userPrompt(transcript: String) -> String { transcript }
}
