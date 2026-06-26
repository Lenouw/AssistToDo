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
        {"tasks":[{"text":"...","destination":"local|reminders|calendar|notes","remindAt":"ISO8601 avec offset ou null","dueDate":"YYYY-MM-DD ou null","durationMinutes":60,"calendarCategory":"perso|commun|pro|studio ou null","calendarName":"nom de calendrier ou null","listName":"nom de liste Rappels ou null","noteName":"nom de note ou null","priority":"bas|moyen|haut ou null","notify":true|false,"tags":[],"codeTodo":true|false}]}
        Maintenant = \(nowStr) (Europe/Paris). Calcule les temps relatifs par rapport à cet instant.
        notify=true uniquement si une heure précise est demandée (ex "dans 2h", "à 18h").
        Découpe les phrases multi-tâches en plusieurs items. Une plage de plusieurs jours (« du 20 au 25 », « du lundi au vendredi ») => un item par jour (une date par item).
        Le champ "text" n'est PAS le transcript brut : rédige un libellé de tâche CLAIR, CONCIS et bien formé en français.
        - Corrige les erreurs et coupures de transcription quand l'intention est évidente (Whisper avale parfois des mots) : écris la phrase correcte et compréhensible, pas la version bancale.
        - Si la dictée est longue ou décousue, RÉSUME à l'essentiel actionnable : garde les détails IMPORTANTS (noms de personnes, lieux, montants, échéances/dates, références précises), enlève le bla-bla, les hésitations et les répétitions.
        - Ne sur-résume JAMAIS au point de perdre une info qui change le sens ou rend la tâche inexécutable. Dans le doute, garde le détail.
        - N'INVENTE aucun détail absent (pas de fait, chiffre, nom ou lieu non dicté).
        N'INVENTE JAMAIS de date ni d'heure. Si un item n'a aucune date/heure dictée, laisse remindAt=null ET dueDate=null (ne mets surtout pas la date du jour par défaut).
        Associe CHAQUE jour/heure dicté à l'item qu'il précède ou qu'il suit immédiatement (chaque item garde SA propre date). Une date dictée pour un item ne se propage pas aux autres, sauf mention explicite (« tous les deux lundi », « le même jour »).
        Ex « lundi rdv kiné à 6h, mardi rdv dentiste, dimanche voir Marion » => 3 items : kiné=lundi 06:00 ; dentiste=mardi ; Marion=dimanche.
        Ex « lundi rdv kiné à 6h, et rdv dentiste, et voir Marion » => kiné=lundi 06:00 ; dentiste et Marion SANS date (dueDate=null, remindAt=null).
        ÉCHÉANCE MOLLE : « fais-moi penser à / pense à / il faut que je ... AVANT / POUR / D'ICI [date] » (« avant le 9 juillet », « pour vendredi », « d'ici lundi ») = une simple échéance, PAS un rappel programmé à heure fixe. Reste en "local", CONSERVE la mention d'échéance TELLE QUELLE dans le text (ne l'extrais pas, ne « nettoie » pas la date), et laisse dueDate=null ET remindAt=null. Ex « fais-moi penser à annuler mon abonnement avant le 9 juillet » => text "Annuler mon abonnement avant le 9 juillet", destination "local", dueDate=null, remindAt=null. Ne passe en "reminders" QUE si l'utilisateur demande un vrai rappel programmé à un jour/heure précis ("rappelle-moi vendredi à 14h", "préviens-moi demain à 9h").
        Utilise la valeur JSON null (pas la chaîne "null") quand un champ est absent.
        Si la phrase n'est PAS une vraie tâche ou intention claire (bruit, hésitation type "euh", mots incompréhensibles, déclenchement accidentel, phrase vide de sens, ou l'utilisateur annule / dit que ce n'est rien), renvoie une liste vide : {"tasks":[]}. Ne force JAMAIS la création d'une tâche pour rien.

        Champ "destination", choisis par tâche :
        - "calendar" : rendez-vous, réunion, rdv (médecin, coiffeur...), appel planifié, MAIS AUSSI tout repas / sortie / activité avec quelqu'un (resto, pizza, ciné, apéro, plage, sport à deux, soirée...) dès qu'il y a un moment, même vague ("ce soir", "ce midi", "demain soir", "samedi"). En clair : si ça se passe à un moment donné avec un lieu ou une personne, c'est un événement. Renseigne remindAt = heure de début SEULEMENT si une heure ou un moment est dicté (heure précise, ou vague : ce soir=18h, ce midi=12h, ce matin=9h). Si SEUL un jour est dicté sans aucun moment ("mardi dentiste", "dimanche voir Marion"), remindAt=null (événement journée entière sur dueDate) — n'invente pas d'heure. durationMinutes=60 si inconnu. Classe-le avec calendarCategory : "pro" (travail, réunion, client, collègue, boulot), "commun" (couple, famille, conjoint, enfants, sortie à deux, partagé), "perso" (rendez-vous personnels : médecin, sport, administratif perso), "studio" (réservation/blocage du studio de podcast : "bloque le studio", "réserve le studio", "ferme le studio", "studio occupé/indisponible"). IMPORTANT studio : ne mets remindAt QUE si une heure est dictée explicitement ("de 14h à 18h"). Si aucune heure n'est dictée, remindAt=null et mets seulement la date dans dueDate (n'invente JAMAIS une heure) — l'app posera la plage de fermeture configurée. FERMETURE + RÉOUVERTURE = UN SEUL ÉVÉNEMENT : « ferme/bloque le studio [le matin / toute la matinée / l'après-midi...] ET rouvre/réouverture à HH » décrit UNE période de fermeture. La réouverture est la FIN de la fermeture, ce n'est JAMAIS un événement séparé — ne crée AUCUNE tâche "rouvrir/réouverture du studio". Pour cet item unique : remindAt = début de la fermeture (matin → 08:00 ; après-midi → 14:00 ; sinon l'heure de début dictée) et durationMinutes = durée du début jusqu'à l'heure de réouverture. Ex "ferme le studio toute la matinée et rouvre à 14h" => UN item, text "Studio fermé", calendarCategory "studio", remindAt 08:00, durationMinutes 360 (08:00→14:00). Ex "bloque le studio mardi de 14h à 18h" => remindAt 14:00, durationMinutes 240. Si l'utilisateur nomme un agenda explicite ("dans mon agenda X", "sur le calendrier X", "calendrier X"), mets son nom EXACT dans calendarName.
        IMPORTANT calendar : un événement EXIGE une date ou une heure réellement dictée. Si un rendez-vous/sortie est mentionné SANS aucune date ni heure ("rdv dentiste", "voir Marion"), ne le classe PAS en calendar et n'invente pas la date du jour : mets-le en "reminders" (chose à ne pas oublier) avec dueDate=null et remindAt=null.
        - "reminders" : chose à ne pas oublier qui a une DATE ou une heure DICTÉE (à plus de 2h ou un autre jour) : "rappelle-moi mardi de...", "n'oublie pas vendredi", "il faut que je... lundi", "à 18h", "demain". EXIGE un "quand" explicite. Renseigne remindAt si heure précise, sinon dueDate. Si AUCUNE date/heure n'est dictée, ce n'est PAS "reminders" → mets "local".
        - "notes" : article de courses ou liste de courses partagée ("ajoute du lait", "il nous faut du pain", "sur la liste de courses", ingrédients à acheter pour la maison). Le champ text ne contient QUE le nom de l'article ("lait", "pain", "farine") — JAMAIS de verbe ("acheter", "ajoute", "prends", "il faut"). Un item par article. Mets dans noteName le nom de note si précisé ("dans ma note X"), sinon null.
        - "local" : to-do "vide-tête" SANS aucune date ni heure dictée (chose à faire un jour, pas urgente, sans "quand" : "chercher le colis Amazon", "penser à rappeler le plombier", "réserver une table au resto", "préparer le dossier") — c'est le cas par défaut d'une chose à faire non datée. OU rappel très court terme (moins de 2h : "dans 5 min", "dans 1h"). OU simple note/idée à capturer. C'est cette liste locale qui se synchronise avec Toudou.
        Champ "codeTodo" (uniquement pertinent si destination="local") : mets-le à true quand la capture est une to-do de DÉVELOPPEMENT / code, signalée par un mot-clé : "Claude Code", "à coder", "note de code", "à développer", "feature à faire", "bug à corriger", "le client veut/demande" (une modif logicielle). Dans ce cas, RETIRE le mot-clé déclencheur du text (ex "Claude Code : ajouter le dark mode" => text "Ajouter le dark mode", codeTodo=true). Sinon codeTodo=false. Ça ne change PAS destination (reste "local"), juste la sous-liste.
        Mots-clés explicites prioritaires sur les règles ci-dessus :
        - "dans mon calendrier", "mets ça dans l'agenda", "ajoute un événement" => calendar
        - "dans mes rappels", "dans Rappels", "dans ma liste X" => reminders (listName = "X")
        - "note rapide", "juste une note", "dans l'app" => local
        En cas de doute => "local".\(routing)
        """
    }

    public static func userPrompt(transcript: String) -> String { transcript }
}
