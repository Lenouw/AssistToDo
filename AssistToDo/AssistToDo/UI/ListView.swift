//
//  ListView.swift
//  AssistToDo
//
//  Panneau groupé par TYPE :
//   - Rappels rapides (locaux) : réordonnables (glisser), swipe, édition inline
//   - Rappels (Apple) : cocher = complété dans Rappels Apple, supprimer = retiré
//   - Rendez-vous (Calendrier) : supprimer = retiré du calendrier
//

import SwiftUI
import AssistToDoCore

struct ListView: View {
    @ObservedObject var store: TaskStore
    var onOpenSettings: () -> Void = {}

    @State private var editingId: UUID?
    @State private var editText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Mes tâches").font(.headline)
                if store.badgeCount > 0 {
                    Text("\(store.badgeCount)")
                        .font(.caption.bold())
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                Button(action: onOpenSettings) { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).help("Réglages")
                    .accessibilityLabel("Ouvrir les réglages")
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)

            if isEmpty {
                emptyState
            } else {
                List {
                    if !store.localTasks.isEmpty {
                        Section("Rappels rapides") {
                            ForEach(store.localTasks) { localRow($0) }
                                .onMove(perform: moveLocal)
                        }
                    }
                    if !store.reminderTasks.isEmpty {
                        Section("Rappels") {
                            ForEach(store.reminderTasks) { appleRow($0, isEvent: false) }
                        }
                    }
                }
                .listStyle(.inset)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.localTasks)
            }

            // Confirmation discrète des événements calendrier ajoutés via l'app (auto-nettoyée après 24h).
            if !store.recentEvents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AJOUTÉS AU CALENDRIER (24 H)")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        .tracking(0.5)
                    ForEach(store.recentEvents) { event in
                        HStack(spacing: 6) {
                            Image(systemName: "calendar").font(.caption2).foregroundStyle(.secondary)
                            Text(event.text).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            Spacer(minLength: 4)
                            if let due = event.remindAt ?? event.dueDate {
                                Text(Self.eventDay.string(from: due))
                                    .font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(.quaternary.opacity(0.4))
            }

            Text("Build \(BuildInfo.date)")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
                .padding(.horizontal, 14).padding(.bottom, 8).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private static let eventDay: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Paris"); f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d MMM HH:mm"; return f
    }()

    private var isEmpty: Bool {
        store.localTasks.isEmpty && store.reminderTasks.isEmpty && store.recentEvents.isEmpty
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.seal").font(.largeTitle).foregroundStyle(.tertiary)
            Text("Tout est fait").foregroundStyle(.secondary)
            Text("Maintiens ⌃⌥Espace pour capturer").font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Rangées locales (réordonnables + éditables)

    @ViewBuilder
    private func localRow(_ task: TaskRecord) -> some View {
        if editingId == task.id {
            editRow(task)
        } else {
            TaskRow(task: task, kind: .local) { store.toggleDone(id: task.id) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { store.delete(id: task.id) } label: { Label("Supprimer", systemImage: "trash") }
                    Button { store.postponeToTomorrow(id: task.id) } label: { Label("Demain", systemImage: "arrow.uturn.forward") }.tint(.orange)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { store.toggleDone(id: task.id) } label: { Label("Fait", systemImage: "checkmark.circle") }.tint(.green)
                    Button { startEditing(task) } label: { Label("Modifier", systemImage: "pencil") }.tint(.blue)
                }
                .contextMenu {
                    Button(task.isDone ? "Marquer non faite" : "Marquer faite") { store.toggleDone(id: task.id) }
                    Button("Modifier") { startEditing(task) }
                    Button("Reporter à demain") { store.postponeToTomorrow(id: task.id) }
                    Divider()
                    Button("Supprimer", role: .destructive) { store.delete(id: task.id) }
                }
                .onTapGesture(count: 2) { startEditing(task) }
        }
    }

    // MARK: - Rangées Apple (cocher = sync Apple, supprimer = retiré)

    private func appleRow(_ task: TaskRecord, isEvent: Bool) -> some View {
        TaskRow(task: task, kind: isEvent ? .event : .reminder) {
            store.toggleDone(id: task.id)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { store.delete(id: task.id) } label: { Label("Supprimer", systemImage: "trash") }
        }
        .contextMenu {
            if !isEvent {
                Button(task.isDone ? "Marquer non faite" : "Marquer faite") { store.toggleDone(id: task.id) }
            }
            Button("Supprimer", role: .destructive) { store.delete(id: task.id) }
        }
    }

    private func editRow(_ task: TaskRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil").foregroundStyle(.blue)
            TextField("Tâche", text: $editText)
                .textFieldStyle(.plain)
                .onSubmit { commitEdit(task) }
            Button("OK") { commitEdit(task) }.buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(.vertical, 3)
        .onExitCommand { editingId = nil }
    }

    // MARK: - Actions

    private func moveLocal(from offsets: IndexSet, to destination: Int) {
        var ids = store.localTasks.map { $0.id }
        ids.move(fromOffsets: offsets, toOffset: destination)
        store.moveLocal(orderedIds: ids)
    }

    private func startEditing(_ task: TaskRecord) {
        editText = task.text
        editingId = task.id
    }

    private func commitEdit(_ task: TaskRecord) {
        store.updateText(id: task.id, text: editText)
        editingId = nil
    }
}

enum RowKind { case local, reminder, event }

private struct TaskRow: View {
    let task: TaskRecord
    let kind: RowKind
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Self.priorityColor(task.priority))
                .frame(width: 3).frame(maxHeight: .infinity)

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
                if kind == .local && task.rolloverCount >= 3 {
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

    private var timeBadge: String? {
        if let remind = task.remindAt {
            return (kind == .event ? "" : "🔔 ") + Self.hm.string(from: remind)
        }
        if let due = task.dueDate, kind != .local { return Self.day.string(from: due) }
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
        f.timeZone = TimeZone(identifier: "Europe/Paris"); f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"; return f
    }()
    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Paris"); f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d MMM"; return f
    }()
}
