//
//  PerfView.swift
//  AssistToDoiOS
//
//  Réglages > Mesures : les temps des dernières captures (lancement, micro, modèle,
//  transcription, routage). Sert à mesurer le démarrage à froid sur le vrai iPhone, que le
//  Mac ne peut pas lire directement. « Copier » met le tableau dans le presse-papiers.
//

import SwiftUI
import UIKit
import AssistToDoKit

struct PerfView: View {
    @State private var runs: [PerfRun] = []
    @State private var copied = false

    /// Objectif fixé par Florian : le micro enregistre moins de 300 ms après le tap, même à froid.
    private let micTargetMs: Double = 300

    var body: some View {
        List {
            if runs.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Aucune mesure pour l'instant").font(.headline)
                        Text("Pour un test à froid : ferme l'app (balaie-la vers le haut dans le sélecteur d'apps), attends quelques secondes, puis lance une capture avec le bouton Action ou le Centre de contrôle. Dicte une phrase, laisse s'arrêter, puis reviens ici.")
                            .font(.subheadline).foregroundStyle(Color.atdInkSecondary)
                    }
                    .padding(.vertical, 6)
                }
            }
            ForEach(runs) { run in
                Section {
                    ForEach(sorted(run), id: \.self) { e in
                        row(run, e)
                    }
                    if let outcome = run.outcome {
                        HStack {
                            Text("Résultat").foregroundStyle(Color.atdInkSecondary)
                            Spacer()
                            Text(outcome).multilineTextAlignment(.trailing).foregroundStyle(Color.atdInkSecondary)
                        }
                        .font(.footnote)
                    }
                } header: {
                    header(run)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.atdBg.ignoresSafeArea())
        .navigationTitle("Mesures")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { copyAll() } label: { Label("Copier les mesures", systemImage: "doc.on.doc") }
                    Button(role: .destructive) { Perf.clearRuns(); runs = [] } label: {
                        Label("Effacer", systemImage: "trash")
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .disabled(runs.isEmpty)
            }
        }
        .overlay(alignment: .bottom) {
            if copied {
                Text("Mesures copiées")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Color.atdSurfaceRaised, in: Capsule())
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                    .padding(.bottom, 24)
                    .transition(.opacity)
            }
        }
        .onAppear { runs = Perf.loadRuns() }
    }

    private func sorted(_ run: PerfRun) -> [PerfEntry] {
        run.entries.sorted { $0.ms < $1.ms }
    }

    private func header(_ run: PerfRun) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(run.cold ? "À froid" : "App déjà en mémoire")
                .font(.footnote.weight(.semibold)).foregroundStyle(Color.atdInk)
            Text("\(Self.dateFmt.string(from: run.date)), \(run.trigger)\(run.prewarmed ? ", préchauffée par iOS" : "")")
                .font(.caption).foregroundStyle(Color.atdInkSecondary)
                .textCase(nil)
        }
        .textCase(nil)
    }

    private func row(_ run: PerfRun, _ e: PerfEntry) -> some View {
        let t = e.ms - run.referenceMs
        let isMic = e.step == .micFirstBuffer
        let ok = t <= micTargetMs
        return HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 1) {
                Text(e.step.label)
                    .font(isMic ? .body.weight(.semibold) : .body)
                    .foregroundStyle(Color.atdInk)
                if let note = e.note {
                    Text(note).font(.caption).foregroundStyle(Color.atdInkTertiary)
                }
                if isMic {
                    Text(ok ? "Objectif 300 ms tenu" : "Objectif 300 ms dépassé")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(ok ? Color.atdSuccess : Color.atdRecording)
                }
            }
            Spacer()
            Text(Self.format(t))
                .font(.body.monospacedDigit().weight(isMic ? .semibold : .regular))
                .foregroundStyle(isMic ? (ok ? Color.atdSuccess : Color.atdRecording) : Color.atdInkSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private static func format(_ ms: Double) -> String {
        abs(ms) >= 10_000 ? String(format: "%.1f s", ms / 1000) : "\(Int(ms.rounded())) ms"
    }

    private func copyAll() {
        UIPasteboard.general.string = runs.map(Perf.text).joined(separator: "\n\n")
        withAnimation(.easeOut(duration: 0.2)) { copied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            withAnimation(.easeOut(duration: 0.2)) { copied = false }
        }
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR"); f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "d MMM 'à' HH:mm:ss"; return f
    }()
}
