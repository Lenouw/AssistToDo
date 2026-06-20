//
//  CapturesView.swift
//  AssistToDoiOS
//
//  Historique des captures (filet de sécurité) : statut, transcript/résumé, écoute audio,
//  re-traitement (re-transcrire) / re-routage seul, suppression. Aucune idée perdue.
//

import SwiftUI
import AVFoundation
import AssistToDoKit

struct CapturesView: View {
    @ObservedObject var store: CaptureStore
    let processor: CaptureProcessor
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVAudioPlayer?

    var body: some View {
        NavigationStack {
            Group {
                if store.captures.isEmpty {
                    ContentUnavailableView("Aucune capture", systemImage: "waveform",
                        description: Text("Tes notes vocales apparaissent ici, même en cas d'échec de traitement."))
                } else {
                    List { ForEach(store.captures, id: \.id) { row($0) } }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(Color.atdBg.ignoresSafeArea())
                }
            }
            .navigationTitle("Captures")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { store.reload() } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Rafraîchir")
                }
                ToolbarItem(placement: .topBarTrailing) { Button("OK") { dismiss() } }
            }
        }
    }

    private func row(_ c: CaptureRecord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Circle().fill(Color.atdAccentSoft).frame(width: 38, height: 38)
                    .overlay(Image(systemName: "waveform").foregroundStyle(Color.atdAccent))
                Circle().fill(dotColor(c.status)).frame(width: 11, height: 11)
                    .overlay(Circle().stroke(Color.atdSurface, lineWidth: 2))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(c.parsedSummary ?? c.transcript ?? "(en attente de traitement)")
                    .foregroundStyle(Color.atdInk)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                Text("\(Self.df.string(from: c.createdAt)) · \(statusLabel(c.status))")
                    .font(.caption).foregroundStyle(Color.atdInkSecondary)
            }
            Spacer(minLength: 6)
            Menu {
                Button { Task { await processor.process(captureId: c.id, now: Date()) } } label: {
                    Label("Re-traiter (re-transcrire)", systemImage: "arrow.clockwise")
                }
                Button { Task { await processor.reroute(captureId: c.id, now: Date()) } } label: {
                    Label("Re-router seulement", systemImage: "arrow.triangle.branch")
                }
                if !c.audioFilename.isEmpty {
                    Button { play(c) } label: { Label("Écouter l'audio", systemImage: "play.circle") }
                }
                Divider()
                Button(role: .destructive) { delete(c) } label: { Label("Supprimer", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundStyle(Color.atdInkSecondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.atdSurface))
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { delete(c) } label: { Label("Supprimer", systemImage: "trash") }
        }
    }

    private func dotColor(_ s: CaptureStatus) -> Color {
        switch s {
        case .done:   return .atdSuccess
        case .failed: return .atdRecording
        default:      return .atdInkTertiary
        }
    }

    private func statusLabel(_ s: CaptureStatus) -> String {
        switch s {
        case .recorded:    return "enregistré"
        case .transcribing: return "transcription…"
        case .transcribed: return "transcrit"
        case .routing:     return "routage…"
        case .done:        return "fait"
        case .failed(let stage, _): return "échec (\(stage))"
        }
    }

    private func play(_ c: CaptureRecord) {
        let url = CapturePaths.url(for: c.audioFilename)
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    private func delete(_ c: CaptureRecord) {
        if !c.audioFilename.isEmpty {
            try? FileManager.default.removeItem(at: CapturePaths.url(for: c.audioFilename))
        }
        store.delete(id: c.id)
    }

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Europe/Paris"); f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEE d MMM HH:mm"; return f
    }()
}
