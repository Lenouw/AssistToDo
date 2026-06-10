//
//  ListView.swift
//  AssistToDo
//
//  Liste des tâches : sections Aujourd'hui / À venir / Faites,
//  accent couleur par priorité, horaires de rappel.
//

import SwiftUI
import AssistToDoCore

struct ListView: View {
    @ObservedObject var store: TaskStore
    var onOpenSettings: () -> Void = {}

    private var todayActive: [TaskRecord] { store.tasks.filter { !$0.isDone } }
    private var todayDone: [TaskRecord] { store.tasks.filter { $0.isDone } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Mes tâches").font(.headline)
                Spacer()
                Button(action: onOpenSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(.plain)
                    .help("Réglages")
                    .accessibilityLabel("Ouvrir les réglages")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 8)

            if store.tasks.isEmpty && store.upcoming.isEmpty {
                Spacer()
                Text("Aucune tâche")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List {
                    if !todayActive.isEmpty {
                        Section("Aujourd'hui") {
                            ForEach(todayActive) { row($0) }
                        }
                    }
                    if !store.upcoming.isEmpty {
                        Section("À venir") {
                            ForEach(store.upcoming) { row($0, showDay: true) }
                        }
                    }
                    if !todayDone.isEmpty {
                        Section("Faites") {
                            ForEach(todayDone) { row($0) }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Text("Build \(BuildInfo.date)")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func row(_ task: TaskRecord, showDay: Bool = false) -> some View {
        TaskRow(task: task, showDay: showDay) { store.toggleDone(id: task.id) }
    }
}

private struct TaskRow: View {
    let task: TaskRecord
    var showDay: Bool = false
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Accent couleur de priorité.
            RoundedRectangle(cornerRadius: 2)
                .fill(Self.priorityColor(task.priority))
                .frame(width: 3)
                .frame(maxHeight: .infinity)

            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isDone ? .green : Self.priorityColor(task.priority))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Marquer non faite" : "Marquer faite")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.text)
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? .secondary : .primary)
                if let sub = subtitle {
                    Text(sub).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 4) {
                if let badge = timeBadge {
                    Text(badge)
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Self.priorityColor(task.priority).opacity(0.15), in: Capsule())
                        .foregroundStyle(Self.priorityColor(task.priority))
                }
                if task.rolloverCount >= 3 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("Reportée \(task.rolloverCount) fois")
                }
            }
        }
        .padding(.vertical, 3)
    }

    /// Badge horaire : heure de rappel, ou jour d'échéance pour la section "À venir".
    private var timeBadge: String? {
        if let remind = task.remindAt { return "🔔 " + Self.hm.string(from: remind) }
        if showDay, let due = task.dueDate { return Self.day.string(from: due) }
        return nil
    }

    private var subtitle: String? {
        var parts: [String] = []
        if let p = task.priority { parts.append(p.rawValue) }
        if !task.tags.isEmpty { parts.append(task.tags.map { "#\($0)" }.joined(separator: " ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func priorityColor(_ p: Priority?) -> Color {
        switch p {
        case .haut: return .red
        case .moyen: return .orange
        case .bas: return .blue
        case nil: return .secondary
        }
    }

    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d MMM"
        return f
    }()
}
