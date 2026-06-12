//
//  ListView.swift
//  AssistToDo
//
//  Panneau "second cerveau" : flux permanent des pensées vocales ancrées dans l'app
//  (📌 ma liste/idées · 🔔 rappels · 📝 notes), du plus récent au plus ancien.
//  Le calendrier n'y figure jamais (les events vivent dans le Calendrier Apple).
//  En bas, un agenda discret du jour (Rappels + Calendrier iCloud), lecture seule.
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
            header

            if store.thoughts.isEmpty && store.codeTasks.isEmpty {
                emptyState
            } else {
                List {
                    Section { ForEach(store.thoughts) { thoughtRow($0) } }
                    if !store.codeTasks.isEmpty {
                        Section {
                            ForEach(store.codeTasks) { thoughtRow($0) }
                        } header: {
                            Label("Claude Code", systemImage: "chevron.left.forwardslash.chevron.right")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.plain)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.thoughts)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: store.codeTasks)
            }

            todaySection

            Text("Build \(BuildInfo.date)")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
                .padding(.horizontal, 14).padding(.bottom, 8).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await store.refreshToday() }
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "brain")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text("AssistToDo").font(.headline)
                Text("Mes pensées vocales").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: onOpenSettings) { Image(systemName: "gearshape") }
                .buttonStyle(.plain).help("Réglages")
                .accessibilityLabel("Ouvrir les réglages")
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
        .overlay(alignment: .bottom) { Divider() }
    }

    // MARK: - Zone "Aujourd'hui · iCloud" (lecture seule)

    @ViewBuilder
    private var todaySection: some View {
        if !store.todayEvents.isEmpty || !store.todayReminders.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("AUJOURD'HUI · ICLOUD")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                    .tracking(0.5)
                ForEach(store.todayEvents) { todayRow($0, icon: "calendar", tint: .blue) }
                ForEach(store.todayReminders) { todayRow($0, icon: "bell", tint: .orange) }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4))
        }
    }

    private func todayRow(_ item: TodayItem, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(tint).frame(width: 14)
            if let date = item.date {
                Text(Self.hm.string(from: date))
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            } else {
                Text("journée").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Text(item.title).font(.system(size: 12)).foregroundStyle(.primary).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "brain").font(.largeTitle).foregroundStyle(.tertiary)
            Text("Ton second cerveau est vide").foregroundStyle(.secondary)
            Text("Maintiens ⌃⌥Espace pour capturer une pensée").font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Rangée du flux

    @ViewBuilder
    private func thoughtRow(_ task: TaskRecord) -> some View {
        if editingId == task.id {
            editRow(task)
        } else {
            ThoughtRow(task: task, timeLabel: Self.timeLabel(task)) { store.toggleDone(id: task.id) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { store.delete(id: task.id) } label: { Label("Supprimer", systemImage: "trash") }
                    if task.destination == .local {
                        Button { store.postponeToTomorrow(id: task.id) } label: { Label("Demain", systemImage: "arrow.uturn.forward") }.tint(.orange)
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { store.toggleDone(id: task.id) } label: { Label("Fait", systemImage: "checkmark.circle") }.tint(.green)
                    if task.destination != .reminders {
                        Button { startEditing(task) } label: { Label("Modifier", systemImage: "pencil") }.tint(.blue)
                    }
                    if task.destination == .local {
                        Button { store.moveToList(id: task.id, to: task.localList == .code ? .braindump : .code) } label: {
                            Label(task.localList == .code ? "Vidage de cerveau" : "Claude Code",
                                  systemImage: "arrow.left.arrow.right")
                        }.tint(.purple)
                    }
                }
                .contextMenu {
                    Button(task.isDone ? "Marquer non faite" : "Marquer faite") { store.toggleDone(id: task.id) }
                    if task.destination != .reminders {
                        Button("Modifier") { startEditing(task) }
                    }
                    if task.destination == .local {
                        Button(task.localList == .code ? "Déplacer vers Vidage de cerveau" : "Déplacer vers Claude Code") {
                            store.moveToList(id: task.id, to: task.localList == .code ? .braindump : .code)
                        }
                        Button("Reporter à demain") { store.postponeToTomorrow(id: task.id) }
                    }
                    Divider()
                    Button("Supprimer", role: .destructive) { store.delete(id: task.id) }
                }
                .onTapGesture(count: 2) {
                    if task.destination != .reminders { startEditing(task) }
                }
        }
    }

    private func editRow(_ task: TaskRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil").foregroundStyle(.blue)
            TextField("Pensée", text: $editText)
                .textFieldStyle(.plain)
                .onSubmit { commitEdit(task) }
            Button("OK") { commitEdit(task) }.buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(.vertical, 3)
        .onExitCommand { editingId = nil }
    }

    // MARK: - Actions

    private func startEditing(_ task: TaskRecord) {
        editText = task.text
        editingId = task.id
    }

    private func commitEdit(_ task: TaskRecord) {
        store.updateText(id: task.id, text: editText)
        editingId = nil
    }

    // MARK: - Libellé temporel compact

    static func timeLabel(_ r: TaskRecord) -> String {
        let d = r.remindAt ?? r.createdAt
        if ParisCalendar.calendar.isDateInToday(d) { return hm.string(from: d) }
        if ParisCalendar.calendar.isDateInYesterday(d) { return "hier" }
        return dayShort.string(from: d)
    }

    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Paris"); f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"; return f
    }()
    private static let dayShort: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Paris"); f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d"; return f
    }()
}

// MARK: - Rangée d'une pensée

private struct ThoughtRow: View {
    let task: TaskRecord
    let timeLabel: String
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : iconName)
                    .font(.system(size: 14))
                    .foregroundStyle(task.isDone ? Color.green : iconTint)
            }
            .buttonStyle(.plain)
            .frame(width: 16)
            .padding(.top, 1)
            .accessibilityLabel(task.isDone ? "Marquer non faite" : "Marquer faite")

            Text(task.text)
                .font(.system(size: 13))
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 6)

            Text(timeLabel)
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(.vertical, 3)
    }

    private var iconName: String {
        if task.destination == .local && task.localList == .code { return "chevron.left.forwardslash.chevron.right" }
        return Self.icon(task.destination)
    }
    private var iconTint: Color {
        if task.destination == .local && task.localList == .code { return .purple }
        return Self.tint(task.destination)
    }

    static func icon(_ d: Destination) -> String {
        switch d {
        case .local: return "pin.fill"
        case .reminders: return "bell.fill"
        case .notes: return "note.text"
        case .calendar: return "calendar"   // jamais affiché dans le flux
        }
    }

    static func tint(_ d: Destination) -> Color {
        switch d {
        case .local: return .gray
        case .reminders: return .orange
        case .notes: return .pink
        case .calendar: return .blue
        }
    }
}
