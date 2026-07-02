//
//  ContentView.swift
//  AssistToDoiOS
//
//  Racine : un seul écran = le second cerveau (tâches synchronisées + agenda iCloud du jour).
//  Bouton de capture héros. Réglages via l'engrenage. Pas d'onglet : la liste de tâches est
//  la raison d'être de l'app ; les courses sont reléguées dans les Réglages (copier-coller).
//

import SwiftUI
import UIKit
import AssistToDoKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: TaskStore
    @State private var showSettings = false
    @State private var showCaptures = false
    @State private var showShopping = false
    /// Recontrôle la présence de la clé OpenRouter quand on ferme les Réglages.
    @State private var routingKeyMissing = false
    @AppStorage("routingEnabled") private var routingEnabled = true

    var body: some View {
        NavigationStack {
            ListsView()
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Liste de courses : visible dès qu'elle contient des articles (fini l'enterrement
                    // dans les Réglages — au supermarché, c'est 1 tap).
                    if !store.shoppingItems.isEmpty {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { showShopping = true } label: {
                                Image(systemName: "cart")
                                    .overlay(alignment: .topTrailing) {
                                        Text("\(store.shoppingItems.count)")
                                            .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                            .padding(3).background(Circle().fill(Color.atdAccent))
                                            .offset(x: 8, y: -8)
                                    }
                            }
                            .accessibilityLabel("Liste de courses")
                        }
                    }
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
                // Bandeaux SOUS la barre de nav (ne masquent pas l'engrenage).
                .safeAreaInset(edge: .top) {
                    VStack(spacing: 1) {
                        if !model.transcriberReady { modelLoadingBanner }
                        if routingKeyMissing { routingInactiveBanner }
                        // Avancement du traitement en arrière-plan : rien ne tombe dans l'oubli.
                        CapturePipelineStrip(captureStore: model.captureStore) { showCaptures = true }
                    }
                }
        }
        .onAppear { refreshRoutingBanner() }
        .onChange(of: showSettings) { _, open in if !open { refreshRoutingBanner() } }
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                // Toast de confirmation / annulation : reste ~6 s, même après fermeture de la feuille.
                if let toast = model.undoToast {
                    undoToastView(toast)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                CaptureButton { model.autoStartCapture = true; model.showCapture = true }
            }
            .padding(.bottom, 24)
            .animation(.spring(duration: 0.35), value: model.undoToast?.id)
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
        .sheet(isPresented: $showShopping) {
            ShoppingListView()
                .environmentObject(store)
        }
    }

    private func refreshRoutingBanner() {
        routingKeyMissing = routingEnabled && !KeychainStore.hasAPIKey
    }

    /// Confirmation en bas d'écran : ce qui vient d'être fait + « Annuler » (faute de manip).
    private func undoToastView(_ toast: AppModel.UndoToast) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(toast.message)
                .font(.footnote).foregroundStyle(Color.atdInk)
                .lineLimit(4).multilineTextAlignment(.leading)
            if let undo = toast.undo {
                Button {
                    undo()
                    model.undoToast = nil
                } label: {
                    Text("Annuler").font(.footnote.weight(.semibold)).foregroundStyle(Color.atdAccent)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.atdSurfaceRaised)
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4))
        .padding(.horizontal, 24)
    }

    /// Sans clé OpenRouter, TOUT tombe dans « À faire » sans structuration. Avant : échec silencieux
    /// (l'app avait l'air cassée). Maintenant : bandeau explicite, tap = Réglages.
    private var routingInactiveBanner: some View {
        Button { showSettings = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("Routage inactif : ajoute ta clé OpenRouter")
                    .font(.caption).foregroundStyle(Color.atdInk)
                Spacer()
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Color.atdInkSecondary)
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(.thinMaterial)
        }
        .buttonStyle(.plain)
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

/// Bandeau d'avancement du pipeline de capture : montre EN CLAIR ce qui se passe en arrière-plan
/// (en attente de transcription / transcription / rangement / à rejouer). Tap = écran Captures.
/// Invisible quand tout est traité — n'apparaît que quand quelque chose « mouline ».
private struct CapturePipelineStrip: View {
    @ObservedObject var captureStore: CaptureStore
    let openCaptures: () -> Void

    var body: some View {
        if let status = pipelineText {
            Button(action: openCaptures) {
                HStack(spacing: 8) {
                    if status.spinning { ProgressView().controlSize(.small) }
                    else { Image(systemName: "clock.arrow.circlepath").font(.caption).foregroundStyle(.orange) }
                    Text(status.text).font(.caption).foregroundStyle(Color.atdInk)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Color.atdInkSecondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.thinMaterial)
            }
            .buttonStyle(.plain)
        }
    }

    private var pipelineText: (text: String, spinning: Bool)? {
        let captures = captureStore.captures
        var recorded = 0, working = 0, toReplay = 0
        for c in captures {
            switch c.status {
            case .recorded: recorded += 1
            case .transcribing, .transcribed, .routing: working += 1
            case .failed: toReplay += 1
            case .done: if c.needsEnrichment { toReplay += 1 }
            }
        }
        if working > 0 { return ("Traitement en cours… (transcription / rangement)", true) }
        if recorded > 0 { return ("\(recorded) capture\(recorded > 1 ? "s" : "") en attente de transcription", true) }
        if toReplay > 0 { return ("\(toReplay) capture\(toReplay > 1 ? "s" : "") à rejouer (voir Captures)", false) }
        return nil
    }
}

/// Liste de courses accessible d'un tap (panier de la toolbar). Articles cochables au magasin ;
/// « Copier » exporte le restant (pour coller dans la note Apple partagée).
private struct ShoppingListView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    @State private var copiedFlash = false

    var body: some View {
        NavigationStack {
            List {
                if store.shoppingItems.isEmpty {
                    Text("Vide. Dicte des articles (« il faut du lait »), ils s'ajoutent ici.")
                        .font(.callout).foregroundStyle(Color.atdInkSecondary)
                }
                ForEach(store.shoppingItems) { item in
                    HStack(spacing: 12) {
                        Button {
                            Haptics.light()
                            store.toggleDone(id: item.id)
                        } label: {
                            Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 21))
                                .foregroundStyle(item.isDone ? Color.atdSuccess : Color.atdInkTertiary)
                        }
                        .buttonStyle(.plain)
                        Text(item.text)
                            .strikethrough(item.isDone)
                            .foregroundStyle(item.isDone ? Color.atdInkTertiary : Color.atdInk)
                        Spacer(minLength: 0)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { store.delete(id: item.id) } label: {
                            Label("Supprimer", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color.atdBg.ignoresSafeArea())
            .navigationTitle("Courses")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = store.shoppingItems
                            .filter { !$0.isDone }.map { $0.text }.joined(separator: "\n")
                        copiedFlash = true
                    } label: { Image(systemName: "doc.on.doc") }
                    .disabled(store.shoppingItems.allSatisfy { $0.isDone })
                    .accessibilityLabel("Copier la liste")
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        for id in store.shoppingItems.map(\.id) { store.delete(id: id) }
                    } label: { Image(systemName: "trash") }
                    .disabled(store.shoppingItems.isEmpty)
                    .accessibilityLabel("Vider la liste")
                }
                ToolbarItem(placement: .topBarTrailing) { Button("OK") { dismiss() } }
            }
            .alert("Liste copiée", isPresented: $copiedFlash) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Colle-la où tu veux (Notes Apple, message…).")
            }
        }
    }
}

/// Gros bouton micro flottant pour lancer une capture manuelle.
/// Anneau de respiration au repos : signale « prêt à t'écouter ».
private struct CaptureButton: View {
    let action: () -> Void
    @State private var breathing = false

    var body: some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Image(systemName: "mic.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color.atdAccent))
                .overlay(
                    Circle().stroke(Color.atdAccent, lineWidth: 2)
                        .scaleEffect(breathing ? 1.25 : 1)
                        .opacity(breathing ? 0 : 0.6)
                        .animation(.easeInOut(duration: 2.4).repeatForever(autoreverses: false), value: breathing)
                )
                .shadow(color: Color.atdAccent.opacity(0.4), radius: 16, y: 6)
        }
        .accessibilityLabel("Nouvelle note vocale")
        .onAppear { breathing = true }
    }
}
