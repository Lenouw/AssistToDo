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
import UniformTypeIdentifiers

struct ListView: View {
    @ObservedObject var store: TaskStore
    var onOpenSettings: () -> Void = {}
    var onOpenCaptures: () -> Void = {}
    var onOpenArchive: () -> Void = {}

    @State private var editingId: UUID?
    @State private var editText = ""

    // Hauteurs des zones (persistées). La zone du milieu (Code) prend le reste.
    @AppStorage("paneBrainH") private var brainH: Double = 300
    @AppStorage("paneTodayH") private var todayH: Double = 120
    @AppStorage("paneWorkH") private var workH: Double = 190
    @State private var dragBaseBrain: Double?
    @State private var dragBaseWork: Double?
    @State private var dragBaseToday: Double?

    // Panneau Travail : groupes clients repliés (persistés) + édition inline du client.
    @AppStorage("workCollapsedProjects") private var collapsedRaw: String = ""
    @State private var editingProjectId: UUID?
    @State private var projectText = ""

    private let handleH: CGFloat = 14
    private let minPane: CGFloat = 60

    private var isEmpty: Bool {
        store.thoughts.isEmpty && store.codeTasks.isEmpty && store.workTasks.isEmpty
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
        .task { await store.refreshToday(); SyncCoordinator.shared?.nudge() }
    }

    // MARK: - Zones redimensionnables

    @ViewBuilder
    private func panes(in total: CGFloat) -> some View {
        // Ordre : Vidage de cerveau, Travail, Claude Code (prend le reste), Calendrier.
        let avail = max(total - 3 * handleH, minPane * 4)
        let tH = min(max(CGFloat(todayH), minPane), avail - 3 * minPane)
        let bH = min(max(CGFloat(brainH), minPane), avail - tH - 2 * minPane)
        let wH = min(max(CGFloat(workH), minPane), avail - tH - bH - minPane)
        let cH = avail - bH - wH - tH

        VStack(spacing: 0) {
            pane(title: "Vidage de cerveau", systemImage: "brain", count: store.thoughts.count + store.openReminders.count + store.upcomingReminders.count, height: bH, tint: .indigo) {
                brainList
            }
            handle(base: $dragBaseBrain, value: $brainH, lower: minPane, upper: avail - tH - wH - minPane)
            pane(title: "Travail", systemImage: "briefcase", count: store.workTasks.filter { !$0.isDone }.count, height: wH, tint: .pink) {
                if store.workTasks.isEmpty {
                    paneHint("Dicte « Travail : … » ou glisse une tâche ici")
                        .onDrop(of: [.plainText], isTargeted: nil) { handleDrop($0, to: .work); return true }
                }
                else { workList }
            }
            handle(base: $dragBaseWork, value: $workH, lower: minPane, upper: avail - tH - bH - minPane)
            pane(title: "Claude Code", systemImage: "chevron.left.forwardslash.chevron.right", count: store.codeTasks.count, height: cH, tint: .green) {
                if store.codeTasks.isEmpty { paneHint("Dicte « Claude Code : … » pour ajouter ici").onDrop(of: [.plainText], isTargeted: nil) { handleDrop($0, to: .code); return true } }
                else { taskList(store.codeTasks, move: moveCode, dropTo: .code) }
            }
            handle(base: $dragBaseToday, value: $todayH, lower: minPane, upper: avail - bH - wH - minPane, inverted: true)
            pane(title: "Calendrier · iCloud", systemImage: "calendar", count: store.todayEvents.count, height: tH, tint: .blue) {
                todayContent
            }
        }
    }

    /// Une zone : barre de titre fine + contenu qui remplit la hauteur allouée.
    private func pane<Content: View>(title: String, systemImage: String, count: Int, height: CGFloat,
                                     tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: systemImage).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
                Text(title.uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.5).foregroundStyle(tint)
                if count > 0 { Text("\(count)").font(.system(size: 9, weight: .medium)).foregroundStyle(tint.opacity(0.6)) }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tint.opacity(0.16))                  // bandeau coloré = séparation visuelle nette par catégorie
            .overlay(alignment: .bottom) { Rectangle().fill(tint.opacity(0.45)).frame(height: 1) }
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
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 1)   // vraie barre pleine largeur
            Capsule().fill(.secondary.opacity(0.55)).frame(width: 40, height: 5) // poignée de redimensionnement
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

    private func taskList(_ tasks: [TaskRecord], move: @escaping (IndexSet, Int) -> Void, dropTo list: LocalList) -> some View {
        List {
            ForEach(tasks) { thoughtRow($0) }
                .onMove(perform: move)
                .onInsert(of: [.plainText]) { _, p in handleDrop(p, to: list) }
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

    // MARK: - Cerveau : rappels iCloud (en haut) + braindump, dans UNE seule List qui scrolle

    /// Rappels iCloud ouverts épinglés en haut (section non réordonnable) + pensées braindump
    /// (section réordonnable + swipes). Tout scrolle ensemble → gère N rappels sans déborder.
    private var brainList: some View {
        List {
            if !store.openReminders.isEmpty {
                Section {
                    ForEach(store.openReminders) { item in
                        ReminderRowView(
                            item: item,
                            timeText: Self.reminderLabel(item.date),
                            onComplete: { Task { await store.completeReminder(id: item.id) } },
                            onPostpone: { Task { await store.postponeReminderToTomorrow(id: item.id) } }
                        )
                        .listRowBackground(Color.orange.opacity(0.06))
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    }
                }
            }
            Section {
                ForEach(store.thoughts) { thoughtRow($0) }
                    .onMove(perform: moveBrain)
                    .onInsert(of: [.plainText]) { _, p in handleDrop(p, to: .braindump) }
            }
            // Rappels iCloud à échéance future : confirmation visuelle de ce qu'on vient de créer.
            if !store.upcomingReminders.isEmpty {
                Section {
                    ForEach(store.upcomingReminders) { item in
                        ReminderRowView(
                            item: item,
                            timeText: Self.upcomingLabel(item.date),
                            onComplete: { Task { await store.completeReminder(id: item.id) } },
                            onPostpone: { Task { await store.postponeReminderToTomorrow(id: item.id) } }
                        )
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    }
                } header: {
                    Text("À venir").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: store.thoughts)
        .animation(.default, value: store.openReminders)
        .animation(.default, value: store.upcomingReminders)
    }

    // MARK: - Zone du bas : calendrier iCloud (lecture seule)

    private var todayContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(store.todayEvents) { todayRow($0, icon: "calendar", tint: .blue) }
                if store.todayEvents.isEmpty {
                    Text("Aucun événement aujourd'hui").font(.caption).foregroundStyle(.quaternary)
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
        .help(item.title)
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
            Button(action: onOpenArchive) { Image(systemName: "archivebox") }
                .buttonStyle(.plain).help("Archive (tâches faites)")
                .accessibilityLabel("Ouvrir l'archive")
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
                .itemProvider { Self.dragItem(task) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { store.delete(id: task.id) } label: { Label("Supprimer", systemImage: "trash") }.labelStyle(.titleAndIcon)
                    if task.destination == .local {
                        Button { store.postponeToTomorrow(id: task.id) } label: { Label("Demain", systemImage: "arrow.uturn.forward") }.labelStyle(.titleAndIcon).tint(.orange)
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { store.toggleDone(id: task.id) } label: { Label("Fait", systemImage: "checkmark.circle") }.labelStyle(.titleAndIcon).tint(.green)
                    if task.destination != .reminders {
                        Button { startEditing(task) } label: { Label("Modifier", systemImage: "pencil") }.labelStyle(.titleAndIcon).tint(.blue)
                    }
                    if task.destination == .local && task.localList == .braindump {
                        Button { store.moveToList(id: task.id, to: .work) } label: {
                            Label("Travail", systemImage: "briefcase")
                        }.labelStyle(.titleAndIcon).tint(.pink)
                    }
                    if task.destination == .local {
                        Button { store.moveToList(id: task.id, to: task.localList == .code ? .braindump : .code) } label: {
                            Label(task.localList == .code ? "Vidage de cerveau" : "Claude Code", systemImage: "arrow.left.arrow.right")
                        }.labelStyle(.titleAndIcon).tint(.purple)
                    }
                }
                .contextMenu {
                    Button(task.isDone ? "Marquer non faite" : "Marquer faite") { store.toggleDone(id: task.id) }
                    if task.destination != .reminders { Button("Modifier") { startEditing(task) } }
                    if task.destination == .local {
                        moveMenu(task)
                        Button("Reporter à demain") { store.postponeToTomorrow(id: task.id) }
                    }
                    Divider()
                    Button("Supprimer", role: .destructive) { store.delete(id: task.id) }
                }
        }
    }

    // MARK: - Glisser-déposer entre panneaux

    /// Préfixe qui identifie une tâche AssistToDo dans le presse-papiers de glisser (évite d'avaler
    /// un texte quelconque déposé depuis une autre app).
    static let dragPrefix = "assisttodo-task:"
    static func dragItem(_ t: TaskRecord) -> NSItemProvider {
        NSItemProvider(object: (dragPrefix + t.id.uuidString) as NSString)
    }

    /// Dépôt d'une tâche sur une liste. Vers Travail, `project` = client du groupe visé (nil = Sans client).
    private func handleDrop(_ providers: [NSItemProvider], to list: LocalList, project: String? = nil) {
        for p in providers where p.canLoadObject(ofClass: NSString.self) {
            _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                guard let raw = obj as? String, raw.hasPrefix(Self.dragPrefix),
                      let id = UUID(uuidString: String(raw.dropFirst(Self.dragPrefix.count))) else { return }
                DispatchQueue.main.async { store.dropTask(id: id, to: list, project: project) }
            }
        }
    }

    /// Sous-menu « Déplacer vers » : les deux autres listes locales.
    @ViewBuilder
    private func moveMenu(_ task: TaskRecord) -> some View {
        Menu("Déplacer vers") {
            if task.localList != .braindump { Button("Vidage de cerveau") { store.moveToList(id: task.id, to: .braindump) } }
            if task.localList != .work { Button("Travail") { store.moveToList(id: task.id, to: .work) } }
            if task.localList != .code { Button("Claude Code") { store.moveToList(id: task.id, to: .code) } }
        }
    }

    // MARK: - Travail : groupes par client, ordonnés par urgence

    /// Clients dans l'ordre de leur tâche la plus urgente (workTasks est déjà trié par priorité),
    /// « Sans client » toujours en dernier.
    private var workGroups: [(name: String?, tasks: [TaskRecord])] {
        var order: [String] = []
        var byName: [String: [TaskRecord]] = [:]
        var unassigned: [TaskRecord] = []
        for t in store.workTasks {
            guard let n = t.projectName else { unassigned.append(t); continue }
            if byName[n] == nil { order.append(n) }
            byName[n, default: []].append(t)
        }
        var out: [(name: String?, tasks: [TaskRecord])] = order.map { ($0, byName[$0] ?? []) }
        if !unassigned.isEmpty { out.append((nil, unassigned)) }
        return out
    }

    private var collapsed: Set<String> { Set(collapsedRaw.split(separator: "\n").map(String.init)) }
    private func toggleCollapsed(_ key: String) {
        var c = collapsed
        if c.contains(key) { c.remove(key) } else { c.insert(key) }
        collapsedRaw = c.sorted().joined(separator: "\n")
    }

    private var workList: some View {
        List {
            ForEach(workGroups, id: \.name) { group in
                let key = group.name ?? "∅"
                let isCollapsed = collapsed.contains(key)
                Section {
                    if !isCollapsed {
                        ForEach(group.tasks) { workRow($0) }
                            .onInsert(of: [.plainText]) { _, p in handleDrop(p, to: .work, project: group.name) }
                    }
                } header: {
                    WorkGroupHeader(name: group.name ?? "Sans client", open: group.tasks.filter { !$0.isDone }.count,
                                    isCollapsed: isCollapsed, isUnassigned: group.name == nil) {
                        withAnimation(.easeOut(duration: 0.18)) { toggleCollapsed(key) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(.easeOut(duration: 0.2), value: store.workTasks)
    }

    @ViewBuilder
    private func workRow(_ task: TaskRecord) -> some View {
        if editingId == task.id {
            editRow(task)
        } else if editingProjectId == task.id {
            projectEditRow(task)
        } else {
            WorkRow(task: task, dueLabel: Self.workDueLabel(task),
                    onToggle: { store.toggleDone(id: task.id) },
                    onPriority: { store.setPriority(id: task.id, $0) })
                .itemProvider { Self.dragItem(task) }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) { store.delete(id: task.id) } label: { Label("Supprimer", systemImage: "trash") }.labelStyle(.titleAndIcon)
                    Button { store.postponeToTomorrow(id: task.id) } label: { Label("Demain", systemImage: "arrow.uturn.forward") }.labelStyle(.titleAndIcon).tint(.orange)
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button { store.toggleDone(id: task.id) } label: { Label("Fait", systemImage: "checkmark.circle") }.labelStyle(.titleAndIcon).tint(.green)
                    Button { startEditing(task) } label: { Label("Modifier", systemImage: "pencil") }.labelStyle(.titleAndIcon).tint(.blue)
                    Button { startEditingProject(task) } label: { Label("Client", systemImage: "person.crop.square") }.labelStyle(.titleAndIcon).tint(.pink)
                }
                .contextMenu {
                    Button(task.isDone ? "Marquer non faite" : "Marquer faite") { store.toggleDone(id: task.id) }
                    Button("Modifier") { startEditing(task) }
                    Menu("Priorité") {
                        Button("Haute") { store.setPriority(id: task.id, .haut) }
                        Button("Moyenne") { store.setPriority(id: task.id, .moyen) }
                        Button("Basse") { store.setPriority(id: task.id, .bas) }
                        Divider()
                        Button("Aucune") { store.setPriority(id: task.id, nil) }
                    }
                    Menu("Client") {
                        ForEach(store.knownProjects.filter { $0 != task.projectName }, id: \.self) { name in
                            Button(name) { store.setProject(id: task.id, name) }
                        }
                        if !store.knownProjects.isEmpty { Divider() }
                        Button("Nouveau client…") { startEditingProject(task) }
                        if task.projectName != nil { Button("Retirer le client") { store.setProject(id: task.id, nil) } }
                    }
                    moveMenu(task)
                    Button("Reporter à demain") { store.postponeToTomorrow(id: task.id) }
                    Divider()
                    Button("Supprimer", role: .destructive) { store.delete(id: task.id) }
                }
        }
    }

    private func projectEditRow(_ task: TaskRecord) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.crop.square").foregroundStyle(.pink)
            TextField("Nom du client", text: $projectText)
                .textFieldStyle(.plain)
                .onSubmit { commitProject(task) }
            Button("OK") { commitProject(task) }.buttonStyle(.borderedProminent).controlSize(.small).tint(.pink)
        }
        .padding(.vertical, 3)
        .onExitCommand { editingProjectId = nil }
    }

    private func startEditingProject(_ task: TaskRecord) { projectText = task.projectName ?? ""; editingProjectId = task.id }
    private func commitProject(_ task: TaskRecord) { store.setProject(id: task.id, projectText); editingProjectId = nil }

    /// Échéance affichée seulement si elle apporte une info : à venir (« ven. 17 ») ou reportée.
    static func workDueLabel(_ r: TaskRecord) -> String? {
        if let d = r.dueDate, ParisCalendar.startOfDay(for: d) > ParisCalendar.startOfDay(for: Date()) {
            return ParisCalendar.calendar.isDateInTomorrow(d) ? "demain" : dayShort.string(from: d)
        }
        if r.rolloverCount > 0 { return "reportée ×\(r.rolloverCount)" }
        return nil
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

    /// Libellé d'un rappel : heure si c'est aujourd'hui, sinon date courte ("hier", "ven. 26").
    static func reminderLabel(_ date: Date?) -> String? {
        guard let date else { return nil }
        if ParisCalendar.calendar.isDateInToday(date) { return hm.string(from: date) }
        if ParisCalendar.calendar.isDateInYesterday(date) { return "hier" }
        return dayShort.string(from: date)
    }

    /// Rappel futur : jour + heure (ex « jeu 3 · 08:45 ») pour la section « À venir ».
    static func upcomingLabel(_ date: Date?) -> String? {
        guard let date else { return nil }
        if ParisCalendar.calendar.isDateInTomorrow(date) { return "demain · " + hm.string(from: date) }
        return dayShortTime.string(from: date)
    }

    static let hm: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Paris"); f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"; return f
    }()
    private static let dayShort: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Paris"); f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d"; return f
    }()
    private static let dayShortTime: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Paris"); f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d · HH:mm"; return f
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
        if task.destination == .local && task.localList == .work { return "briefcase" }
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

/// Ligne de rappel Apple dans la zone du jour : cocher (fait) ou décaler à demain, chaque action
/// demandant un 2e clic de confirmation (anti mis-clic). Les rappels en retard pulsent doucement.
private struct ReminderRowView: View {
    let item: TodayItem
    let timeText: String?
    let onComplete: () -> Void
    let onPostpone: () -> Void

    private enum Pending { case complete, postpone }
    @State private var pending: Pending?
    @State private var pulse = false
    @State private var expanded = false

    private var overdue: Bool {
        guard let d = item.date else { return false }
        return d < Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let pending {
                HStack(spacing: 8) {
                    Image(systemName: pending == .complete ? "checkmark.circle.fill" : "calendar.badge.clock")
                        .font(.caption).foregroundStyle(pending == .complete ? Color.green : Color.orange).frame(width: 14)
                    Text(item.title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                    Button(pending == .complete ? "Valider ?" : "Demain ?") {
                        if pending == .complete { onComplete() } else { onPostpone() }
                        self.pending = nil
                    }
                    .buttonStyle(.borderedProminent).controlSize(.mini)
                    .tint(pending == .complete ? .green : .orange)
                    Button { self.pending = nil } label: { Image(systemName: "xmark").font(.system(size: 9)) }
                        .buttonStyle(.borderless).controlSize(.mini).foregroundStyle(.secondary)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Button { pending = .complete } label: {
                        Image(systemName: "circle").font(.caption).foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain).frame(width: 14).help("Marquer comme fait")
                    if let timeText {
                        Text(timeText).font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(overdue ? Color.orange : Color.secondary)
                    } else {
                        Text("journée").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    // Titre cliquable : se déplie en entier (clic) ; texte complet aussi au survol.
                    Text(item.title).font(.system(size: 12)).foregroundStyle(.primary)
                        .lineLimit(expanded ? nil : 1)
                        .fixedSize(horizontal: false, vertical: expanded)
                        .contentShape(Rectangle())
                        .onTapGesture { withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() } }
                    Spacer(minLength: 4)
                    Button { pending = .postpone } label: {
                        Image(systemName: "arrow.right.to.line").font(.system(size: 10))
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Décaler à demain")
                }
                if expanded, let sub = item.subtitle, !sub.isEmpty {
                    Text(sub).font(.system(size: 10)).foregroundStyle(.tertiary).padding(.leading, 22)
                }
            }
        }
        .help(item.title)
        .padding(.vertical, 2).padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.orange.opacity(overdue ? (pulse ? 0.22 : 0.07) : 0))
        )
        .onAppear {
            guard overdue else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

// MARK: - Travail : ligne et en-tête de groupe

/// Ligne du panneau Travail. La priorité se lit par la FORME (barres de signal remplies 1→3),
/// la couleur ne fait que renforcer « haute » : lisible aussi en daltonisme et en thème sombre.
private struct WorkRow: View {
    let task: TaskRecord
    let dueLabel: String?
    let onToggle: () -> Void
    let onPriority: (Priority?) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(task.isDone ? Color.green : Color.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 16)
            .padding(.top, 1)
            .accessibilityLabel(task.isDone ? "Marquer non faite" : "Marquer faite")

            Menu {
                Button { onPriority(.haut) } label: { Label("Haute", systemImage: "cellularbars") }
                Button { onPriority(.moyen) } label: { Label("Moyenne", systemImage: "cellularbars") }
                Button { onPriority(.bas) } label: { Label("Basse", systemImage: "cellularbars") }
                Divider()
                Button("Aucune") { onPriority(nil) }
            } label: {
                Image(systemName: "cellularbars", variableValue: barsValue)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(barsStyle)
                    .frame(width: 16, height: 16)
            }
            // .button + .plain : seul style de Menu macOS qui respecte la couleur du label
            // (.borderlessButton la repeint en noir/blanc, la priorité haute perdait son rose).
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.top, 1)
            .help("Priorité : \(priorityName)")
            .accessibilityLabel("Priorité \(priorityName)")

            Text(task.text)
                .font(.system(size: 13))
                .strikethrough(task.isDone)
                .foregroundStyle(task.isDone ? .secondary : .primary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 6)

            if let dueLabel {
                Text(dueLabel)
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .opacity(task.isDone ? 0.7 : 1)
    }

    private var barsValue: Double {
        // Paliers nets sur l'icône à 4 barres : basse 1, moyenne 2, haute 4 (écart lisible d'un coup d'œil).
        switch task.priority { case .haut: return 1; case .moyen: return 0.5; case .bas: return 0.25; case nil: return 0 }
    }
    private var barsStyle: AnyShapeStyle {
        switch task.priority {
        case .haut: return AnyShapeStyle(Color.pink)
        case .moyen: return AnyShapeStyle(.secondary)
        case .bas, nil: return AnyShapeStyle(.tertiary)
        }
    }
    private var priorityName: String {
        switch task.priority { case .haut: return "haute"; case .moyen: return "moyenne"; case .bas: return "basse"; case nil: return "aucune" }
    }
}

/// En-tête repliable d'un groupe client : chevron, nom, nombre de tâches ouvertes.
private struct WorkGroupHeader: View {
    let name: String
    let open: Int
    let isCollapsed: Bool
    let isUnassigned: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isUnassigned ? .secondary : .primary)
                    .italic(isUnassigned)
                    .lineLimit(1)
                Spacer()
                if open > 0 {
                    Text("\(open)").font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(open) tâche\(open > 1 ? "s" : ""), \(isCollapsed ? "replié" : "déplié")")
    }
}
