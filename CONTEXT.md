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
- 2026-06-10 (après-midi) : implémentation Phase 0 + Phase 1 sur branche `feat/assisttodo-v1`, en subagent-driven (un sous-agent par tâche, TDD). Package SwiftPM `AssistToDoCore` créé avec tout le cœur métier testé : modèles (Priority, ParsedTask, TaskRecord), ParisCalendar (helpers TZ), DateResolver (dates/heures relatives FR déterministes), ParseResponseDecoder (JSON LLM), ParsePromptBuilder, HallucinationFilter, RolloverEngine idempotent. **26 tests verts** (`swift test`). Revue finale faite : 1 bug corrigé (DateResolver renvoyait une heure passée pour "à 8h" quand déjà dépassée → reporte au lendemain). Clé OpenRouter validée, modèle `google/gemini-2.5-flash` testé et figé.
- 2026-06-10 (matin) : init projet (git + .gitignore Swift/Xcode). Brainstorming complet. 3 agents (recherche libs, idées produit, stress-test design). Design v1 validé + spec écrit. Plan d'implémentation écrit (`docs/superpowers/plans/2026-06-10-assisttodo-v1.md`).

## Ou on en est
Phase 0 + Phase 1 (cœur métier, package `AssistToDoCore`) **terminées, testées (26 tests), commitées** sur la branche `feat/assisttodo-v1`. 
Prochaine étape = **Phase 2 (app Xcode)** : nécessite Xcode GUI + le Mac de Florian (créer le projet, accorder permissions micro/notif, build, vérif). Les sous-agents CLI ne peuvent pas faire cette phase seuls. À reprendre avec Florian aux commandes d'Xcode.

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
