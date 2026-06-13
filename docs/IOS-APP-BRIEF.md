# AssistToDo iPhone · brief de handoff (nouvelle conversation)

But de ce document : démarrer la **version iPhone** d'AssistToDo dans une conversation dédiée, en réutilisant un MAXIMUM de l'app macOS existante et en gardant les deux apps **connectées**. Lis tout avant de coder. Ne code rien tant que la recherche + le brainstorming + le plan ne sont pas faits et validés par Florian.

---

## 0. Décision d'architecture (déjà tranchée)

- **Même repo / même projet Xcode** que l'app macOS. On ajoute un **nouveau target iOS** (pas un nouveau dossier, pas un nouveau repo).
- Le cœur métier `AssistToDoCore` (package SwiftPM local) est **partagé tel quel** entre macOS et iOS.
- La couche app portable (sync Toudou, store, réseau, transcription) doit être **partagée** entre les deux targets — soit en l'ajoutant au target iOS (membership), soit (mieux) en l'extrayant dans le package `AssistToDoCore` ou un 2ᵉ package `AssistToDoKit`. À décider en début de plan (voir §6).
- **Connexion Mac ↔ iPhone = via Toudou** (source de vérité, contrat `/api/sync` déjà en place, slugs `braindump` + `code`). Aucune communication directe device-à-device. Les Rappels/Calendrier Apple se synchronisent nativement via iCloud.

---

## 1. Ce qu'est l'app (rappel produit)

Capture vocale éclair de tâches. Tu parles, c'est transcrit **en local** (WhisperKit, offline, FR), structuré par LLM (OpenRouter `google/gemini-2.5-flash`), et rangé :
- **Vidage de cerveau** (to-do « un jour », sans date) → liste locale, **synchronisée Toudou** (slug `braindump`).
- **To-do Claude Code** (idées dev / modifs clients, mot-clé « Claude Code : … ») → liste locale, **synchronisée Toudou** (slug `code`).
- **Rappels Apple** (datés), **Calendrier Apple** (events, catégories perso/commun/pro/studio), **Notes Apple** (liste de courses) → restent chez Apple.
- Garde-fou LOCAL avant l'appel LLM (bruit/hésitations filtrés). Rollover quotidien Europe/Paris.

Détails complets : `CONTEXT.md`, `tasks/lessons.md`, mémoire projet, et la spec macOS `docs/superpowers/specs/2026-06-10-assisttodo-design.md`.

---

## 2. Code RÉUTILISABLE tel quel (Foundation pur / multiplateforme)

Package `AssistToDoCore/Sources/AssistToDoCore/` — **aucune dépendance UI/AppKit**, marche sur iOS :
- `Models/` : `ParsedTask`, `TaskRecord`, `Destination`, `LocalList`, `Priority`, `CalendarCategory`.
- `Parsing/` : `ParsePromptBuilder` (prompt LLM, règles de routage validées), `ParseResponseDecoder`.
- `Logic/` : `HallucinationFilter` (garde-fou), `RolloverEngine` (idempotent, Paris).
- `Dates/` : `DateResolver`, `ParisCalendar`.
- 37 tests verts (`cd AssistToDoCore && swift test`). À NE PAS réécrire.

Couche app **portable moyennant peu de changements** (actuellement dans le target macOS `AssistToDo/AssistToDo/`) :
- `Sync/ToudouClient.swift` + `Sync/SyncCoordinator.swift` : sync Toudou (URLSession, Codable). **Portable**.
- `Persistence/TaskStore.swift` + `TaskEntity.swift` : SwiftData, @MainActor. **Portable** (SwiftData existe sur iOS).
- `Parsing/TaskParser.swift`, `Support/KeychainStore.swift` (Security framework, iOS OK), `Support/PreferencesService.swift`, `Capture/Transcriber.swift` (WhisperKit, iOS OK), réseau OpenRouter (`OpenRouterClient`).
- `Capture/HallucinationFilter` usage, `CaptureCoordinator` (logique de pipeline — à adapter, pas l'UI).

À extraire dans un module partagé compilé par les 2 targets (recommandé) plutôt que dupliquer.

---

## 3. Code macOS-ONLY (à NE PAS porter, à remplacer par un équivalent iOS)

- `UI/IslandController.swift`, `ListWindowController.swift`, `MenuBarController` : NSPanel, barre de menus, niveaux de fenêtre. **N'existe pas sur iOS.**
- `HotkeyManager` (raccourci global clavier) : **pas de raccourci global sur iOS.** Remplacer par : bouton push-to-talk plein écran, **Action Button** (iPhone 15 Pro+), **Control Center control** (iOS 18), **Shortcuts / App Intents**, **Siri**, **Lock Screen widget**.
- `Integrations/NotesService.swift` (AppleScript com.apple.Notes) : **AppleScript n'existe pas sur iOS.** La liste de courses → Notes devra passer par une autre voie (App Intent « Add to Note » via Shortcuts, ou abandonner Notes sur iOS et router les courses ailleurs). À trancher avec Florian.
- `AppDelegate` macOS (NSApplicationDelegate, `.accessory`, single-instance) : remplacer par un `App`/`UIApplicationDelegate` iOS.
- `UI/IslandView.swift` (l'îlot encoche dessiné à la main) : sur iPhone, la vraie **Dynamic Island** se fait via **ActivityKit / Live Activities** (iPhone 14 Pro+). Reconcevoir.

---

## 4. Spécificités iOS à concevoir (sujets de recherche AVANT de coder)

Fais les recherches web (docs Apple à jour, WWDC récentes) sur :
1. **Capture audio iOS** : `AVAudioEngine` / `AVAudioSession` (catégorie record, gestion interruptions, permission micro `NSMicrophoneUsageDescription`). Enregistrement court push-to-talk.
2. **WhisperKit sur iOS** : confirmer support iOS, taille mémoire des modèles sur iPhone (le Mac propose tiny→large-v3 ; sur iPhone viser `base`/`small`, large = lourd). Modèle téléchargé au 1er run.
3. **Déclencheurs de capture** : Action Button (iPhone 15 Pro+), **App Intents** + **Shortcuts** (« Hey Siri, note pour AssistToDo »), **Control Center control** (iOS 18), **Lock Screen / Home Screen widgets**, éventuellement **share extension** (texte sélectionné → tâche).
4. **Dynamic Island / Live Activity** : `ActivityKit` pour l'état de capture (écoute → traitement → ajouté) en Dynamic Island + Lock Screen. C'est l'équivalent iOS de l'îlot encoche macOS.
5. **EventKit sur iOS** : `EKReminder` / `EKEvent` (mêmes APIs que macOS, entitlements `com.apple.security.personal-information.reminders`/`.calendars` + usage strings Info.plist). Réutiliser la logique de `EventKitService` (createReminder/createEvent, fetchToday...).
6. **Background / notifications** : `UNUserNotificationCenter` (interactif, déjà fait côté Mac, portable). Sync Toudou en background : `BGAppRefreshTask` ou sync à l'ouverture/au foreground.
7. **Stockage** : SwiftData (même schéma `TaskEntity`). Décider si on partage via **iCloud (CloudKit + SwiftData)** EN PLUS de Toudou, ou si Toudou suffit pour la connexion Mac↔iPhone (recommandé : Toudou seul pour les listes syncables, éviter le double canal).
8. **Réglages iOS** : URL+token Toudou (Keychain), clé OpenRouter (Keychain), modèle Whisper, permissions. Réutiliser `KeychainStore`, `PreferencesService`.

---

## 5. Contraintes / pièges (déjà connus côté Mac)

- **Compte Apple Developer** : Florian est en **compte gratuit**. Pour faire tourner sur un **vrai iPhone** : provisioning perso gratuit (rebuild tous les 7 jours), ou compte payant (99 $/an) pour TestFlight/App Store. À clarifier — ça conditionne la distribution iOS.
- **Timezone Europe/Paris** partout (règle projet, voir `tasks/lessons.md`). `ParisCalendar` déjà géré dans Core.
- **Secrets** : token Toudou + clé OpenRouter en **Keychain**, jamais en clair. Ne JAMAIS inventer/committer un token. Repo public `github.com/Lenouw/AssistToDo` → vérifier qu'aucun secret ne part dans l'historique.
- **Signature ad-hoc instable** (Mac) → sur iOS, signature de dev gérée par Xcode, mais le Keychain iOS est par-app (pas le même piège).
- Sync Toudou : contrat possédé par Toudou (`/api/sync`, slugs `braindump`/`code`, Bearer, LWW, tombstones). **Ne pas réinventer le contrat.** Réutiliser `ToudouClient`/`SyncCoordinator`.

---

## 6. Process attendu pour la nouvelle conversation

1. **Recherche** (web) sur les sujets §4 — APIs iOS à jour, ne rien inventer (cf. règle CLAUDE.md sur les slugs/APIs).
2. **Brainstorming** produit avec Florian : quels déclencheurs de capture (Action Button ? Siri ? widget ?), Dynamic Island oui/non, sort de la liste de courses (Notes impossible sur iOS), iCloud en plus de Toudou ou non, modèle Whisper par défaut iPhone.
3. **Décision d'extraction** : déplacer la couche partagée (sync/store/réseau/transcription) dans `AssistToDoCore` (ou un nouveau package `AssistToDoKit`) pour que macOS ET iOS la compilent sans duplication. Adapter le target macOS en conséquence (ne pas casser l'app Mac existante — elle marche, tests + build verts).
4. **Plan d'implémentation** écrit (skill writing-plans) → validé par Florian avant code.
5. **Implémentation** target iOS, en réutilisant Core + couche partagée. Build iOS vert + test sur simulateur/device.
6. Vérifier la **connexion** : une to-do « vidage de cerveau » créée sur iPhone apparaît dans Toudou puis sur le Mac (et inverse). Idem liste code.

---

## 7. Décisions à trancher avec Florian (à poser en début de conversation)

- Déclencheur(s) de capture iOS prioritaire(s) : Action Button / Siri-Shortcuts / widget / bouton in-app ? (probablement plusieurs).
- Dynamic Island (Live Activity) pour l'état de capture : oui (iPhone 14 Pro+) ?
- Liste de courses sur iPhone : Notes impossible → router ailleurs (Rappels ? liste in-app ? Shortcut ?) ou désactiver sur iOS.
- iCloud (CloudKit) en plus de Toudou, ou Toudou seul pour la connexion ? (reco : Toudou seul pour les listes syncables.)
- Compte Apple Developer payant pour iOS (device/TestFlight) ?
- Version iOS minimale cible (iOS 17 pour SwiftData + ActivityKit récent ? iOS 18 pour Control Center controls ?).

---

## 8. Référence rapide repo

- Repo : `github.com/Lenouw/AssistToDo` (branche `main`, public).
- Projet Xcode : `AssistToDo/AssistToDo.xcodeproj` (target macOS `AssistToDo`).
- Package cœur : `AssistToDoCore/` (tests : `swift test`).
- Contexte/état : `CONTEXT.md`, `tasks/todo.md`, `tasks/lessons.md`.
- Spec sync Toudou (contrat) : `App - Toudou/docs/superpowers/specs/2026-06-12-toudou-sync-design.md` (§14 multi-listes).
