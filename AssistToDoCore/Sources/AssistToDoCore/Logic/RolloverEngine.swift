import Foundation

public enum RolloverEngine {
    public struct Result: Equatable {
        public let tasks: [TaskRecord]
        public let rolledDay: String?  // jour Paris pour lequel le rollover a été appliqué
    }

    /// Avance à aujourd'hui (Paris) toute tâche non faite dont la dueDate est antérieure.
    /// Idempotent : si `lastRolloverDay` == aujourd'hui, ne fait rien.
    public static func apply(tasks: [TaskRecord], now: Date, lastRolloverDay: String?) -> Result {
        let today = ParisCalendar.ymd(for: now)
        if lastRolloverDay == today {
            return Result(tasks: tasks, rolledDay: today)
        }
        let todayStart = ParisCalendar.startOfDay(for: now)
        var changed = false
        let updated = tasks.map { t -> TaskRecord in
            guard !t.isDone, let due = t.dueDate, due < todayStart else { return t }
            var copy = t
            copy.dueDate = todayStart
            copy.rolloverCount += 1
            changed = true
            return copy
        }
        return Result(tasks: updated, rolledDay: changed ? today : lastRolloverDay)
    }
}
