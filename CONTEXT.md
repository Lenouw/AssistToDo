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
- 2026-06-10 (soir, suite) : app complète testée de bout en bout (capture vocale → tâche). Polish : liste en panneau auto-fermant depuis la droite (tap=liste, hold=capture), sections Aujourd'hui/À venir/Faites + couleurs priorité + horaires, onboarding 1er lancement, README. Corrections : auto-gain audio (normalisation au pic avant Whisper, seuil VAD 0.004) pour micro faible ; Keychain `kSecAttrAccessibleAfterFirstUnlock` (+ note signature stable pour éviter re-prompt). Notifications interactives : boutons report 5/10/15/30 min + À demain + Fait ✓ (UNNotificationCategory + delegate). Backlog : connexion Apple Reminders (EventKit) à explorer plus tard.

- 2026-06-10 (après-midi) : implémentation Phase 0 + Phase 1 sur branche `feat/assisttodo-v1`, en subagent-driven (un sous-agent par tâche, TDD). Package SwiftPM `AssistToDoCore` créé avec tout le cœur métier testé : modèles (Priority, ParsedTask, TaskRecord), ParisCalendar (helpers TZ), DateResolver (dates/heures relatives FR déterministes), ParseResponseDecoder (JSON LLM), ParsePromptBuilder, HallucinationFilter, RolloverEngine idempotent. **26 tests verts** (`swift test`). Revue finale faite : 1 bug corrigé (DateResolver renvoyait une heure passée pour "à 8h" quand déjà dépassée → reporte au lendemain). Clé OpenRouter validée, modèle `google/gemini-2.5-flash` testé et figé.
- 2026-06-10 (matin) : init projet (git + .gitignore Swift/Xcode). Brainstorming complet. 3 agents (recherche libs, idées produit, stress-test design). Design v1 validé + spec écrit. Plan d'implémentation écrit (`docs/superpowers/plans/2026-06-10-assisttodo-v1.md`).

## Ou on en est
Phase 0 + Phase 1 (cœur métier) terminées et testées (26 tests verts).
Phase 2 en cours. Projet Xcode créé à `AssistToDo/AssistToDo.xcodeproj` (équipe TQVHUV8MZY, Sign to Run Locally, App Sandbox: Audio Input + Outgoing Connections, LSUIElement=YES, NSMicrophoneUsageDescription). 3 packages liés: AssistToDoCore (local `../AssistToDoCore`), WhisperKit, KeyboardShortcuts. Groupe synchronisé (drop .swift = auto-ajouté).
- Task 2.1 (app .accessory + lien core) : **build-vérifiée**, commitée (`3e94872`).
- Task 2.2 (SwiftData TaskEntity/TaskStore, MenuBarController + badge, ListView/ListWindow, rollover) + Réglages (SettingsView: hotkey recorder, modèle Whisper, clé OpenRouter→Keychain, login item, permissions micro/notif) + HotkeyManager : écrites, commitées WIP (`d561a9e`), **PAS encore build-vérifiées**.

**REPRISE = ouvrir Xcode (`AssistToDo/AssistToDo.xcodeproj`), `⌘R`, corriger erreurs de build éventuelles, puis dérouler le test :** menu-bar avec badge + Réglages, set hotkey, coller clé API (Enregistrer), autoriser micro/notifs, Debug›Ajouter tâches test (badge), Ouvrir liste + cocher, maintenir ⌃⌥Espace + relâcher → ouvre la liste (preuve hotkey). Une fois vert, commit propre puis **Task 2.4 (AudioCapture + ondes + VAD)**, puis 2.5 (WhisperKit), 2.6 (OpenRouter+toast+notif réelle), 2.7 (onboarding).

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

## Idées / backlog (à explorer plus tard)
- [ ] **Connexion Apple Reminders** (sync bidirectionnelle via EventKit) — l'utilisateur veut pouvoir relier ses tâches AssistToDo à l'app Rappels d'Apple. Faisabilité à rechercher plus tard (EventKit `EKReminder`, permission Rappels). Pas urgent.
- [ ] Récurrence vocale ("tous les lundis"), projets/recherche, récap matinal, extension Raycast, companion Apple Watch.
- [ ] Undo capture : re-presser le raccourci dans les 3s annule la dernière tâche.
- [ ] Benchmark Whisper tiny/base/small sur le MacBook Air, figer le défaut.

## Problemes connus
Aucun bloquant. App fonctionnelle de bout en bout.

## Notes pour la prochaine session
- Le spec de référence : `docs/superpowers/specs/2026-06-10-assisttodo-design.md` (tout le design détaillé y est).
- L'utilisateur veut le feel Wispr Flow : HUD central, ondes audio live (preuve que le micro capte), pastille "prêt". Sa hantise = parler dans le vide et perdre une pensée.
- Adaptation : la "petite planète" de Wispr (= connexion internet) devient chez nous un globe indiquant si OpenRouter est joignable, car la transcription est locale (marche offline).
- Ne PAS commencer à coder sans le go explicite de l'utilisateur sur le spec.
- Règle OpenRouter (CLAUDE.md) : ne jamais inventer l'ID modèle, le lister + tester via l'API avant de l'intégrer.
