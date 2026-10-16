//
//  SyncStatusViews.swift
//  AssistToDoiOS
//
//  État de la synchro Toudou rendu visible : une ligne dans les Réglages et un bandeau sur
//  l'écran principal quand la synchro est coupée ou en échec. Avant, un jeton manquant ou une
//  erreur réseau laissaient l'iPhone désynchronisé du Mac sans aucun signe.
//

import SwiftUI
import AssistToDoKit

/// Ligne d'état, sous la connexion Toudou dans les Réglages.
struct SyncStatusLine: View {
    @ObservedObject var sync: SyncCoordinator

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Color.atdInk)
                if let detail { Text(detail).font(.caption).foregroundStyle(Color.atdInkSecondary) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch sync.status {
        case .notConfigured: return "link.badge.plus"
        case .syncing:       return "arrow.triangle.2.circlepath"
        case .ok:            return "checkmark.circle.fill"
        case .failed:        return "exclamationmark.triangle.fill"
        }
    }
    private var color: Color {
        switch sync.status {
        case .notConfigured, .failed: return .orange
        case .syncing:                return Color.atdInkSecondary
        case .ok:                     return Color.atdSuccess
        }
    }
    private var title: String {
        switch sync.status {
        case .notConfigured: return "Synchro coupée : jeton Toudou absent"
        case .syncing:       return "Synchronisation…"
        case .ok(let at, _): return "Synchronisé \(Self.relative(at))"
        case .failed:        return "La synchro a échoué"
        }
    }
    private var detail: String? {
        switch sync.status {
        case .notConfigured: return "Colle le jeton puis touche « Enregistrer la connexion »."
        case .syncing:       return nil
        case .ok(_, let n):  return "\(n) tâche\(n > 1 ? "s" : "") reçue\(n > 1 ? "s" : "") du serveur"
        case .failed(let at, let m): return "\(m) (\(Self.relative(at)))"
        }
    }

    static func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.unitsStyle = .full
        return Date().timeIntervalSince(d) < 30 ? "à l'instant" : f.localizedString(for: d, relativeTo: Date())
    }
}

/// Bandeau de l'écran principal, affiché seulement si la synchro est coupée ou en échec.
struct SyncProblemBanner: View {
    @ObservedObject var sync: SyncCoordinator
    let onTap: () -> Void

    var body: some View {
        if let text {
            Button(action: onTap) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                    Text(text).font(.caption).foregroundStyle(Color.atdInk)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Color.atdInkSecondary)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(.thinMaterial)
            }
            .buttonStyle(.plain)
        }
    }

    private var text: String? {
        switch sync.status {
        case .notConfigured: return "Synchro avec le Mac coupée : ajoute ton jeton Toudou"
        case .failed:        return "Synchro avec le Mac en échec : voir les Réglages"
        default:             return nil
        }
    }
}
