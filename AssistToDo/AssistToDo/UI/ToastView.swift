//
//  ToastView.swift
//  AssistToDo
//
//  Toast de confirmation : montre chaque tâche créée et sa destination
//  (liste locale, Rappels Apple, Calendrier Apple).
//

import SwiftUI
import AssistToDoCore

struct ToastItem: Identifiable {
    let id = UUID()
    let record: TaskRecord
    let destination: Destination
    /// true si la destination demandée a échoué et que la tâche est retombée en local.
    let fellBack: Bool
}

@MainActor
final class ToastModel: ObservableObject {
    @Published var items: [ToastItem] = []
}

struct ToastView: View {
    @ObservedObject var model: ToastModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(model.items.count > 1 ? "\(model.items.count) tâches ajoutées" : "Tâche ajoutée")
                    .font(.subheadline.bold())
            }
            ForEach(model.items) { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.record.text)
                        .font(.callout)
                        .lineLimit(2)
                    HStack(spacing: 4) {
                        Image(systemName: Self.icon(item.destination))
                            .font(.caption2)
                        Text(destinationLabel(item))
                            .font(.caption)
                    }
                    .foregroundStyle(item.fellBack ? .orange : .secondary)
                }
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.1)))
    }

    private func destinationLabel(_ item: ToastItem) -> String {
        if item.fellBack { return "Liste locale (destination indisponible)" }
        var parts: [String] = []
        switch item.destination {
        case .local: parts.append("Ma liste")
        case .reminders: parts.append("Rappels Apple")
        case .calendar: parts.append("Calendrier")
        }
        if let remind = item.record.remindAt {
            parts.append(Self.timeFormatter.string(from: remind))
        }
        if let p = item.record.priority { parts.append("priorité " + p.rawValue) }
        return parts.joined(separator: " · ")
    }

    static func icon(_ d: Destination) -> String {
        switch d {
        case .local: return "checklist"
        case .reminders: return "list.bullet.circle"
        case .calendar: return "calendar"
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "d MMM HH:mm"
        return f
    }()
}
