//
//  ListView.swift
//  AssistToDo
//
//  Panneau "second cerveau" en 3 zones redimensionnables (séparateurs déplaçables,
//  scroll interne par zone) :
//   1. Vidage de cerveau (local braindump + Rappels Apple) — réordonnable au glisser
//   2. To-do Claude Code (local code) — réordonnable au glisser
//   3. Aujourd'hui · iCloud (events + rappels du jour, lecture seule)
//

import SwiftUI
import AssistToDoKit
import AppKit
import AssistToDoCore

struct ListView: View {
    @ObservedObject var store: TaskStore
    var onOpenSettings: () -> Void = {}
    var onOpenCaptures: () -> Void = {}

    @State private var editingId: UUID?
    @State private var editText = ""

    // Hauteurs des zones (persistées). La zone du milieu (Code) prend le reste.
    @AppStorage("paneBrainH") private var brainH: Double = 300
    @AppStorage("paneTodayH") private var todayH: Double = 120
    @State private var dragBaseBrain: Double?
    @State private var dragBaseToday: Double?

    private let handleH: CGFloat = 14
    private let minPane: CGFloat = 60

    private var isEmpty: Bool {
        store.thoughts.isEmpty && store.codeTasks.isEmpty
            && store.todayEvents.isEmpty && store.todayReminders.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isEmpty {
                emptyState
            } else {
                GeometryReader { geo in panes(in: geo.size.height) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { await store.refreshToday() }
    }

    // MARK: - Zones redimensionnables

    @ViewBuilder
    private func panes(in total: CGFloat) -> some View {
        let avail = max(total - 2 * handleH, minPane * 3)
        let tH = min(max(CGFloat(todayH), minPane), avail - 2 * minPane)
        let bH = min(max(CGFloat(brainH), minPane), avail - tH - minPane)
        let cH = avail - bH - tH

        VStack(spacing: 0) {
            pane(title: "Vidage de cerveau", systemImage: "brain", count: store.thoughts.count, height: bH) {
                taskList(store.thoughts, move: moveBrain)
            }
            handle(base: $dragBaseBrain, value: $brainH, lower: minPane, upper: avail - tH - minPane)
            pane(title: "Claude Code", systemImage: "chevron.left.forwardslash.chevron.right", count: store.codeTasks.count, height: cH) {
                if store.codeTasks.isEmpty { paneHint("Dicte « Claude Code : … » pour ajouter ici") }
                else { taskList(store.codeTasks, move: moveCode) }
            }
            handle(base: $dragBaseToday, value: $todayH, lower: minPane, upper: avail - bH - minPane, inverted: true)
            pane(title: "Aujourd'hui · iCloud", systemImage: "calendar", count: store.todayEvents.count + store.todayReminders.count, height: tH) {
                todayContent
            }
        }
    }

    /// Une zone : barre de titre fine + contenu qui remplit la hauteur allouée.
    private func pane<Content: View>(title: String, systemImage: String, count: Int, height: CGFloat,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 10)).foregroundStyle(.tertiary)
                Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.5).foregroundStyle(.tertiary)
                if count > 0 { Text("\(count)").font(.system(size: 9)).foregroundStyle(.quaternary) }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 2)
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(height: height)
        .clipped()
    }

    private func paneHint(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.quaternary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Séparateur déplaçable. `inverted` = glisser vers le bas réduit la zone (cas de la zone du bas).
    private func handle(base: Binding<Double?>, value: Binding<Double>, lower: CGFloat, upper: CGFloat, inverted: Bool = false) -> some View {
        ZStack {
            Rectangle().fill(.clear)
            Capsule().fill(.secondary.opacity(0.35)).frame(width: 36, height: 4)
        }
        .frame(height: handleH)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { NSCursor.resizeUpDown.set() }
            else if base.wrappedValue == nil { NSCursor.arrow.set() }   // ne pas réinitialiser pendant un drag
        }
        .gesture(
            DragGesture()
                .onChanged { v in
                    if base.wrappedValue == nil { base.wrappedValue = value.wrappedValue }
                    let delta = Double(inverted ? -v.translation.height : v.translation.height)
                    let proposed = (base.wrappedValue ?? value.wrappedValue) + delta
                    let hi = max(Double(lower), Double(upper))   // garde-fou : upper ne passe jamais sous lower
                    value.wrappedValue = min(max(proposed, Double(lower)), hi)
                }
                .onEnded { _ in base.wrappedValue = nil }
        )
    }

    // MARK: - Listes réordonnables

    private func taskList(_ tasks: [TaskRecord], move: @escaping (IndexSet, Int) -> Void) -> some View {
        List {
            ForEach(tasks) { thoughtRow($0) }
                .onMove(perform: move)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: tasks)
    }

    private func moveBrain(_ offsets: IndexSet, _ destination: Int) {
        var ids = store.thoughts.map { $0.id }
        ids.move(fromOffsets: offsets, toOffset: destination)
        store.reorderLocal(orderedIds: ids)
    }
    private func moveCode(_ offsets: IndexSet, _ destination: Int) {
        var ids = store.codeTasks.map { $0.id }
        ids.move(fromOffsets: offsets, toOffset: destination)
        store.reorderLocal(orderedIds: ids)
    }

    // MARK: - Zone du jour (lecture seule)

    private var todayContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(store.todayEvents) { todayRow($0, icon: "calendar", tint: .blue) }
                ForEach(store.todayReminders) { todayRow($0, icon: "bell", tint: .orange) }
                if store.todayEvents.isEmpty && store.todayReminders.isEmpty {
                    Text("Rien aujourd'hui").font(.caption).foregroundStyle(.quaternary)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func todayRow(_ item: TodayItem, icon: String, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.caption).foregroundStyle(tint).frame(width: 14)
            if let date = item.date {
                Text(Self.hm.string(from: date)).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
            } else {
                Text("journée").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Text(item.title).font(.system(size: 12)).foregroundStyle(.primary).lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "brain")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.tint)
                .frame(width: 26, height: 26)
                .background(.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text("AssistToDo").font(.headline)
                Text("Mes pensées vocales").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: onOpenCaptures) { Image(systemName: "waveform") }
                .buttonStyle(.plain).help("Captures (historique vocal, re-traiter)")
                .accessibilityLabel("Ouvrir les captures")
            Button(action: onOpenSettings) { Image(systemName: "gearshape") }
                .buttonStyle(.plain).help("Réglages")
                .accessibilityLabel("Ouvrir les réglages")
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)
        .overlay(alignment: .bottom) { Divider() }
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

    // MARK: - Rangée d'une pensée

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
                            Label(task.localList == .code ? "Vidage de cerveau" : "Claude Code", systemImage: "arrow.left.arrow.right")
                        }.tint(.purple)
                    }
                }
                .contextMenu {
                    Button(task.isDone ? "Marquer non faite" : "Marquer faite") { store.toggleDone(id: task.id) }
                    if task.destination != .reminders { Button("Modifier") { startEditing(task) } }
                    if task.destination == .local {
                        Button(task.localList == .code ? "Déplacer vers Vidage de cerveau" : "Déplacer vers Claude Code") {
                            store.moveToList(id: task.id, to: task.localList == .code ? .braindump : .code)
                        }
                        Button("Reporter à demain") { store.postponeToTomorrow(id: task.id) }
                    }
                    Divider()
                    Button("Supprimer", role: .destructive) { store.delete(id: task.id) }
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

    private func startEditing(_ task: TaskRecord) { editText = task.text; editingId = task.id }
    private func commitEdit(_ task: TaskRecord) { store.updateText(id: task.id, text: editText); editingId = nil }

    // MARK: - Libellé temporel

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

            // Poignée de glissement (affordance "attrape ici pour réordonner").
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .padding(.leading, 2).padding(.top, 1)
                .help("Glisser pour réordonner")
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
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
        case .calendar: return "calendar"
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
