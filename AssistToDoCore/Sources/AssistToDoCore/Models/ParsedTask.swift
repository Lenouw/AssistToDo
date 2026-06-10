import Foundation

public struct ParsedTask: Equatable, Sendable {
    public var text: String
    public var remindAtRaw: String?
    public var dueDateRaw: String?
    public var priority: Priority?
    public var notify: Bool
    public var tags: [String]

    public init(text: String, remindAtRaw: String? = nil, dueDateRaw: String? = nil,
                priority: Priority? = nil, notify: Bool = false, tags: [String] = []) {
        self.text = text; self.remindAtRaw = remindAtRaw; self.dueDateRaw = dueDateRaw
        self.priority = priority; self.notify = notify; self.tags = tags
    }
}
