import Foundation

public enum ParsePromptBuilder {
    public static func systemPrompt(now: Date, calendars: [String] = [], reminderLists: [String] = [],
                                    customRules: String = "") -> String {
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
        let rules = customRules.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rules.isEmpty {
            routing += "\nRègles de classement de l'utilisateur (PRIORITAIRES sur tout le reste, applique-les strictement) :\n\(rules)"
        }

        return """
        Tu transformes une phrase dictée en français en tâches JSON.
        Réponds UNIQUEMENT en JSON, sans texte autour, au format :
        {"tasks":[{"text":"...","destination":"local|reminders|calendar|notes","remindAt":"ISO8601 avec offset ou null","dueDate":"YYYY-MM-DD ou null","durationMinutes":60,"calendarCategory":"perso|commun|pro|studio ou null","calendarName":"nom de calendrier ou null","listName":"nom de liste Rappels ou null","noteName":"nom de note ou null","priority":"bas|moyen|haut ou null","notify":true|false,"tags":[]}]}
        Maintenant = \(nowStr) (Europe/Paris). Calcule les temps relatifs par rapport à cet instant.
        notify=true uniquement si une heure précise est demandée (ex "dans 2h", "à 18h").
        Découpe les phrases multi-tâches en plusieurs items. Une plage de plusieurs jours (« du 20 au 25 », « du lundi au vendredi ») => un item par jour (une date par item). Nettoie le texte (orthographe, majuscule initiale).
        Utilise la valeur JSON null (pas la chaîne "null") quand un champ est absent.
        Si la phrase n'est PAS une vraie tâche ou intention claire (bruit, hésitation type "euh", mots incompréhensibles, déclenchement accidentel, phrase vide de sens, ou l'utilisateur annule / dit que ce n'est rien), renvoie une liste vide : {"tasks":[]}. Ne force JAMAIS la création d'une tâche pour rien.

        Champ "destination", choisis par tâche :
        - "calendar" : rendez-vous, réunion, rdv (médecin, coiffeur...), appel planifié, MAIS AUSSI tout repas / sortie / activité avec quelqu'un (resto, pizza, ciné, apéro, plage, sport à deux, soirée...) dès qu'il y a un moment, même vague ("ce soir", "ce midi", "demain soir", "samedi"). En clair : si ça se passe à un moment donné avec un lieu ou une personne, c'est un événement. Renseigne remindAt = heure de début (ce soir=18h, ce midi=12h) et durationMinutes (60 si inconnu). Classe-le avec calendarCategory : "pro" (travail, réunion, client, collègue, boulot), "commun" (couple, famille, conjoint, enfants, sortie à deux, partagé), "perso" (rendez-vous personnels : médecin, sport, administratif perso), "studio" (réservation/blocage du studio de podcast : "bloque le studio", "réserve le studio", "studio occupé/indisponible", enregistrement podcast au studio). Si l'utilisateur nomme un agenda explicite ("dans mon agenda X"), mets-le aussi dans calendarName.
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
