//
//  CaptureView.swift
//  AssistToDoiOS
//
//  Capture vocale : maintenir pour parler, relâcher pour transcrire. Si lancée par un
//  déclencheur (Action Button / Siri / widget), démarre automatiquement et un appui arrête.
//

import SwiftUI
import AssistToDoKit

struct CaptureView: View {
    let autoStart: Bool
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var capture: CaptureController
    @Environment(\.dismiss) private var dismiss

    @State private var pressStart: Date?
    @State private var micDenied = false
    /// Une capture a réellement démarré → on referme la feuille quand elle revient à l'état repos.
    @State private var hasStarted = false
    /// Autorisation micro demandée À L'APPARITION (pas pendant le geste) pour éviter la course
    /// permission-async ↔ relâchement. nil = en cours, true/false = réponse.
    @State private var micGranted: Bool?

    /// Tampon glissant des dernières amplitudes (waveform façon Wispr/Superwhisper).
    private let barCount = 30
    @State private var levels: [Float] = Array(repeating: 0, count: 30)

    var body: some View {
        VStack(spacing: 22) {
            statusText
            waveform
            controlButton
            hint
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.atdSurfaceRaised.ignoresSafeArea())
        .task { await prepare() }
        .onChange(of: capture.level) { _, lvl in pushLevel(lvl) }
        .onChange(of: capture.phase) { _, phase in
            switch phase {
            case .listening:
                Haptics.tap()                                       // retour de début de capture
                levels = Array(repeating: 0, count: barCount)
            case .added:
                Haptics.success()                                   // confirmation d'ajout
            default:
                break
            }
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
        case .idle, .preparing:
            Text("Prêt").font(.title3.weight(.semibold)).foregroundStyle(Color.atdInkSecondary)
        case .listening:
            HStack(spacing: 8) {
                Circle().fill(Color.atdRecording).frame(width: 9, height: 9)
                    .opacity(0.9).modifier(Pulse())
                Text("À l'écoute").font(.title3.weight(.semibold)).foregroundStyle(Color.atdInk)
            }
        case .transcribing:
            Text("Je transcris…").font(.title3.weight(.semibold)).foregroundStyle(Color.atdInk)
        case .result:
            Text(capture.transcript).font(.body).foregroundStyle(Color.atdInk)
                .multilineTextAlignment(.center)
        case .added:
            addedView
        case .ignored:
            Text("Rien à créer ici").font(.title3.weight(.semibold)).foregroundStyle(Color.atdInkSecondary)
        case .error(let m):
            Text(m).font(.headline).foregroundStyle(Color.atdRecording)
        }
    }

    private var addedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 30)).foregroundStyle(Color.atdSuccess)
                .symbolEffect(.bounce, value: capture.addedSummaries.count)
            ForEach(capture.addedSummaries, id: \.self) {
                Text($0).font(.callout).foregroundStyle(Color.atdInk)
            }
        }
    }

    private var waveform: some View {
        let active = capture.phase == .listening
        return HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, lvl in
                Capsule()
                    .fill(active ? Color.atdAccent : Color.atdAccent.opacity(0.22))
                    .frame(width: 3, height: max(3, CGFloat(min(1, lvl)) * 56))
            }
        }
        .frame(height: 64).frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.08), value: levels)
        .opacity(capture.phase == .result || capture.phase == .added ? 0 : 1)
        .animation(.easeOut(duration: 0.4), value: capture.phase)
        .padding(.horizontal)
    }

    private func pushLevel(_ v: Float) {
        levels.append(v)
        if levels.count > barCount { levels.removeFirst(levels.count - barCount) }
    }

    private var controlButton: some View {
        Group {
            if autoStart {
                Button { capture.end() } label: {
                    Label("Terminer", systemImage: "stop.fill").font(.headline)
                }
                .buttonStyle(.borderedProminent).tint(Color.atdAccent)
            } else {
                Circle()
                    .fill(capture.phase == .listening ? Color.atdRecording : Color.atdAccent)
                    .frame(width: 84, height: 84)
                    // Halo audio-réactif pendant l'écoute (intensité = niveau).
                    .overlay(
                        Circle().stroke(Color.atdRecording.opacity(0.5), lineWidth: 3)
                            .scaleEffect(capture.phase == .listening ? 1 + CGFloat(capture.level) * 0.5 : 1)
                            .opacity(capture.phase == .listening ? 1 : 0)
                            .animation(.easeOut(duration: 0.1), value: capture.level)
                    )
                    .overlay(Image(systemName: "mic.fill").font(.system(size: 30)).foregroundStyle(.white))
                    .gesture(holdGesture)
            }
        }
    }

    @ViewBuilder private var hint: some View {
        if autoStart {
            Text("Parle, ça s'arrête tout seul. (ou « Terminer »)")
                .font(.caption).foregroundStyle(.secondary)
        } else {
            Text("Maintiens pour parler, relâche pour ajouter")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - Gestes / logique

    private var holdGesture: some Gesture {
        // Geste SYNCHRONE : la permission micro est déjà résolue (prepare()), donc begin()/end()
        // ne traversent aucun await → pas de relâchement traité avant le démarrage réel.
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard pressStart == nil, micGranted == true else { return }
                pressStart = Date()
                hasStarted = true
                capture.begin()
            }
            .onEnded { _ in
                guard let start = pressStart else { return }   // appui sans démarrage → on ignore
                let held = Date().timeIntervalSince(start)
                pressStart = nil
                if held < 0.4 { capture.cancel() } else { capture.end() }
            }
    }

    /// Demande le micro une seule fois à l'apparition ; en mode déclencheur, démarre la capture.
    private func prepare() async {
        let ok = await model.requestMicrophone()
        micGranted = ok
        guard ok else { micDenied = true; return }
        if autoStart {
            model.autoStartCapture = false
            hasStarted = true
            capture.begin(autoStop: true)   // mains libres : s'arrête seul au silence
        }
    }
}

/// Pulsation douce en boucle (point d'enregistrement « qui respire »).
private struct Pulse: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(on ? 1.0 : 0.7)
            .opacity(on ? 1.0 : 0.5)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
