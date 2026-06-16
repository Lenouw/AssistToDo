# Contexte du projet

## Projet
AssistToDo · application macOS native de capture vocale éclair de tâches. Raccourci global maintenu, l'utilisateur parle, la voix est transcrite (offline) et structurée par LLM, puis ajoutée à une liste du jour. L'app ne vole jamais le focus de l'app active. Les tâches non cochées roulent au lendemain.

## Type
Application (macOS native, Swift/SwiftUI)

## Stack technique
Swift + SwiftUI · app menu-bar `.accessory` · WhisperKit (transcription streaming offline, modèle `base`) · KeyboardShortcuts (sindresorhus, raccourci global) · NSPanel non-activating (HUD) · SwiftData (persistance) · OpenRouter (parsing LLM du texte, clé fournie par l'utilisateur).
Cible : MacBook Air Apple Silicon, macOS 15.5 (Sequoia).

## Derniere mise a jour
2026-06-16 (v1.1.2 publiée)

## Ce qu'on a fait
- 2026-06-16 (après-midi) : **audit sécu + fonctionnement, puis v1.1.2**. Audit (2 sous-agents : test + revue de code). 🔴 trouvé : l'auto-update interne (`UpdateChecker.swift`) téléchargeait et installait/exécutait le `.zip` GitHub **sans vérifier l'intégrité** + retirait la quarantaine → risque supply-chain (RCE non confinée vu l'app dé-sandboxée). **Corrigé** : `scripts/release.sh` publie désormais `<zip>.sha256` ; l'updater télécharge ce checksum, recalcule `SHA256(zip)` (CryptoKit) et **refuse d'installer si mismatch ou checksum absent** (repli sur page manuelle, n'installe jamais un binaire non vérifié). 🟠 corrigé aussi : le script de swap passe les chemins en **arguments bash `$1/$2/$3`** (plus d'interpolation Swift) → plus d'injection shell via le nom du `.app`. Reste clean : aucune clé en dur (`git grep sk-or-v1` vide), secrets Keychain, TLS, échappement AppleScript. 58 tests verts, build OK. Commit `c1fbba0`, push main + feat/assisttodo-v1, **release GitHub v1.1.2** (DMG + ZIP + .sha256). ⚠️ La v1.1.1 utilise l'ancien updater non vérifié pour passer en v1.1.2 ; à partir de v1.1.2 → suivantes, chaque MAJ est vérifiée par SHA256.
- 2026-06-16 (matin/midi) : grosse session. **Filet de sécurité de capture** (« jamais perdre une idée ») livré en subagent-driven : chaque capture vocale enregistrée durablement (audio .caf en Application Support, jamais temporaryDirectory) + journal SwiftData `CaptureRecord` (statut recorded/transcribing/.../done/failed) + pipeline rejouable (`CaptureProcessor` : `process()`/`reroute()`, garde anti-concurrence, idempotent). UI **Captures** (historique, écouter, re-traiter, re-router, supprimer) accessible depuis le panneau de droite (icône onde) + barre de menus. Préchauffe WhisperKit en tâche de fond après load (corrige démarrage à froid ; `prewarm:true` dans la config CRASHAIT l'init → retiré). **Dé-sandbox** de l'app pour permettre l'auto-update (écrire dans /Applications). **Auto-update interne** (UpdateChecker : GitHub Releases → télécharge zip → remplace bundle → relance). Clé OpenRouter **par-installation** dans le Keychain (aucune clé embarquée ; chaque utilisateur, y compris un pote, met sa propre clé payante). Section Toudou **masquée par défaut** (sync perso avancée). Releases v1.0.0 → v1.1.0 → v1.1.1.
- 2026-06-10 (soir, suite) : app complète testée de bout en bout (capture vocale → tâche). Polish : liste en panneau auto-fermant depuis la droite (tap=liste, hold=capture), sections Aujourd'hui/À venir/Faites + couleurs priorité + horaires, onboarding 1er lancement, README. Corrections : auto-gain audio (normalisation au pic avant Whisper, seuil VAD 0.004) pour micro faible ; Keychain `kSecAttrAccessibleAfterFirstUnlock` (+ note signature stable pour éviter re-prompt). Notifications interactives : boutons report 5/10/15/30 min + À demain + Fait ✓ (UNNotificationCategory + delegate). Backlog : connexion Apple Reminders (EventKit) à explorer plus tard.

- 2026-06-10 (après-midi) : implémentation Phase 0 + Phase 1 sur branche `feat/assisttodo-v1`, en subagent-driven (un sous-agent par tâche, TDD). Package SwiftPM `AssistToDoCore` créé avec tout le cœur métier testé : modèles (Priority, ParsedTask, TaskRecord), ParisCalendar (helpers TZ), DateResolver (dates/heures relatives FR déterministes), ParseResponseDecoder (JSON LLM), ParsePromptBuilder, HallucinationFilter, RolloverEngine idempotent. **26 tests verts** (`swift test`). Revue finale faite : 1 bug corrigé (DateResolver renvoyait une heure passée pour "à 8h" quand déjà dépassée → reporte au lendemain). Clé OpenRouter validée, modèle `google/gemini-2.5-flash` testé et figé.
- 2026-06-10 (matin) : init projet (git + .gitignore Swift/Xcode). Brainstorming complet. 3 agents (recherche libs, idées produit, stress-test design). Design v1 validé + spec écrit. Plan d'implémentation écrit (`docs/superpowers/plans/2026-06-10-assisttodo-v1.md`).

## Ou on en est
**App v1.1.2 en prod, distribuée sur GitHub Releases (`Lenouw/AssistToDo`), dé-sandboxée, auto-update interne avec vérif SHA256.** Tout le flux marche de bout en bout : capture vocale → transcription (WhisperKit, modèle réglable, Distil Large v3 Turbo conseillé) → parsing LLM (OpenRouter `google/gemini-2.5-flash`) → routage (liste locale / Calendrier / Rappels / Notes). Filet de sécurité actif (captures durables + rejouables). 58 tests verts (Core 37 + Kit 21).

Architecture en 2 packages SwiftPM + l'app :
- `AssistToDoCore` : domaine pur testé (parsing, dates Paris, rollover, prompt builder).
- `AssistToDoKit` : couche app partagée Mac/iOS (Capture/ pipeline, Persistence/ stores SwiftData).
- `AssistToDo/AssistToDo.xcodeproj` : app macOS (UI, routeurs EventKit/Notes spécifiques Mac).

**Coordination Mac↔iOS** : 2 worktrees git du même repo (Mac = `feat/assisttodo-v1`, iOS = `feat/ios`) + fichier partagé `ASSISTTODO-HANDOFF.md` (hors worktrees) à lire avant de builder. La version iPhone se développe dans une AUTRE conversation.

**REPRISE** : app stable, rien de bloquant en cours. Prochaines pistes possibles = voir backlog ci-dessous. Pour publier une MAJ : bump `Info.plist`, `./scripts/release.sh`, `gh release create vX.Y.Z dist/*.dmg dist/*.zip dist/*.zip.sha256 --target main`.

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
- [ ] **Distribution + installateur GitHub + auto-update** (prochaine grosse session, demandé le 2026-06-12) :
  - Build **Release** de l'app, versionner (MARKETING_VERSION / CURRENT_PROJECT_VERSION).
  - Empaqueter en **DMG** (glisser vers /Applications) à mettre sur **GitHub Releases** pour le partager à un pote. Dépendances déjà statiquement liées dans le .app (pas de souci type FFMPEG).
  - **Décision clé à trancher** : compte Apple Developer **payant** (99 $/an) ? Si OUI → **signer Developer ID + notariser** = le pote ouvre l'app sans alerte Gatekeeper. Si NON → app non notarisée, le pote doit faire clic-droit → Ouvrir (ou retirer la quarantaine). 
  - **Modèle Whisper** : soit le bundler dans le .app (install 100% offline), soit garder le téléchargement au 1er run (réseau). À décider.
  - Le pote devra entrer **sa propre clé OpenRouter** (config, pas une dépendance). Ou import du fichier de préférences.
  - **Auto-update** : intégrer **Sparkle** (framework standard macOS) avec un **appcast** hébergé sur GitHub Releases (signature EdDSA des updates). Permet la MAJ auto + facile à publier.

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
