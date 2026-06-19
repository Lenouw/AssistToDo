//
//  ContentView.swift
//  AssistToDoiOS
//
//  Racine : un seul écran = le second cerveau (tâches synchronisées + agenda iCloud du jour).
//  Bouton de capture héros. Réglages via l'engrenage. Pas d'onglet : la liste de tâches est
//  la raison d'être de l'app ; les courses sont reléguées dans les Réglages (copier-coller).
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSettings = false
    @State private var showCaptures = false

    var body: some View {
        NavigationStack {
            ListsView()
                .navigationTitle("AssistToDo")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showCaptures = true } label: {
                            Image(systemName: "waveform")
                        }
                        .accessibilityLabel("Captures (historique vocal)")
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Réglages")
                    }
                }
                // Bandeau SOUS la barre de nav (ne masque pas l'engrenage).
                .safeAreaInset(edge: .top) {
                    if !model.transcriberReady { modelLoadingBanner }
                }
        }
        .overlay(alignment: .bottom) {
            CaptureButton { model.autoStartCapture = false; model.showCapture = true }
                .padding(.bottom, 24)
        }
        .sheet(isPresented: $model.showCapture) {
            CaptureView(autoStart: model.autoStartCapture)
                .presentationDetents([.height(360)])
                .environmentObject(model)
                .environmentObject(model.capture)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(model)
                .environmentObject(model.store)
        }
        .sheet(isPresented: $showCaptures) {
            CapturesView(store: model.captureStore, processor: model.captureProcessor)
        }
    }

    /// Bandeau non bloquant pendant le téléchargement/chargement du modèle de transcription.
    /// Affiche un pourcentage réel pendant le download (1er lancement) pour ne pas faire croire à un bug.
    @ViewBuilder private var modelLoadingBanner: some View {
        switch model.transcriberReadiness {
        case .downloading(let fraction):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Téléchargement du modèle de transcription… \(Int(fraction * 100)) %")
                        .font(.caption)
                    Spacer()
                }
                ProgressView(value: fraction)
                Text("1er lancement uniquement (~480 Mo). Garde l'app ouverte.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.thinMaterial)
        case .preparing:
            banner(icon: nil, "Préparation du modèle… (presque prêt)")
        case .failed:
            banner(icon: "exclamationmark.triangle.fill",
                   "Échec du chargement du modèle. Relance l'app (vérifie ta connexion).")
        case .ready:
            EmptyView()
        }
    }

    private func banner(icon: String?, _ text: String) -> some View {
        HStack(spacing: 8) {
            if let icon { Image(systemName: icon).foregroundStyle(.orange) }
            else { ProgressView().controlSize(.small) }
            Text(text).font(.caption)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.thinMaterial)
    }
}

/// Gros bouton micro flottant pour lancer une capture manuelle.
private struct CaptureButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "mic.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(Circle().fill(Color.accentColor))
                .shadow(radius: 8, y: 3)
        }
        .accessibilityLabel("Nouvelle note vocale")
    }
}
