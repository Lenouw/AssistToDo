//
//  ContentView.swift
//  AssistToDoiOS
//
//  Racine : onglets (Cerveau · Courses · Réglages) + bouton de capture proéminent.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            ListsView()
                .tabItem { Label("Cerveau", systemImage: "brain.head.profile") }
            ShoppingView()
                .tabItem { Label("Courses", systemImage: "cart") }
            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
        }
        .overlay(alignment: .bottom) {
            CaptureButton { model.autoStartCapture = false; model.showCapture = true }
                .padding(.bottom, 54)   // au-dessus de la barre d'onglets
        }
        .safeAreaInset(edge: .top) {
            if !model.transcriberReady { modelLoadingBanner }
        }
        .sheet(isPresented: $model.showCapture) {
            CaptureView(autoStart: model.autoStartCapture)
                .presentationDetents([.height(360)])
        }
    }

    /// Bandeau non bloquant pendant le téléchargement/chargement du modèle de transcription.
    private var modelLoadingBanner: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Préparation du modèle de transcription… (1er lancement)")
                .font(.caption)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
