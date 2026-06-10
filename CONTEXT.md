# Contexte du projet

## Projet
AssistToDo · application macOS native de capture vocale éclair de tâches. Raccourci global maintenu, l'utilisateur parle, la voix est transcrite (offline) et structurée par LLM, puis ajoutée à une liste du jour. L'app ne vole jamais le focus de l'app active. Les tâches non cochées roulent au lendemain.

## Type
Application (macOS native, Swift/SwiftUI)

## Stack technique
Swift + SwiftUI · app menu-bar `.accessory` · WhisperKit (transcription streaming offline, modèle `base`) · KeyboardShortcuts (sindresorhus, raccourci global) · NSPanel non-activating (HUD) · SwiftData (persistance) · OpenRouter (parsing LLM du texte, clé fournie par l'utilisateur).
Cible : MacBook Air Apple Silicon, macOS 15.5 (Sequoia).

## Derniere mise a jour
2026-06-10

## Ce qu'on a fait
- 2026-06-10 : init projet (git + .gitignore Swift/Xcode). Brainstorming complet de l'idée. 3 agents (recherche libs open source, idées produit, stress-test du design). Design v1 validé en brainstorming et écrit dans `docs/superpowers/specs/2026-06-10-assisttodo-design.md`. Décisions tranchées : push-to-talk, transcription streaming, micro armé à l'appui, focus préservé d'abord, parsing LLM via OpenRouter avec fallback texte brut.

## Ou on en est
Phase design terminée. Spec écrit et en attente de revue finale de l'utilisateur avant d'écrire le plan d'implémentation. Aucun code applicatif encore. Pas de projet Xcode créé.

## Architecture et decisions
Voir le spec complet : `docs/superpowers/specs/2026-06-10-assisttodo-design.md`.
Décisions clés et pourquoi :
- **Transcription streaming** (pas batch) : sinon ~5-6s d'attente sur l'Air avec Whisper, ne serait pas "éclair".
- **Modèle `base`** (pas `small`) : compromis latence/RAM sur un Air, à benchmarker.
- **Micro armé à l'appui** (pas continu) : évite le voyant micro orange permanent, respect vie privée.
- **Focus préservé d'abord** : le toast ne devient éditable au clavier que sur interaction explicite, sinon il volerait le focus (contradiction avec l'objectif n°1).
- **Rollover idempotent au lancement/réveil** (pas Timer seul) : un Timer ne fire pas si l'Air dort à minuit. Calcul Europe/Paris explicite (piège DST récurrent).
- **Fallback texte brut si OpenRouter down** : ne jamais perdre une tâche à cause du réseau.
- **Permission micro à l'onboarding** : la popup TCC vole le focus, la demander dans le chemin de capture casserait la 1ère capture.

## Ce qu'il reste a faire
- [ ] Revue du spec par l'utilisateur (gate avant implémentation)
- [ ] Écrire le plan d'implémentation (skill writing-plans)
- [ ] Obtenir de l'utilisateur : clé API OpenRouter + ID modèle exact (à vérifier via l'API avant intégration)
- [ ] Créer le projet Xcode + SwiftPM (WhisperKit, KeyboardShortcuts)
- [ ] Implémenter les modules (voir spec section 8)
- [ ] Benchmarker les modèles Whisper `tiny`/`base`/`small` sur le MacBook Air réel
- [ ] Tests rollover heure d'été (UTC+2) et hiver (UTC+1)

## Problemes connus
Aucun (pas encore de code).

## Notes pour la prochaine session
- Le spec de référence : `docs/superpowers/specs/2026-06-10-assisttodo-design.md` (tout le design détaillé y est).
- L'utilisateur veut le feel Wispr Flow : HUD central, ondes audio live (preuve que le micro capte), pastille "prêt". Sa hantise = parler dans le vide et perdre une pensée.
- Adaptation : la "petite planète" de Wispr (= connexion internet) devient chez nous un globe indiquant si OpenRouter est joignable, car la transcription est locale (marche offline).
- Ne PAS commencer à coder sans le go explicite de l'utilisateur sur le spec.
- Règle OpenRouter (CLAUDE.md) : ne jamais inventer l'ID modèle, le lister + tester via l'API avant de l'intégrer.
