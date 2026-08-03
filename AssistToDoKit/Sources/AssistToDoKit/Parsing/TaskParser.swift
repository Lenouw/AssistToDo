//
//  TaskParser.swift
//  AssistToDoKit
//
//  Transcript → tâche(s) structurée(s). Le LLM propose dates/priorité/tags/split,
//  DateResolver (Swift) sert de filet déterministe. Fallback texte brut si l'appel échoue :
//  jamais de tâche perdue.
//

import Foundation
import AssistToDoCore

/// Tâche parsée + sa destination (local / Rappels Apple / Calendrier Apple).
public struct RoutedTask {
    public var record: TaskRecord
    public let destination: Destination
    public let durationMinutes: Int?
    public let listName: String?
    public let calendarName: String?
    public let calendarCategory: CalendarCategory?
    public let noteName: String?
}

public struct TaskParser {
    let client: any LLMCompleting

    public init(client: any LLMCompleting) {
        self.client = client
    }

    public func parse(transcript: String, now: Date,
                      calendars: [String] = [], reminderLists: [String] = [],
                      customRules: String = "") async -> [RoutedTask] {
        let system = ParsePromptBuilder.systemPrompt(now: now, calendars: calendars,
                                                     reminderLists: reminderLists, customRules: customRules)
        do {
            let content = try await client.complete(system: system, user: transcript)
            var parsed = try ParseResponseDecoder.decode(content)
            // Garde-fou « écho » : le LLM recrache parfois la phrase dictée telle quelle en simple
            // note locale, en ignorant la consigne (vu en vrai : « Ferme le studio le vendredi 9
            // septembre de 15h à 16h » rangé dans le vidage de cerveau au lieu de créer l'événement).
            // C'est un raté d'instruction, pas une décision : on retente UNE fois.
            if Self.isEcho(parsed, transcript: transcript) {
                if let retryContent = try? await client.complete(system: system, user: transcript),
                   let retry = try? ParseResponseDecoder.decode(retryContent),
                   !Self.isEcho(retry, transcript: transcript) {
                    parsed = retry
                }
            }
            // Vide = le LLM a jugé que ce n'est pas une vraie tâche → on ne crée rien.
            // On écarte aussi les tâches au texte vide/blanc (hallucination de split, objet
            // résiduel) : sinon une ligne fantôme serait créée et poussée sur Toudou.
            return parsed
                .filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { routed(from: $0, transcript: transcript, now: now) }
        } catch {
            // Échec réseau/décodage : on ne peut pas juger → on garde le texte brut (jamais perdu).
            print("Parse échoué, fallback texte brut : \(error)")
            return [rawFallback(transcript, now: now)]
        }
    }

    // MARK: - Garde-fou « écho »

    /// Vrai si le LLM s'est contenté de renvoyer la phrase dictée en note locale non datée, alors que
    /// la phrase contient un repère temporel (donc elle aurait dû être routée/datée). Le prompt interdit
    /// explicitement de recopier le transcript : c'est un raté d'instruction → on peut retenter.
    static func isEcho(_ tasks: [ParsedTask], transcript: String) -> Bool {
        guard tasks.count == 1, let t = tasks.first,
              t.destination == .local,
              t.dueDateRaw == nil, t.remindAtRaw == nil,
              hasTemporalSignal(transcript) else { return false }
        return normalized(t.text) == normalized(transcript)
    }

    /// Repère temporel dicté : heure d'horloge, mois, jour de semaine, ou mot relatif.
    static func hasTemporalSignal(_ s: String) -> Bool {
        let t = normalized(s)
        if s.range(of: #"\d{1,2}\s*[h:]"#, options: .regularExpression) != nil { return true }
        let markers = ["janvier", "fevrier", "mars", "avril", "mai", "juin", "juillet", "aout",
                       "septembre", "octobre", "novembre", "decembre",
                       "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche",
                       "demain", "prochain", "prochaine", "aujourdhui"]
        return markers.contains { t.contains($0) }
    }

    /// Minuscules, sans accents ni ponctuation ni espaces (comparaison tolérante).
    private static func normalized(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
    }

    // MARK: - Construction

    private func routed(from p: ParsedTask, transcript: String, now: Date) -> RoutedTask {
        let today = ParisCalendar.startOfDay(for: now)
        // Jour RELATIF (« mardi prochain », « demain ») : Swift fait AUTORITÉ (les LLM calculent mal le
        // jour de la semaine). Uniquement si `whenRaw` est PUREMENT relatif (sans chiffre) : « jeudi 6
        // août » est une date ABSOLUE (jour = étiquette) → on garde la date du LLM (resolveRelativeDay=nil).
        let swiftDay = DateResolver.resolveRelativeDay(text: p.whenRaw, now: now)
        // Heure : celle du LLM (ou détectée dans le texte). Si on a un jour Swift fiable ET une heure,
        // on recale l'heure sur le BON jour (corrige un rappel dont le LLM s'est trompé de jour).
        var remind = parseISODateTime(p.remindAtRaw) ?? DateResolver.resolveRemind(text: p.text, now: now)
        if let day = swiftDay, let r = remind { remind = DateResolver.combine(day: day, time: r) }
        // Jour d'échéance : Swift (relatif) d'abord, puis date LLM (utile pour les dates ABSOLUES), puis filet texte.
        let resolvedDue = swiftDay ?? parseDay(p.dueDateRaw) ?? DateResolver.resolveDueDate(text: p.text, now: now)
        // On ne défaute à "aujourd'hui" QUE pour les tâches locales (liste du jour + rollover).
        // Pour calendar/reminders/notes, dueDate reste nil si rien n'est dicté → pas de date inventée
        // (et le filet de CaptureCoordinator peut rétrograder un event sans date en rappel).
        let due = resolvedDue ?? (p.destination == .local ? today : nil)
        let notify = p.notify && remind != nil

        let record = TaskRecord(
            text: p.text,
            createdAt: now,
            dueDate: due,
            remindAt: remind,
            notify: notify,
            priority: p.priority,
            tags: p.tags,
            rawTranscript: transcript,
            parseStatus: .parsed,
            localList: p.codeTodo ? .code : .braindump
        )
        // Un événement calendrier sans heure → événement "journée entière" (ex: bloquer le studio).
        return RoutedTask(record: record, destination: p.destination,
                          durationMinutes: p.durationMinutes, listName: p.listName,
                          calendarName: p.calendarName, calendarCategory: p.calendarCategory,
                          noteName: p.noteName)
    }

    private func rawFallback(_ transcript: String, now: Date) -> RoutedTask {
        RoutedTask(
            record: TaskRecord(
                text: transcript,
                createdAt: now,
                dueDate: ParisCalendar.startOfDay(for: now),
                rawTranscript: transcript,
                parseStatus: .rawOnly
            ),
            destination: .local, durationMinutes: nil, listName: nil,
            calendarName: nil, calendarCategory: nil, noteName: nil
        )
    }

    // MARK: - Dates

    /// "2026-06-11T17:30:00+02:00" → Date.
    private func parseISODateTime(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// "2026-06-11" → minuit Paris ce jour-là.
    private func parseDay(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = DateFormatter()
        f.calendar = ParisCalendar.calendar
        f.timeZone = ParisCalendar.tz
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}
