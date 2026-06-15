//
//  CapturesView.swift
//  AssistToDo
//
//  Historique des captures (filet de sécurité) : statut, transcript/résumé, écoute audio,
//  re-traitement (re-transcrire) / re-routage seul, suppression.
//

import SwiftUI
import AVFoundation
import AssistToDoKit

struct CapturesView: View {
    @ObservedObject var store: CaptureStore
    let processor: CaptureProcessor
    @State private var player: AVAudioPlayer?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Captures").font(.headline)
                Spacer()
                Button { store.reload() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("Rafraîchir")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()

            if store.captures.isEmpty {
                Spacer()
                Text("Aucune capture pour l'instant").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(store.captures, id: \.id) { c in row(c) }
                    .listStyle(.inset)
            }
        }
        .frame(minWidth: 420, minHeight: 360)
    }

    private func row(_ c: CaptureRecord) -> some View {
        HStack(alignment: .top, spacing: 10) {
            statusIcon(c.status)
                .frame(width: 16).padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(c.parsedSummary ?? c.transcript ?? "(en attente de traitement)")
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text("\(Self.df.string(from: c.createdAt)) · \(statusLabel(c.status))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            Menu {
                Button("Re-traiter (re-transcrire)") { Task { await processor.process(captureId: c.id, now: Date()) } }
                Button("Re-router seulement") { Task { await processor.reroute(captureId: c.id, now: Date()) } }
                Button("Écouter l'audio") { play(c) }
                Divider()
                Button("Supprimer", role: .destructive) { delete(c) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton).fixedSize()
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func statusIcon(_ s: CaptureStatus) -> some View {
        switch s {
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        default: Image(systemName: "clock").foregroundStyle(.secondary)
        }
    }

    private func statusLabel(_ s: CaptureStatus) -> String {
        switch s {
        case .recorded: return "enregistré"
        case .transcribing: return "transcription…"
        case .transcribed: return "transcrit"
        case .routing: return "routage…"
        case .done: return "fait"
        case .failed(let stage, _): return "échec (\(stage))"
        }
    }

    private func play(_ c: CaptureRecord) {
        let url = CapturePaths.url(for: c.audioFilename)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    private func delete(_ c: CaptureRecord) {
        try? FileManager.default.removeItem(at: CapturePaths.url(for: c.audioFilename))
        store.delete(id: c.id)
    }

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Paris"); f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d MMM HH:mm"; return f
    }()
}
