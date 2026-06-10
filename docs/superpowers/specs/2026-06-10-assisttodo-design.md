# AssistToDo · Design (spec v1)

Date : 2026-06-10
Statut : validé en brainstorming, en attente de revue utilisateur avant plan d'implémentation.

## 1. Vision

App macOS native de **capture vocale éclair de tâches**. Une pensée surgit pendant le travail, l'utilisateur maintient un raccourci global, parle, relâche : la tâche est transcrite, structurée par LLM, ajoutée à la liste du jour. L'app ne vole jamais le focus de l'app active. Le soir, les tâches non cochées roulent au lendemain.

Identité produit : **préservation du focus + friction quasi nulle + feedback visuel rassurant** (style Wispr Flow). La peur centrale à éliminer : parler dans le vide et perdre une pensée importante sans le savoir.

## 2. Contexte cible

- Dev solo. MacBook Air Apple Silicon, macOS 15.5 (Sequoia). Pas macOS 26 → APIs macOS 26 (SpeechTranscriber, Foundation Models) indisponibles.
- App distribuée et utilisée uniquement sur la machine de l'utilisateur (pas de App Store v1).
- Règles CLAUDE.md actives : app macOS native (jamais `killall` process système, désinstallation propre sans casser l'état système), timezone Europe/Paris explicite partout, jamais d'invention de données sensibles, pas de tiret long dans le copy visible.

## 3. Stack

| Brique | Choix | Raison |
|---|---|---|
| Langage / UI | Swift + SwiftUI | Natif, réactif, exigence de l'utilisateur |
| App type | Menu-bar `.accessory` (pas d'icône Dock), démarre au login | Toujours prête, discrète |
| Transcription | WhisperKit (argmaxinc), **streaming**, modèle `base` par défaut (benché `tiny`/`base`/`small` sur l'Air, configurable) | Offline, FR correct, gratuit, SwiftPM, real-time natif |
| Raccourci global | KeyboardShortcuts (sindresorhus) | keyUp/keyDown global vérifiés, rebindable, recorder SwiftUI |
| Fenêtre instant | `NSPanel` non-activating + `NSHostingView` | Spotlight/Maccy-style, ne vole pas le focus |
| Persistance | SwiftData, `VersionedSchema` dès le départ | Natif `@Query`, code minimal ; schéma versionné pour migrations |
| Parsing structuré | OpenRouter (API cloud) | Parsing FR intelligent. Clé API + ID modèle exact fournis par l'utilisateur, jamais inventés (règle CLAUDE.md OpenRouter : lister + tester l'ID avant intégration) |

Référence d'implémentation à lire : `p0deje/Maccy` (fenêtre flottante, hotkey, menu-bar, persistance).

## 4. Décisions tranchées (brainstorming)

1. **Push-to-talk** : maintien du raccourci = enregistre, relâche = valide. Défaut `⌃⌥Space`, rebindable.
2. **Transcription streaming live** : le texte apparaît au fil de la parole dans le HUD (pas batch après relâche).
3. **Micro armé à l'appui** (pas continu) : voyant micro ponctuel, respect vie privée. Court pré-roll pour limiter la perte des premiers ms.
4. **Focus préservé d'abord** : le toast ne vole jamais le focus (auto-commit). Édition clavier seulement après interaction explicite (clic/hover). Annulation = re-presser le raccourci.
5. **Parsing intelligent v1** : dates relatives, priorités, tags, split multi-tâches.
6. **LLM via OpenRouter** (cloud), avec fallback texte brut si réseau indisponible.
7. **Aperçu post-capture** : toast latéral ~3s.

## 5. Flow de capture

```
keyDown (maintien)
  ├─ AVAudioEngine démarre, tap audio actif (pré-roll court)
  ├─ HUD pill central s'affiche (<100ms) sur l'écran sous le curseur
  │    ├─ état textuel + pastille : "Prêt" (vert) quand permission micro OK ET modèle WhisperKit chargé ET tap actif
  │    ├─ ondes audio live (réagissent au volume) → preuve que le micro capte
  │    ├─ texte transcrit en streaming (au fil de la parole)
  │    └─ icône globe : OpenRouter joignable (vert) / offline (gris, fallback règles locales)
  │
keyUp (relâche)
  ├─ HUD se ferme
  ├─ finalisation transcription
  ├─ garde-fous hallucination (durée < ~1s rejetée, blacklist FR, score de confiance / no_speech_prob)
  ├─ si aucun son détecté (VAD) → toast rouge "Rien entendu, rien enregistré", pas de commit
  ├─ si audio présent mais transcription vide/rejetée → conserve l'audio brut + toast "Transcription ratée, audio conservé"
  ├─ sinon → OpenRouter parse (date / priorité / tags / split multi-tâches)
  │    └─ si parse échoue/timeout/offline → commit texte brut sans structure, re-parse différé. Jamais de tâche perdue.
  └─ toast latéral ~3s en haut-droite : tâche(s) + date détectée
       ├─ non-key par défaut (focus préservé) → auto-commit à 3s
       ├─ clic/hover → devient éditable au clavier (l'utilisateur a choisi d'interagir)
       └─ re-presser le raccourci dans les 3s = undo du dernier commit
```

### Garanties anti-perte (exigence centrale)
- Audio bufferisé dès keyDown.
- Voyant "Prêt" honnête : reflète l'état réel du chargement modèle, pas juste le micro.
- Aucun commit silencieux : tout échec produit un toast visible (rouge = rien gardé, orange = audio gardé).
- Aucune tâche perdue à cause du cloud : fallback texte brut systématique.

## 6. Liste & rollover

- Menu-bar : clic → fenêtre liste du jour. Badge = nombre de tâches restantes du jour.
- Item : case à cocher (cochée = barrée + son léger + archivée), affichage date d'échéance / priorité / tags.
- **Rollover idempotent** (pas un Timer seul) :
  - Calculé au lancement, au réveil système, et à l'ouverture de la fenêtre liste.
  - Algo : pour toute tâche non cochée dont `dueDate` (wall-clock Paris) < aujourd'hui Paris, avancer `dueDate` à aujourd'hui Paris et incrémenter `rolloverCount` une seule fois par jour calendaire Paris sauté.
  - Idempotence : clé "rollover déjà appliqué pour le jour Paris J" pour éviter le double-rollover (ouverture multiple le même jour).
  - Un Timer minuit est un bonus pour le cas app-ouverte, jamais la source de vérité.
  - **Timezone Europe/Paris explicite** partout (frontière minuit, "aujourd'hui"). Tests de validation en heure d'été (UTC+2) ET hiver (UTC+1) avant de figer.
- **Anti-zombie** : tâche reportée `rolloverCount >= 3` → marquée visuellement, proposée en décision (faire / replanifier / supprimer).

## 7. Modèle de données (SwiftData)

`Task`
- `id: UUID`
- `text: String` (texte affiché de la tâche)
- `createdAt: Date`
- `dueDate: Date?` (échéance, jour courant par défaut)
- `priority: Int?` (ou enum bas/moyen/haut)
- `tags: [String]`
- `isDone: Bool`
- `doneAt: Date?`
- `rolloverCount: Int` (défaut 0)
- `rawTranscript: String` (texte brut Whisper, pour ré-édition / re-parse / audit hallucination)
- `parseStatus: enum` { parsed, rawOnly, pending } (pour re-parse différé si OpenRouter était down)

`VersionedSchema` v1 défini dès le départ pour permettre des migrations sans corruption.

## 8. Modules (unités isolées)

| Module | Responsabilité | Dépend de |
|---|---|---|
| `HotkeyManager` | Enregistre le raccourci global, expose keyDown / keyUp | KeyboardShortcuts |
| `AudioCapture` | Démarre/arrête AVAudioEngine, tap, buffer, niveau (pour les ondes), VAD, gère reconfig device (AirPods, changement sample rate) | AVFoundation |
| `Transcriber` | Wrapper WhisperKit streaming, garde-fous hallucination, chargement/pré-chargement modèle, état "prêt" | WhisperKit |
| `Parser` | Texte → tâche(s) structurée(s) via OpenRouter, fallback texte brut, re-parse différé | OpenRouter, réseau |
| `TaskStore` | CRUD SwiftData, logique de rollover idempotent, anti-zombie | SwiftData |
| `CapturePanelController` | NSPanel non-activating, positionnement écran sous curseur, cycle de vie HUD | AppKit |
| `HUDView` | SwiftUI : pastille état, ondes audio, texte streaming, globe OpenRouter | SwiftUI |
| `ToastController` / `ToastView` | Aperçu 3s, auto-commit, édition sur interaction, undo via hotkey | AppKit + SwiftUI |
| `ListWindowController` / `ListView` | Fenêtre liste du jour, cases à cocher | AppKit + SwiftUI |
| `MenuBarController` | NSStatusItem, badge, accès liste + réglages | AppKit |
| `OnboardingController` | Première exécution : permission micro (TCC), login item (SMAppService), réglage du raccourci, saisie clé OpenRouter | AppKit + SwiftUI |
| `Settings` | Raccourci, modèle Whisper, clé OpenRouter + ID modèle, préférences | UserDefaults / Keychain (clé API) |

## 9. Permissions & cycle de vie

- **Micro (TCC)** : demandé à l'**onboarding**, jamais dans le chemin de capture (la popup système vole le focus et bloquerait la première capture).
- **Login item** : `SMAppService.mainApp` (Sequoia), proposé à l'onboarding.
- **App Nap** : `ProcessInfo.beginActivity` pendant la capture pour éviter la suspension de l'AVAudioEngine.
- **Clé API OpenRouter** : stockée en Keychain, jamais en clair. L'utilisateur la fournit ; ID modèle exact vérifié via l'API OpenRouter avant intégration (règle CLAUDE.md).

## 10. Risques & angles morts traités

- Latence Whisper → streaming + modèle `base` + pré-chargement + benchmark Air.
- Hallucinations FR sur court/silence → durée min, blacklist, score de confiance.
- Multi-écran → HUD sur l'écran contenant le curseur (pas `NSScreen.main`).
- Micro déjà utilisé (Zoom/FaceTime) / changement de device à chaud → gérer `AVAudioEngineConfigurationChange` sans crash.
- Accessibilité → état toujours doublé en texte (pas seulement couleur/visuel).
- Réseau OpenRouter → fallback texte brut + re-parse différé.
- Confidentialité → la transcription part vers OpenRouter (cloud tiers) ; documenté pour l'utilisateur, option locale gardée en backlog.
- Migrations SwiftData → `VersionedSchema` dès v1.

## 11. Hors scope v1 (backlog)

v2 : récurrence vocale ("tous les lundis"), notifications / récap matinal (digest unique), projets + recherche floue, sync Apple Reminders (EventKit), extension Raycast, parsing local optionnel (privacy).
v3 : companion Apple Watch (capture la plus rapide), smart scheduling vers Calendar, dictée bilingue FR/EN, résumé hebdo comportemental, streaks (à doser, non culpabilisant).

## 12. Critères de succès v1

- De la pensée à la tâche enregistrée en un seul geste, sans quitter l'app active.
- Feedback visuel qui prouve que la voix est captée (ondes) et que l'app est prête (pastille).
- Aucune tâche perdue silencieusement (échecs toujours visibles, fallback systématique).
- Rollover quotidien correct en heure d'été et d'hiver.
- Latence ressentie acceptable sur le MacBook Air réel (à mesurer).
