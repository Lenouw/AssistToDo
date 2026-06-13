# AssistToDo iPhone · spec de design (v1)

Date : 2026-06-13. Statut : validé par Florian (décisions §7 + design tranchés en brainstorming).
Source amont : `docs/IOS-APP-BRIEF.md`. Cette spec fige les décisions et l'architecture avant le plan d'implémentation.

---

## 1. Objectif

Porter AssistToDo sur iPhone en réutilisant un maximum de l'app macOS existante (qui marche : build + 37 tests verts), sans la casser, et en gardant Mac ↔ iPhone **connectés via Toudou**. Une to-do « vidage de cerveau » ou « Claude Code » créée sur iPhone doit apparaître sur le Mac, et inversement.

L'app : capture vocale éclair. On parle → transcription **locale** (WhisperKit, offline, FR) → structuration LLM (OpenRouter `google/gemini-2.5-flash`) → routage (vidage de cerveau, Claude Code, rappels Apple, calendrier Apple, courses). Garde-fou local anti-hallucination avant l'appel LLM. Rollover quotidien Europe/Paris.

---

## 2. Décisions figées (brainstorming 2026-06-13)

| # | Décision | Choix retenu |
|---|----------|--------------|
| Compte Apple Developer | gratuit / payant | **Payant 99 $/an** (TestFlight, ActivityKit en prod, bundle id réel) |
| iOS minimum | 16 / 17 / 18 | **iOS 18** (Control Center custom natif sans `#available`) |
| Liste de courses | Notes / Rappels / in-app / désactiver | **In-app**, `TaskEntity` + `LocalList.shopping`, cases cochables contrôlées par l'app |
| Canal de sync Mac↔iPhone | Toudou seul / + CloudKit | **Toudou seul** (Rappels/Calendrier se synchronisent à part nativement via iCloud) |
| Déclencheurs de capture | — | **Action Button + Siri/Shortcuts + Control Center + Widget** + bouton in-app (base). Tous partagent un seul App Intent |
| Dynamic Island / Live Activity | oui / plus tard / non | **Oui** (ActivityKit, états écoute→traitement→ajouté) |
| Extraction couche partagée | package / membership / dans Core | **Nouveau package SwiftPM local `AssistToDoKit`** |

---

## 3. Architecture de modules

Trois couches, deux targets app + une extension, zéro duplication de code métier.

```
AssistToDoCore/            (existant, Foundation pur, 37 tests) — inchangé sauf platforms += .iOS(.v18)
AssistToDoKit/             (NOUVEAU package SwiftPM local) — couche app portable
   └─ depends: AssistToDoCore + WhisperKit
   └─ Sync/            ToudouClient, SyncCoordinator
      Persistence/     TaskStore, TaskEntity
      Parsing/         TaskParser, OpenRouterClient
      Capture/         Transcriber, AudioCapture
      Integrations/    EventKitService
      Notifications/   NotificationManager
      Support/         KeychainStore, BuildInfo, PreferencesService (protocole + impl portable)
AssistToDo            (target macOS existant) — UI AppKit, link Core + Kit
AssistToDoiOS         (target NOUVEAU) — UI SwiftUI iOS, link Core + Kit
AssistToDoWidget      (target extension NOUVEAU) — Widget + Control + App Intent + Live Activity UI, link Core + Kit
```

**Coût d'extraction assumé** : les types/membres de `AssistToDoKit` consommés hors module passent de `internal` à `public`. Travail mécanique, fichier par fichier.

**Gate dur** : après extraction et rebranchement du target macOS sur `AssistToDoKit`, le build macOS et `swift test` (37 verts) doivent repasser **avant** d'écrire la moindre ligne d'iOS. Rouge → on répare avant d'avancer.

### Répartition des fichiers déplacés (macOS `AssistToDo/AssistToDo/` → `AssistToDoKit/`)

Portables, déplacés tels quels (puis `public`) :
`Sync/ToudouClient.swift`, `Sync/SyncCoordinator.swift`, `Persistence/TaskStore.swift`, `Persistence/TaskEntity.swift`, `Parsing/TaskParser.swift`, `Parsing/OpenRouterClient.swift`, `Capture/Transcriber.swift`, `Capture/AudioCapture.swift`, `Integrations/EventKitService.swift`, `Notifications/NotificationManager.swift`, `Support/KeychainStore.swift`, `Support/BuildInfo.swift`.

`Support/PreferencesService.swift` importe AppKit → scindé : protocole + logique portable dans Kit, dépendance AppKit (le cas échéant) reléguée côté target macOS, ou supprimée si triviale. À vérifier au déplacement.

Restent macOS-only (target macOS, NON déplacés) :
tous les `UI/*Controller`, `UI/*View` AppKit, `HotkeyManager` (KeyboardShortcuts), `Integrations/NotesService` (AppleScript), `AppDelegate`, `AssistToDoApp` (NSApplicationDelegateAdaptor), `UpdateChecker` (AppKit), `CaptureCoordinator` (AppKit HUD).

---

## 4. Target iOS — composants

### 4.1 App
- `AssistToDoiOSApp.swift` : `@main struct App`, SwiftUI. Un `ModelContainer` SwiftData partagé (App Group, pour partage avec l'extension widget). Sync Toudou déclenchée sur `scenePhase == .active` et après sauvegarde.
- Permissions demandées au bon moment : micro (`AVAudioApplication.requestRecordPermission()`), Rappels + Calendrier (EventKit) à la première intégration concernée.

### 4.2 Capture (push-to-talk)
Écran plein écran : maintenir pour parler, relâcher = stop.
1. `AVAudioSession` catégorie `.record`, `setActive(true)`, gérer `interruptionNotification` + `routeChangeNotification`.
2. `AVAudioRecorder` enregistre un clip court (`.wav`/`.caf`).
3. `Transcriber` (WhisperKit) transcrit le fichier → texte FR.
4. Garde-fou `HallucinationFilter` (Core) avant LLM.
5. `TaskParser` (OpenRouter `google/gemini-2.5-flash`) → `ParsedTask`.
6. Routage `Destination` → `TaskStore` (SwiftData) + EventKit (rappels/calendrier) + liste courses in-app.
7. Sync Toudou pour braindump/code.

Permission micro : `AVAudioApplication.requestRecordPermission()` (iOS 17+, l'app cible iOS 18 donc pas de fallback `AVAudioSession` nécessaire). Clé Info.plist `NSMicrophoneUsageDescription`.

### 4.3 App Intent partagé
Un seul `RecordVoiceIntent: AppIntent`, `static var openAppWhenRun = true`. Ouvre l'app sur l'écran de capture et démarre l'enregistrement. Brique unique réutilisée par les 4 déclencheurs. Vit dans `AssistToDoKit` (ou un module intents commun) pour être accessible à l'app ET à l'extension.

### 4.4 Déclencheurs (4 + base)
- **Bouton in-app** : écran de capture (base, toujours présent).
- **Action Button** : `AppShortcutsProvider` publie un App Shortcut ; l'utilisateur le mappe dans Réglages iOS > Bouton Action. Pas d'API dédiée (confirmé Apple).
- **Siri / Shortcuts** : `AppShortcut(intent: RecordVoiceIntent(), phrases: ["Note dans \(.applicationName)", ...])`. La phrase DOIT contenir `\(.applicationName)` (contrainte Apple vérifiée).
- **Control Center** (iOS 18) : `ControlWidgetButton` dans un Control Widget bundle, exécute l'intent. Pour ouvrir l'app : `OpenURLIntent` Universal Link ou intent `openAppWhenRun`.
- **Widget** accueil/verrouillé (iOS 17+) : `Button(intent: RecordVoiceIntent())`. Seuls `Button`/`Toggle` sont interactifs.

Widget + Control + Live Activity UI vivent dans le target extension `AssistToDoWidget`.

### 4.5 Live Activity / Dynamic Island
`ActivityKit`. `CaptureActivityAttributes` (statique) + `ContentState` (dynamique) à 3 états :
- **écoute** (micro actif),
- **traitement** (transcription + LLM),
- **ajouté** (résumé court de la tâche rangée).

Démarrage en foreground sur action utilisateur (`Activity.request`), `.update` **locaux** (pas de push APNs en v1), `.end` à la sauvegarde avec `dismissalPolicy`. Gate : `ActivityAuthorizationInfo().areActivitiesEnabled`. Présentations Dynamic Island (iPhone 14 Pro+) **et** écran verrouillé (autres devices) toutes deux codées. Info.plist `NSSupportsLiveActivities = YES`.

### 4.6 Liste de courses in-app
Réutilise `TaskEntity` avec `LocalList.shopping` (pas de nouvelle entité). Vue dédiée avec cases cochables contrôlées par l'app. Le routage LLM « courses » (côté Mac = `Destination.notes` → Apple Notes) est **remappé sur iOS** vers la liste courses locale (`local` + `LocalList.shopping`). Pas de sync Apple Notes (impossible iOS), pas de sync Toudou pour les courses en v1.

### 4.7 Réglages
URL + token Toudou (Keychain via `KeychainStore`), clé OpenRouter (Keychain), picker modèle Whisper, états de permission. Réutilise `KeychainStore` + `PreferencesService` (partie portable).

---

## 5. Sync Toudou (objectif clé)

Réutilise `ToudouClient` + `SyncCoordinator` tels quels (contrat possédé par Toudou : `/api/sync`, slugs `braindump` + `code`, Bearer, LWW, tombstones — **non réinventé**).

Déclenchement iOS :
- au foreground (`scenePhase == .active`),
- après chaque sauvegarde de tâche syncable,
- `BGAppRefreshTask` en bonus opportuniste (best-effort, jamais la source de fiabilité ; registration avant fin de lancement, sinon crash).

**Critère d'acceptation** : créer une to-do braindump sur iPhone → POST `/api/sync` → la tâche apparaît dans Toudou puis sur le Mac. Et inversement (Mac → Toudou → iPhone). Idem liste `code`.

---

## 6. Configuration iOS

### Info.plist
- `NSMicrophoneUsageDescription`
- usage strings Rappels + Calendrier (EventKit)
- `NSSupportsLiveActivities = YES`
- `BGTaskSchedulerPermittedIdentifiers` (reverse-DNS préfixé bundle id) + `UIBackgroundModes` (`fetch`/`processing`)

### Entitlements
- `com.apple.security.personal-information.reminders` **et** `.calendars` (leçon Mac 2026-06-12 : chacun exige le sien)
- App Groups (container SwiftData + Keychain partagés app ↔ extension widget)

### Capabilities
Live Activities, Background Modes, App Groups, Siri (App Intents).

### Distribution
Compte payant → bundle id réel, signature dev gérée par Xcode, TestFlight possible.

---

## 7. Modèle Whisper iPhone

- Défaut : **`small`** (≈ 480 Mo, FR correct ; `tiny`/`base` dégradent le FR).
- Option « haute précision » : **`large-v3-v20240930_626MB`** (large-v3 compressé).
- `large-v3` plein (~1,5 Go) écarté (trop lourd iPhone).
- Pas de `distil` : non confirmé dans le repo officiel `argmaxinc/whisperkit-coreml` → ne pas utiliser tant que non vérifié.
- Téléchargé au 1er run. `prewarm` testé sur device réel (issue WhisperKit #171 : `prewarmModels()` a échoué dans certains setups iOS).
- WhisperKit min iOS 16 (`Package.swift`), Apple Silicon/ANE requis → OK pour cible iOS 18. Pin une version/tag de WhisperKit (repo en migration vers `argmaxinc/argmax-oss-swift`).

---

## 8. Préservation de l'app macOS (gate dur)

Ordre imposé :
1. Créer `AssistToDoKit`, déplacer les 12 fichiers portables, passer en `public` ce qui est consommé hors module.
2. Rebrancher le target macOS sur `AssistToDoKit` (retirer les fichiers déplacés du target macOS, ajouter la dépendance package).
3. **Vérifier : `cd AssistToDoCore && swift test` (37 verts) + build macOS vert.** Rouge → réparer avant toute suite.
4. Seulement ensuite : créer le target iOS + l'extension.

---

## 9. APIs vérifiées (ne rien réinventer)

Toutes vérifiées contre les docs Apple / repos officiels (recherche 2026-06-13) :
- Permission micro : `AVAudioApplication.requestRecordPermission()` (iOS 17+ ; ancien `AVAudioSession.requestRecordPermission` déprécié).
- App Intents : `AppIntent.perform()` (iOS 16+), `AppShortcutsProvider` (phrase avec `\(.applicationName)` obligatoire), `openAppWhenRun`.
- Control Center : `ControlWidget`, `ControlWidgetButton` (iOS 18) ; ouverture app via `OpenURLIntent` Universal Link (pas de scheme custom).
- Widgets interactifs : `Button(intent:)` / `Toggle(isOn:intent:)` (iOS 17+).
- Live Activities : `ActivityKit`, `Activity.request/update/end`, `ActivityAttributes` + `ContentState` + `ActivityContent` (iOS 16.1 ; Dynamic Island device 14 Pro+). Vérifier la signature exacte `request`/`update` (`content:`) contre le SDK ciblé.
- Background : `BGTaskScheduler.register(...)` avant fin de lancement, `BGAppRefreshTaskRequest`, `BGTaskSchedulerPermittedIdentifiers`. Exécution opportuniste, non garantie.
- Notifications : `UNUserNotificationCenter` + `UNNotificationCategory`/`UNNotificationAction` (portable depuis macOS).
- WhisperKit : `import WhisperKit`, `WhisperKitConfig(prewarm:load:download:model:)`, min iOS 16.

---

## 10. Hors périmètre v1 (« plus tard »)

- Share extension (texte sélectionné → tâche).
- CloudKit / SwiftData iCloud (Toudou seul retenu).
- Sync Toudou de la liste de courses.
- Push APNs pour Live Activity (updates locaux suffisent au flux court).
- Modèles Whisper `distil`.

---

## 11. Critères d'acceptation v1

1. Build iOS vert sur simulateur + device réel (compte payant).
2. Build macOS + 37 tests Core **toujours verts** après extraction.
3. Capture vocale iPhone fonctionnelle : parler → transcrit FR → tâche rangée correctement.
4. Les 4 déclencheurs ouvrent l'app en capture (Action Button mappé, Siri phrase, Control Center, widget).
5. Live Activity affiche écoute → traitement → ajouté (Dynamic Island si device compatible, sinon écran verrouillé).
6. Liste de courses in-app avec cases cochables.
7. **Connexion** : braindump créée iPhone → visible Mac (et inverse) ; idem `code`.
