//
//  ListsView.swift
//  AssistToDoiOS
//
//  Vue de dispatch (parité Mac) : 4 zones — À faire (liste interne synced), Rappels Apple
//  (live iCloud : dûs aujourd'hui/en retard + à venir), Agenda Apple (live, aujourd'hui),
//  Fait (historique coché). Deux dispositions commutables (Réglages) : segmentée ou empilée.
//  Gestes de swipe répliqués du Mac (Fait/Modifier/Déplacer · Supprimer/Demain).
//

import SwiftUI
import AssistToDoCore
import AssistToDoKit

enum DispatchZone: String, CaseIterable, Identifiable {
    case todo = "À faire"
    case code = "Code"
    case reminders = "Rappels"
    case agenda = "Agenda"
    case done = "Fait"
    var id: String { rawValue }
}

/// Disposition de l'écran (typée plutôt que String brute, partagée avec les Réglages).
enum AppLayout: String { case segmented, stacked }

struct ListsView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var model: AppModel
    @AppStorage("iosLayout") private var layout: AppLayout = .segmented

    @State private var zone: DispatchZone = .todo
    @State private var agenda: [TodayItem] = []          // événements aujourd'hui → J+3 (filtrés/colorés)
    @State private var futureReminders: [TodayItem] = [] // rappels datés à venir (demain → +14 j)
    @State private var editingTask: TaskRecord?
    @State private var editText = ""
    @State private var showDone = false

    var body: some View {
        Group {
            if layout == .stacked { stackedLayout } else { segmentedLayout }
        }
        .task { await store.refreshToday(); await refreshReminders(); await refreshAgenda() }
        .refreshable {
            SyncCoordinator.shared?.syncNow()
            await store.refreshToday()
            await refreshReminders()
            await refreshAgenda()
        }
        .onChange(of: zone) { _, z in
            Task {
                if z == .reminders { await store.refreshToday(); await refreshReminders() }
                if z == .agenda { await refreshAgenda() }
            }
        }
        .onChange(of: model.agendaVisibilityVersion) { _, _ in
            Task { await refreshAgenda() }   // un agenda a été masqué/affiché dans les Réglages
        }
        .alert("Modifier", isPresented: editingBinding) {
            TextField("Texte", text: $editText)
            Button("Annuler", role: .cancel) { editingTask = nil }
            Button("OK") {
                if let t = editingTask { store.updateText(id: t.id, text: editText) }
                editingTask = nil
            }
        }
    }

    // MARK: - Disposition segmentée

    private var segmentedLayout: some View {
        VStack(spacing: 0) {
            todayHeader
            Picker("Zone", selection: $zone) {
                ForEach(DispatchZone.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal).padding(.bottom, 8)

            List {
                switch zone {
                case .todo:      todoRows
                case .code:      codeRows
                case .reminders: reminderRows
                case .agenda:    eventRows
                case .done:      doneRows
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(Color.atdBg.ignoresSafeArea())
    }

    // MARK: - Disposition empilée (À faire + Rappels + Agenda en scroll, Fait via l'horloge)

    private var stackedLayout: some View {
        VStack(spacing: 0) {
            todayHeader
            List {
                Section("À faire") { todoRows }
                Section("Claude Code") { codeRows }
                Section("Rappels") { reminderRows }
                Section("Agenda") { eventRows }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.atdBg.ignoresSafeArea())
        }
        .background(Color.atdBg.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showDone = true } label: { Image(systemName: "clock.arrow.circlepath") }
                    .accessibilityLabel("Historique (fait)")
            }
        }
        .sheet(isPresented: $showDone) {
            NavigationStack {
                List { doneRows }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.atdBg.ignoresSafeArea())
                    .navigationTitle("Fait")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("OK") { showDone = false } } }
            }
        }
    }

    // MARK: - Contenus des zones

    /// En-tête : la journée de l'utilisateur, pas le nom de l'app.
    private var todayHeader: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Aujourd'hui").font(.largeTitle.bold()).foregroundStyle(Color.atdInk)
            Text(Self.headerDate.string(from: Date()).capitalizedFirst)
                .font(.subheadline).foregroundStyle(Color.atdInkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 12)
        .background(Color.atdBg)
    }

    @ViewBuilder private var todoRows: some View {
        // Rappels iCloud à traiter ÉPINGLÉS en tête du cerveau (parité Mac) : l'écran du matin
        // répond direct à « qu'est-ce que je dois faire là ? ». En disposition segmentée seulement
        // (en empilée, la section Rappels est déjà visible en dessous).
        if layout == .segmented, !store.openReminders.isEmpty {
            pinnedReminders
        }
        // À faire = vidage de cerveau SEUL (les tâches Claude Code ont leur propre onglet).
        let items = store.thoughts
            .filter { $0.destination == .local && $0.localList == .braindump && !$0.isDone }
            .sorted(by: byPriorityThenRecent)
        if items.isEmpty && store.openReminders.isEmpty {
            emptyState("Cerveau vide", "Maintiens le micro pour vider ce que tu as en tête.", "sparkles")
        }
        ForEach(items) { taskRow($0) }
    }

    /// Jusqu'à 3 rappels ouverts (les en-retard d'abord), avec accès à la zone Rappels complète.
    @ViewBuilder private var pinnedReminders: some View {
        let startToday = ParisCalendar.startOfDay(for: Date())
        let open = store.openReminders.sorted { a, b in
            let ao = (a.date ?? .distantFuture) < startToday, bo = (b.date ?? .distantFuture) < startToday
            if ao != bo { return ao }                                   // en retard d'abord
            return (a.date ?? .distantFuture) < (b.date ?? .distantFuture)
        }
        sectionLabel("Rappels à traiter (\(open.count))")
        ForEach(open.prefix(3)) { reminderRow($0) }
        if open.count > 3 {
            Button {
                zone = .reminders
            } label: {
                Text("Voir les \(open.count) rappels →")
                    .font(.caption.weight(.medium)).foregroundStyle(Color.atdAccent)
            }
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
    }

    @ViewBuilder private var codeRows: some View {
        let items = store.codeTasks
            .filter { !$0.isDone }
            .sorted(by: byPriorityThenRecent)
        if items.isEmpty {
            emptyState("Pas de tâche de code", "Dicte « Claude Code : … » pour en ajouter ici.",
                       "chevron.left.forwardslash.chevron.right")
        }
        ForEach(items) { taskRow($0) }
    }

    /// Ordre d'affichage : haute en premier, puis moyenne, non priorisée, basse en dernier.
    private func priorityRank(_ r: TaskRecord) -> Int {
        switch r.priority {
        case .haut:  return 0
        case .moyen: return 1
        case nil:    return 2
        case .bas:   return 3
        }
    }

    /// Tri stable : priorité d'abord, puis le plus récent (créé) à priorité égale (la majorité
    /// des tâches n'a pas de priorité → sans clé secondaire, `sort` non stable les fait sautiller).
    private func byPriorityThenRecent(_ a: TaskRecord, _ b: TaskRecord) -> Bool {
        let ra = priorityRank(a), rb = priorityRank(b)
        return ra != rb ? ra < rb : a.createdAt > b.createdAt
    }

    @ViewBuilder private var doneRows: some View {
        let items = (store.thoughts + store.codeTasks).filter { $0.isDone }
            .sorted { ($0.doneAt ?? .distantPast) > ($1.doneAt ?? .distantPast) }
        if items.isEmpty && store.archived.isEmpty { emptyRow("Rien de coché pour l'instant") }
        if !items.isEmpty {
            sectionLabel("Dernières 24 h")
            ForEach(items) { taskRow($0) }
            // Une tâche cochée reste 24h puis s'archive (et quitte Toudou). Bouton pour ne pas attendre.
            Button {
                Haptics.light()
                store.archiveAllDoneNow()
            } label: {
                Label("Archiver les tâches faites maintenant", systemImage: "archivebox")
                    .font(.callout).foregroundStyle(Color.atdAccent)
            }
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
        }
        // L'Archive : rien ne disparaît jamais. Restaurer = re-décocher (revient dans sa liste
        // et sur Toudou) ; supprimer = définitif.
        if !store.archived.isEmpty {
            sectionLabel("Archive (\(store.archived.count))")
            ForEach(store.archived) { archivedRow($0) }
        }
    }

    private func archivedRow(_ rec: TaskRecord) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "archivebox").font(.caption).foregroundStyle(Color.atdInkTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.text).strikethrough().foregroundStyle(Color.atdInkTertiary)
                if let d = rec.doneAt {
                    Text("Faite le ") .font(.caption2).foregroundStyle(Color.atdInkTertiary)
                    + Text(d, style: .date).font(.caption2).foregroundStyle(Color.atdInkTertiary)
                }
            }
            Spacer(minLength: 0)
            if rec.localList == .code {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.caption2).foregroundStyle(Color.atdCode.opacity(0.6))
            }
        }
        .padding(.vertical, 3)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { store.toggleDone(id: rec.id) } label: { Label("Restaurer", systemImage: "arrow.uturn.backward") }.tint(.green)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { store.delete(id: rec.id) } label: { Label("Supprimer", systemImage: "trash") }
        }
        .contextMenu {
            Button("Restaurer (non faite)") { store.toggleDone(id: rec.id) }
            Button("Supprimer", role: .destructive) { store.delete(id: rec.id) }
        }
    }

    @ViewBuilder private var reminderRows: some View {
        if !EventKitService.shared.hasRemindersAccess {
            permissionRow("Autoriser les rappels") {
                await model.requestRemindersAndCalendar(); await store.refreshToday()
            }
        } else {
            // Rappels iCloud OUVERTS (aujourd'hui + en retard + sans date ; les futurs vivent dans
            // l'app Rappels, pas ici). En retard = à traiter d'abord, le plus récent en tête (les
            // vieux rappels de 2021 tombent en bas). iCloud reste la source, l'app fait rouler.
            let open = store.openReminders
            let startToday = ParisCalendar.startOfDay(for: Date())
            let overdue = open.filter { ($0.date ?? .distantFuture) < startToday }
                .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
            let today = open.filter { d in
                guard let dt = d.date else { return false }; return dt >= startToday
            }
            let undated = open.filter { $0.date == nil }
            if open.isEmpty && futureReminders.isEmpty {
                emptyState("Rien à traiter", "Tes rappels du jour, en retard et à venir apparaissent ici.", "bell")
            }
            if !overdue.isEmpty { sectionLabel("En retard"); ForEach(overdue) { reminderRow($0) } }
            if !today.isEmpty { sectionLabel("Aujourd'hui"); ForEach(today) { reminderRow($0) } }
            if !undated.isEmpty { sectionLabel("Sans date"); ForEach(undated) { reminderRow($0) } }
            // À VENIR : ce que tu viens de dicter pour demain+ est visible ici (créé dans Rappels
            // Apple, notifié par iCloud le jour J). Sans ça, un rappel futur semblait « disparu ».
            if !futureReminders.isEmpty { sectionLabel("À venir"); ForEach(futureReminders) { reminderRow($0) } }
        }
    }

    @ViewBuilder private var eventRows: some View {
        if !EventKitService.shared.hasCalendarAccess {
            permissionRow("Autoriser le calendrier") {
                await model.requestRemindersAndCalendar(); await refreshAgenda()
            }
        } else if agenda.isEmpty {
            emptyRow("Aucun événement à venir")
        } else {
            // Groupé par jour (aujourd'hui → J+3), un en-tête par jour. On ne recrée pas l'agenda,
            // juste un aperçu déroulant des 4 prochains jours.
            let groups = Dictionary(grouping: agenda) { $0.dayStart ?? .distantPast }
            ForEach(groups.keys.sorted(), id: \.self) { day in
                sectionLabel(Self.dayLabel(day))
                ForEach(groups[day] ?? []) { eventRow($0) }
            }
        }
    }

    // MARK: - Lignes

    private func taskRow(_ rec: TaskRecord) -> some View {
        let high = rec.priority == .haut && !rec.isDone
        let low = rec.priority == .bas
        return HStack(alignment: .top, spacing: 12) {
            Button {
                toggleTask(rec)
            } label: {
                Image(systemName: rec.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21))
                    .foregroundStyle(rec.isDone ? Color.atdSuccess : Color.atdInkTertiary)
                    .symbolEffect(.bounce, value: rec.isDone)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // Priorité haute = drapeau chaud + texte semibold → saute aux yeux.
                    if high {
                        Image(systemName: "flag.fill").font(.caption2).foregroundStyle(Color.atdPriorityHigh)
                    }
                    if rec.localList == .code {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.caption2).foregroundStyle(Color.atdCode)
                    }
                    Text(rec.text)
                        .font(high ? .body.weight(.semibold) : .body)
                        .strikethrough(rec.isDone)
                        .foregroundStyle(rec.isDone ? Color.atdInkTertiary
                                         : (low ? Color.atdInkSecondary : Color.atdInk))
                }
                taskMeta(rec)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        // Priorité haute : fond de ligne légèrement teinté (hiérarchie sans bordure latérale).
        .listRowBackground(high ? Color.atdPriorityHigh.opacity(0.06) : Color.clear)
        // Swipe gauche→droite (parité Mac) : Fait · Modifier · Déplacer.
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { toggleTask(rec) } label: { Label("Fait", systemImage: "checkmark.circle") }.tint(.green)
            if rec.destination != .reminders {
                Button { startEditing(rec) } label: { Label("Modifier", systemImage: "pencil") }.tint(.blue)
            }
            if rec.destination == .local {
                Button { store.moveToList(id: rec.id, to: rec.localList == .code ? .braindump : .code) } label: {
                    Label(rec.localList == .code ? "Cerveau" : "Code", systemImage: "arrow.left.arrow.right")
                }.tint(.purple)
            }
        }
        // Swipe droite→gauche (parité Mac) : Supprimer · Demain.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { store.delete(id: rec.id) } label: { Label("Supprimer", systemImage: "trash") }
            if rec.destination == .local {
                Button { store.postponeToTomorrow(id: rec.id) } label: { Label("Demain", systemImage: "arrow.uturn.forward") }.tint(.orange)
            }
        }
        .contextMenu {
            Button(rec.isDone ? "Marquer non faite" : "Marquer faite") { toggleTask(rec) }
            if rec.destination != .reminders { Button("Modifier") { startEditing(rec) } }
            if rec.destination == .local {
                Button(rec.localList == .code ? "Vers Vidage de cerveau" : "Vers Claude Code") {
                    store.moveToList(id: rec.id, to: rec.localList == .code ? .braindump : .code)
                }
                Button("Reporter à demain") { store.postponeToTomorrow(id: rec.id) }
            }
            Divider()
            Button("Supprimer", role: .destructive) { store.delete(id: rec.id) }
        }
    }

    private func reminderRow(_ item: TodayItem) -> some View {
        let overdue = (item.date ?? .distantFuture) < ParisCalendar.startOfDay(for: Date())
        return HStack(alignment: .top, spacing: 12) {
            Button { Haptics.light(); completeReminder(item.id) } label: {
                Image(systemName: "circle").font(.system(size: 21))
                    .foregroundStyle(overdue ? Color.atdRecording : Color.atdInkTertiary)
                    .symbolEffect(.pulse, options: .repeating, isActive: overdue)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).foregroundStyle(Color.atdInk)
                HStack(spacing: 4) {
                    if item.date != nil {
                        Image(systemName: overdue ? "exclamationmark.circle.fill" : "bell")
                        (overdue ? Text("En retard · ").bold() : Text("")) + Text(Self.reminderWhen(item))
                    }
                    if let list = item.subtitle {
                        Text(item.date == nil ? list : "· \(list)")
                    }
                }
                .font(.caption)
                .foregroundStyle(overdue ? Color.atdRecording : Color.atdInkSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { completeReminder(item.id) } label: { Label("Fait", systemImage: "checkmark.circle") }.tint(.green)
        }
        // Le 2ᵉ geste indispensable du matin : reporter à demain (même heure), sans quitter l'app.
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { postponeReminder(item.id) } label: { Label("Demain", systemImage: "arrow.uturn.forward") }.tint(.orange)
        }
        .contextMenu {
            Button("Fait") { completeReminder(item.id) }
            Button("Reporter à demain") { postponeReminder(item.id) }
        }
    }

    /// Événement en mini-bloc horaire : heure à gauche, repère COLORÉ selon l'agenda source, titre +
    /// nom de l'agenda (pour distinguer studio / Fluffy Cat Hotel / perso même à la même heure).
    private func eventRow(_ item: TodayItem) -> some View {
        let color = item.colorHex.flatMap { Color(hexString: $0) } ?? Color.atdZoneAgenda
        return HStack(spacing: 12) {
            Group {
                if let d = item.date {
                    Text(d, style: .time).font(.subheadline.weight(.semibold)).foregroundStyle(Color.atdInk)
                } else {
                    Text("Jour").font(.caption.weight(.medium)).foregroundStyle(Color.atdInkSecondary)
                }
            }
            .frame(width: 50, alignment: .leading)
            Capsule().fill(color).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).foregroundStyle(Color.atdInk)
                if let cal = item.calendarTitle {
                    HStack(spacing: 5) {
                        Circle().fill(color).frame(width: 6, height: 6)
                        Text(cal).font(.caption2).foregroundStyle(Color.atdInkTertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private func permissionRow(_ label: String, _ action: @escaping () async -> Void) -> some View {
        Button { Task { await action() } } label: {
            Label(label, systemImage: "lock.open")
        }
    }

    /// Méta sous le libellé : n'affiche une échéance que pour les rappels datés (sinon = bruit).
    @ViewBuilder private func taskMeta(_ rec: TaskRecord) -> some View {
        if rec.destination == .reminders, let d = rec.remindAt ?? rec.dueDate {
            HStack(spacing: 4) {
                Image(systemName: "bell")
                Text(d, style: .date)
            }
            .font(.caption).foregroundStyle(Color.atdInkSecondary)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text).foregroundStyle(Color.atdInkSecondary).font(.callout)
    }

    /// Vide invitant (au lieu d'une ligne grise) pour la zone principale.
    private func emptyState(_ title: String, _ subtitle: String, _ icon: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(Color.atdAccent.opacity(0.55))
            Text(title).font(.headline).foregroundStyle(Color.atdInk)
            Text(subtitle).font(.subheadline).foregroundStyle(Color.atdInkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 36)
        .listRowBackground(Color.clear)
    }

    private static let headerDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.timeZone = ParisCalendar.tz
        f.dateFormat = "EEEE d MMMM"; return f
    }()

    /// Petit en-tête de sous-groupe dans une liste (Aujourd'hui / À venir / En retard / un jour).
    private func sectionLabel(_ t: String) -> some View {
        Text(t.uppercased())
            .font(.caption2.weight(.semibold)).foregroundStyle(Color.atdInkTertiary)
            .listRowBackground(Color.clear).listRowSeparator(.hidden)
    }

    private static func dayLabel(_ d: Date) -> String {
        let cal = ParisCalendar.calendar
        let today = ParisCalendar.startOfDay(for: Date())
        if cal.isDate(d, inSameDayAs: today) { return "Aujourd'hui" }
        if let tmr = cal.date(byAdding: .day, value: 1, to: today), cal.isDate(d, inSameDayAs: tmr) { return "Demain" }
        return dayLabelFmt.string(from: d).capitalizedFirst
    }
    private static let dayLabelFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.timeZone = ParisCalendar.tz
        f.dateFormat = "EEEE d MMM"; return f
    }()

    /// Échéance d'un rappel en FRANÇAIS, avec l'heure si le rappel en a une (« jeu. 3 juil. à 15:00 »).
    private static func reminderWhen(_ item: TodayItem) -> String {
        guard let d = item.date else { return "" }
        let f = item.hasTime ? reminderDayTimeFmt : reminderDayFmt
        return f.string(from: d).capitalizedFirst
    }
    private static let reminderDayFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.timeZone = ParisCalendar.tz
        f.dateFormat = "EEE d MMM"; return f
    }()
    private static let reminderDayTimeFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.timeZone = ParisCalendar.tz
        f.dateFormat = "EEE d MMM 'à' HH:mm"; return f
    }()

    // MARK: - Actions / données

    private var editingBinding: Binding<Bool> {
        Binding(get: { editingTask != nil }, set: { if !$0 { editingTask = nil } })
    }

    private func startEditing(_ task: TaskRecord) {
        editText = task.text
        editingTask = task
    }

    // Helpers Kit : rafraîchissent store.openReminders, ce qui re-programme aussi les relances
    // de rappels en retard (sink dans AppModel). Chaque validation = toast avec « Annuler »
    // (faute de manip → retour en arrière en 1 tap).
    private func completeReminder(_ id: String) {
        Task { await store.completeReminder(id: id); await refreshReminders() }
        model.showToast("Rappel fait ✓") { [weak store] in
            EventKitService.shared.setReminderCompleted(id: id, completed: false)
            Task { await store?.refreshToday(); await refreshReminders() }
        }
    }

    private func postponeReminder(_ id: String) {
        Haptics.light()
        Task { await store.postponeReminderToTomorrow(id: id); await refreshReminders() }
        model.showToast("Rappel reporté à demain")
    }

    /// Coche/décoche une tâche ; à la coche, propose l'annulation.
    private func toggleTask(_ rec: TaskRecord) {
        Haptics.light()
        store.toggleDone(id: rec.id)
        if !rec.isDone {   // rec = état AVANT le tap → on vient de la marquer faite
            model.showToast("Fait ✓ · \(rec.text)") { [weak store] in
                store?.toggleDone(id: rec.id)
            }
        }
    }

    private func refreshReminders() async {
        futureReminders = await EventKitService.shared.fetchFutureReminders(days: 14)
    }

    private func refreshAgenda() async {
        let hidden = Set(UserDefaults.standard.stringArray(forKey: "hiddenCalendars") ?? [])
        agenda = await EventKitService.shared.fetchUpcomingEvents(days: 4, hidden: hidden)
    }
}

private extension String {
    /// "vendredi 20 juin" → "Vendredi 20 juin".
    var capitalizedFirst: String { isEmpty ? self : prefix(1).uppercased() + dropFirst() }
}
