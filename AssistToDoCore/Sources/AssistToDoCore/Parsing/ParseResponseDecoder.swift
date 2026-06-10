import Foundation

public enum ParseResponseDecoder {
    struct Wrapper: Decodable { let tasks: [RawTask] }
    struct RawTask: Decodable {
        let text: String
        let destination: String?
        let remindAt: String?
        let dueDate: String?
        let durationMinutes: Int?
        let listName: String?
        let calendarName: String?
        let noteName: String?
        let priority: String?
        let notify: Bool?
        let tags: [String]?
    }

    public enum DecodeError: Error { case noJSON }

    public static func decode(_ raw: String) throws -> [ParsedTask] {
        let json = stripFences(raw)
        guard let data = json.data(using: .utf8) else { throw DecodeError.noJSON }
        let wrapper = try JSONDecoder().decode(Wrapper.self, from: data)
        return wrapper.tasks.map { rt in
            ParsedTask(
                text: rt.text,
                // Champ absent ou valeur inconnue → local (jamais de capture perdue).
                destination: Destination(rawValue: nullable(rt.destination) ?? "") ?? .local,
                remindAtRaw: nullable(rt.remindAt),
                dueDateRaw: nullable(rt.dueDate),
                durationMinutes: rt.durationMinutes,
                listName: nullable(rt.listName),
                calendarName: nullable(rt.calendarName),
                noteName: nullable(rt.noteName),
                priority: Priority(rawValue: nullable(rt.priority) ?? ""),
                notify: rt.notify ?? false,
                tags: rt.tags ?? []
            )
        }
    }

    /// Garde la sous-chaîne entre la première { et la dernière }.
    private static func stripFences(_ s: String) -> String {
        guard let start = s.firstIndex(of: "{"), let end = s.lastIndex(of: "}") else { return s }
        return String(s[start...end])
    }

    /// Traite la string "null" (et vide) comme nil.
    private static func nullable(_ s: String?) -> String? {
        guard let s, !s.isEmpty, s.lowercased() != "null" else { return nil }
        return s
    }
}
