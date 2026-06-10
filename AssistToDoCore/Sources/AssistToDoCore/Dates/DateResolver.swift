import Foundation

/// Résout des intentions temporelles FR en Date exacte (Europe/Paris).
/// Déterministe : le LLM propose, ce code décide.
public enum DateResolver {
    private static let cal = ParisCalendar.calendar

    private static let weekdays: [String: Int] = [ // 1=dim..7=sam
        "dimanche": 1, "lundi": 2, "mardi": 3, "mercredi": 4,
        "jeudi": 5, "vendredi": 6, "samedi": 7
    ]

    /// Heure de rappel précise si un motif d'heure/délai est présent, sinon nil.
    public static func resolveRemind(text: String, now: Date) -> Date? {
        let t = text.lowercased()

        // "dans X minutes / heures" (gère "une demi heure", chiffres en lettres simples)
        if let delay = parseRelativeDelay(t) {
            return now.addingTimeInterval(delay)
        }
        // "à 18h", "à 9h30"
        if let hm = parseClock(t) {
            return setTime(now: now, hour: hm.0, minute: hm.1)
        }
        // "ce soir" → 18:00
        if t.contains("ce soir") || t.contains("ce soir-là") {
            return setTime(now: now, hour: 18, minute: 0)
        }
        // "ce midi" → 12:00
        if t.contains("ce midi") || t.contains("à midi") {
            return setTime(now: now, hour: 12, minute: 0)
        }
        return nil
    }

    /// Date d'échéance (jour) si un motif de jour est présent, sinon nil.
    public static func resolveDueDate(text: String, now: Date) -> Date? {
        let t = text.lowercased()
        if t.contains("après-demain") || t.contains("apres-demain") {
            return cal.date(byAdding: .day, value: 2, to: ParisCalendar.startOfDay(for: now))
        }
        if t.contains("demain") {
            return cal.date(byAdding: .day, value: 1, to: ParisCalendar.startOfDay(for: now))
        }
        if t.contains("aujourd'hui") || t.contains("aujourdhui") {
            return ParisCalendar.startOfDay(for: now)
        }
        for (name, wd) in weekdays where t.contains(name) {
            return nextWeekday(wd, after: now)
        }
        return nil
    }

    // MARK: - Helpers

    private static func parseRelativeDelay(_ t: String) -> TimeInterval? {
        guard t.contains("dans ") else { return nil }
        if t.contains("demi heure") || t.contains("demi-heure") { return 30 * 60 }
        // nombre en chiffres
        if let n = firstInt(in: t) {
            if t.contains("heure") { return Double(n) * 3600 }
            if t.contains("minute") { return Double(n) * 60 }
        }
        // nombres en lettres usuels
        let words: [String: Int] = ["une": 1, "un": 1, "deux": 2, "trois": 3, "quatre": 4,
                                    "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9, "dix": 10]
        for (w, n) in words where t.contains(" \(w) ") {
            if t.contains("heure") { return Double(n) * 3600 }
            if t.contains("minute") { return Double(n) * 60 }
        }
        return nil
    }

    private static func parseClock(_ t: String) -> (Int, Int)? {
        // motifs "18h", "9h30", "18 h", "18:30"
        let pattern = #"(\d{1,2})\s*[h:]\s*(\d{0,2})"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
        let hStr = (t as NSString).substring(with: m.range(at: 1))
        let mStr = (t as NSString).substring(with: m.range(at: 2))
        guard let h = Int(hStr), h < 24 else { return nil }
        let min = Int(mStr) ?? 0
        guard min < 60 else { return nil }
        return (h, min)
    }

    private static func firstInt(in t: String) -> Int? {
        let pattern = #"(\d{1,3})"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) else { return nil }
        return Int((t as NSString).substring(with: m.range(at: 1)))
    }

    /// Pose l'heure d'horloge sur aujourd'hui ; si l'instant est déjà passé, reporte au lendemain.
    private static func setTime(now: Date, hour: Int, minute: Int) -> Date {
        let today = cal.date(bySettingHour: hour, minute: minute, second: 0, of: now) ?? now
        if today <= now {
            return cal.date(byAdding: .day, value: 1, to: today) ?? today
        }
        return today
    }

    /// Prochain jour de semaine strictement après aujourd'hui (Paris).
    private static func nextWeekday(_ target: Int, after now: Date) -> Date {
        let start = ParisCalendar.startOfDay(for: now)
        for offset in 1...7 {
            if let d = cal.date(byAdding: .day, value: offset, to: start),
               ParisCalendar.weekday(for: d) == target {
                return d
            }
        }
        return start
    }
}
