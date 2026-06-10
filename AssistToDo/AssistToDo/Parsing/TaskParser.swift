//
//  TaskParser.swift
//  AssistToDo
//
//  Transcript → tâche(s) structurée(s). Le LLM propose dates/priorité/tags/split,
//  DateResolver (Swift) sert de filet déterministe. Fallback texte brut si l'appel échoue :
//  jamais de tâche perdue.
//

import Foundation
import AssistToDoCore

/// Tâche parsée + sa destination (local / Rappels Apple / Calendrier Apple).
struct RoutedTask {
    var record: TaskRecord
    let destination: Destination
    let durationMinutes: Int?
    let listName: String?
    let calendarName: String?
}

struct TaskParser {
    let client: OpenRouterClient

    func parse(transcript: String, now: Date,
               calendars: [String] = [], reminderLists: [String] = []) async -> [RoutedTask] {
        let system = ParsePromptBuilder.systemPrompt(now: now, calendars: calendars, reminderLists: reminderLists)
        do {
            let content = try await client.complete(system: system, user: transcript)
            let parsed = try ParseResponseDecoder.decode(content)
            guard !parsed.isEmpty else { return [rawFallback(transcript, now: now)] }
            return parsed.map { routed(from: $0, transcript: transcript, now: now) }
        } catch {
            print("Parse échoué, fallback texte brut : \(error)")
            return [rawFallback(transcript, now: now)]
        }
    }

    // MARK: - Construction

    private func routed(from p: ParsedTask, transcript: String, now: Date) -> RoutedTask {
        let today = ParisCalendar.startOfDay(for: now)
        // LLM d'abord (calculé par tâche), DateResolver en filet sur le texte de la tâche.
        let remind = parseISODateTime(p.remindAtRaw) ?? DateResolver.resolveRemind(text: p.text, now: now)
        let due = parseDay(p.dueDateRaw) ?? DateResolver.resolveDueDate(text: p.text, now: now) ?? today
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
            parseStatus: .parsed
        )
        // Un événement calendrier sans heure de début n'a pas de sens → retombe en local.
        let destination: Destination = (p.destination == .calendar && remind == nil) ? .local : p.destination
        return RoutedTask(record: record, destination: destination,
                          durationMinutes: p.durationMinutes, listName: p.listName, calendarName: p.calendarName)
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
            destination: .local, durationMinutes: nil, listName: nil, calendarName: nil
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
