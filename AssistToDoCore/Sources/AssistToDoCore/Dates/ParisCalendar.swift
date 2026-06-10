import Foundation

public enum ParisCalendar {
    public static let tz = TimeZone(identifier: "Europe/Paris")!

    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = tz; return c
    }

    /// "YYYY-MM-DD" en wall-clock Paris.
    public static func ymd(for date: Date) -> String {
        let f = DateFormatter()
        f.calendar = calendar; f.timeZone = tz; f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// 1=dimanche .. 7=samedi (convention Calendar).
    public static func weekday(for date: Date) -> Int {
        calendar.component(.weekday, from: date)
    }

    /// Minuit Paris du jour de `date`.
    public static func startOfDay(for date: Date) -> Date {
        calendar.startOfDay(for: date)
    }
}
