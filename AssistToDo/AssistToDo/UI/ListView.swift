//
//  ListView.swift
//  AssistToDo
//
//  Liste des tâches : sections Aujourd'hui / À venir / Faites, couleurs de priorité,
//  horaires, swipe (fait / demain / supprimer / modifier), édition inline.
//

import SwiftUI
import AssistToDoCore

struct ListView: View {
    @ObservedObject var store: TaskStore
    var onOpenSettings: () -> Void = {}

    @State private var editingId: UUID?
    @State private var editText = ""
    @FocusState private var editFocused: Bool

    private var todayActive: [TaskRecord] { store.tasks.filter { !$0.isDone } }
    private var todayDone: [TaskRecord] { store.tasks.filter { $0.isDone } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Mes tâches").font(.headline)
                if !todayActive.isEmpty {
                    Text("\(todayActive.count)")
                        .font(.caption.bold())
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
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
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.seal")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                    Text("Tout est fait")
                        .foregroundStyle(.secondary)
                    Text("Maintiens ⌃⌥Espace pour capturer une tâche")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
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
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: store.tasks)
            }

            Text("Build \(BuildInfo.date)")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Lignes

    @ViewBuilder
    private func row(_ task: TaskRecord, showDay: Bool = false) -> some View {
        if editingId == task.id {
            editRow(task)
        } else {
            TaskRow(task: task, showDay: showDay) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                    store.toggleDone(id: task.id)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    store.delete(id: task.id)
                } label: {
                    Label("Supprimer", systemImage: "trash")
                }
                Button {
                    store.postponeToTomorrow(id: task.id)
                } label: {
                    Label("Demain", systemImage: "arrow.uturn.forward")
                }
                .tint(.orange)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        store.toggleDone(id: task.id)
                    }
                } label: {
                    Label(task.isDone ? "Pas faite" : "Fait", systemImage: task.isDone ? "arrow.uturn.backward.circle" : "checkmark.circle")
                }
                .tint(.green)
                Button {
                    startEditing(task)
                } label: {
                    Label("Modifier", systemImage: "pencil")
                }
                .tint(.blue)
            }
            .contextMenu {
                Button(task.isDone ? "Marquer non faite" : "Marquer faite") {
                    store.toggleDone(id: task.id)
                }
                Button("Modifier") { startEditing(task) }
                Button("Reporter à demain") { store.postponeToTomorrow(id: task.id) }
                Divider()
                Button("Supprimer", role: .destructive) { store.delete(id: task.id) }
            }
            .onTapGesture(count: 2) { startEditing(task) }
        }
    }

    private func editRow(_ task: TaskRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .foregroundStyle(.blue)
            TextField("Tâche", text: $editText)
                .textFieldStyle(.plain)
                .focused($editFocused)
                .onSubmit { commitEdit(task) }
            Button("OK") { commitEdit(task) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.vertical, 3)
        .onExitCommand { editingId = nil }   // Échap annule
    }

    private func startEditing(_ task: TaskRecord) {
        editText = task.text
        editingId = task.id
        editFocused = true
    }

    private func commitEdit(_ task: TaskRecord) {
        store.updateText(id: task.id, text: editText)
        editingId = nil
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
                    Text("×\(task.rolloverCount)")
                        .font(.caption2.bold())
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(.orange.opacity(0.15), in: Capsule())
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
