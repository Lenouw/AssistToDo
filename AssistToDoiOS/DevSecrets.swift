//
//  DevSecrets.swift
//  AssistToDoiOS
//
//  CONFORT DE DÉV uniquement. Colle ici tes secrets UNE FOIS : à chaque build DEBUG,
//  s'ils manquent dans le Keychain, ils sont injectés automatiquement (plus de re-saisie).
//
//  ⚠️ Ce fichier est neutralisé côté git par `git update-index --skip-worktree` : tes
//  valeurs restent LOCALES et ne sont JAMAIS committées. Ne fais jamais `git add -f` dessus.
//  Tout est sous `#if DEBUG` → les builds Release (TestFlight/App Store) n'embarquent rien.
//

#if DEBUG
enum DevSecrets {
    /// URL Toudou (laisse vide pour la prod par défaut). Ex : "https://toudou-one.vercel.app"
    static let toudouURL = ""
    /// Token de synchronisation Toudou.
    static let toudouToken = ""
    /// Clé API OpenRouter ("sk-or-...").
    static let openRouterKey = ""
}
#endif
