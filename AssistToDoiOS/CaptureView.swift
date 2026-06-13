//
//  CaptureView.swift
//  AssistToDoiOS
//
//  Capture vocale : maintenir pour parler, relâcher pour transcrire. Si lancée par un
//  déclencheur (Action Button / Siri / widget), démarre automatiquement et un appui arrête.
//

import SwiftUI

struct CaptureView: View {
    let autoStart: Bool
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var capture: CaptureController
    @Environment(\.dismiss) private var dismiss

    @State private var pressStart: Date?
    @State private var micDenied = false
    /// Une capture a réellement démarré → on referme la feuille quand elle revient à l'état repos.
    @State private var hasStarted = false

    var body: some View {
        VStack(spacing: 24) {
            statusText
            waveform
            controlButton
            hint
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { if autoStart { await beginAutoStart() } }
        .onChange(of: capture.phase) { _, phase in
            // Referme la feuille une fois la capture terminée (ajouté / ignoré / annulé).
            if phase == .idle, pressStart == nil, hasStarted { dismiss() }
        }
        .alert("Micro non autorisé", isPresented: $micDenied) {
            Button("OK", role: .cancel) { dismiss() }
        } message: {
            Text("Autorise le micro dans Réglages > AssistToDo pour dicter tes notes.")
        }
    }

    // MARK: - Sous-vues

    @ViewBuilder private var statusText: some View {
        switch capture.phase {
        case .idle, .preparing: Text("Prêt").font(.headline).foregroundStyle(.secondary)
        case .listening:        Text("À l'écoute…").font(.headline)
        case .transcribing:     Text("Transcription…").font(.headline)
        case .result:           Text(capture.transcript).font(.body).multilineTextAlignment(.center)
        case .added:            addedView
        case .ignored:          Text("Rien à créer").font(.headline).foregroundStyle(.secondary)
        case .error(let m):     Text(m).font(.headline).foregroundStyle(.red)
        }
    }

    private var addedView: some View {
        VStack(spacing: 6) {
            ForEach(capture.addedSummaries, id: \.self) { Text($0).font(.callout) }
        }
    }

    private var waveform: some View {
        let active = capture.phase == .listening
        return RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor.opacity(active ? 0.25 + Double(capture.level) * 0.6 : 0.12))
            .frame(height: 64)
            .overlay(
                Image(systemName: active ? "waveform" : "waveform.path")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                    .scaleEffect(1 + CGFloat(active ? capture.level : 0) * 0.5)
                    .animation(.easeOut(duration: 0.1), value: capture.level)
            )
            .padding(.horizontal)
    }

    private var controlButton: some View {
        Group {
            if autoStart {
                Button { capture.end() } label: {
                    Label("Terminer", systemImage: "stop.fill").font(.headline)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Circle()
                    .fill(capture.phase == .listening ? Color.red : Color.accentColor)
                    .frame(width: 80, height: 80)
                    .overlay(Image(systemName: "mic.fill").font(.system(size: 30)).foregroundStyle(.white))
                    .gesture(holdGesture)
            }
        }
    }

    @ViewBuilder private var hint: some View {
        if !autoStart {
            Text("Maintiens pour parler, relâche pour ajouter")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Gestes / logique

    private var holdGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard pressStart == nil else { return }
                pressStart = Date()
                Task { await startPressCapture() }
            }
            .onEnded { _ in
                let held = pressStart.map { Date().timeIntervalSince($0) } ?? 0
                pressStart = nil
                if held < 0.4 { capture.cancel() } else { capture.end() }
            }
    }

    private func startPressCapture() async {
        guard await ensureMic() else { return }
        hasStarted = true
        capture.begin()
    }

    private func beginAutoStart() async {
        model.autoStartCapture = false
        guard await ensureMic() else { return }
        hasStarted = true
        capture.begin()
    }

    private func ensureMic() async -> Bool {
        let ok = await model.requestMicrophone()
        if !ok { micDenied = true }
        return ok
    }
}
