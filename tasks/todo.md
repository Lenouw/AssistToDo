# 🚨 URGENT — Polling sync trop agressif, quota Neon (à faire EN PREMIER, demandé 2026-07-17)

Quota Neon (base Toudou) à **80 %, ~3 jours avant coupure**. Le polling toutes les **45 s** garde la base éveillée 24h/24 (Neon s'endort après ~5 min sans requête).

Fichier : `AssistToDoKit/Sources/AssistToDoKit/Sync/SyncCoordinator.swift` ligne ~46 (`withTimeInterval: 45`). ⚠️ **Kit PARTAGÉ Mac + iOS** → corrige les deux (iOS l'a au merge).

- [ ] Pull toutes les **15 min** au lieu de 45 s (96× moins de requêtes)
- [ ] **Pull immédiat** à l'activation de l'app / ouverture du panneau / sortie de veille Mac (`NSApplication.didBecomeActiveNotification`, `NSWorkspace.didWakeNotification`, `.task` du panneau)
- [ ] **Push immédiat** quand une tâche change localement (aujourd'hui `TaskStore.markSyncDirty` ne déclenche RIEN → brancher un callback vers `SyncCoordinator.syncNow()`, débouncé qq secondes)
- [ ] Vérifier après coup que la base peut dormir (pas de requête pendant > 5 min au repos)
- [ ] Handoff iOS : hook `scenePhase == .active` côté iPhone (spécifique iOS), le reste vient du Kit

---

# TODO — Migration moteur transcription : WhisperKit → whisper.cpp (2026-07-03)

**But** : chargement instantané (~1 s par mmap, zéro compilation ANE) comme l'app Handy. Modèle large-v3-turbo GGML **q8_0** (874 Mo), chargé 1 fois depuis NOTRE GitHub. Décidé par Florian (frustré du warm-up WhisperKit : 2 min 47 s à froid, 6,6 s à chaud).

**Faits vérifiés** : Handy = whisper.cpp/ggml + Metal (pas de CoreML). whisper.cpp officiel (`ggml-org/whisper.cpp`) se consomme via **XCFramework** (`build-xcframework.sh` → `.binaryTarget`), Metal par défaut Apple Silicon + iOS. SwiftWhisper = abandonné + pas de Metal → écarté. Modèle q8_0 = 874 Mo (mmap ~1 s). L'app enregistre en 48 kHz → il faut **rééchantillonner à 16 kHz mono** (WhisperKit le faisait implicitement).

**Ne release QUE quand ça marche end-to-end. L'app reste en v1.1.16 (WhisperKit) entre-temps.**

## Étapes
- [x] cmake installé + whisper.cpp cloné (scratchpad)
- [ ] Builder `whisper.xcframework` (Metal, macOS+iOS) via build-xcframework.sh
- [ ] Récupérer + héberger `ggml-large-v3-turbo-q8_0.bin` sur release GitHub `models-turbo-ggml-v1` (SHA256)
- [ ] Kit `Package.swift` : retirer WhisperKit, ajouter le binaryTarget whisper.xcframework
- [ ] Wrapper Swift bas niveau (inspiré `examples/whisper.swiftui/whisper.cpp.swift`) : init(.bin), transcribe([Float]) → texte + avgLogProb
- [ ] Réécrire l'INTÉRIEUR de `Transcriber.swift`, MÊME API publique (isReady/transcribe(path:)/switchModel/downloading/downloadProgress/loadedModel). Chargement mmap → isReady quasi immédiat, plus de warmup bloquant
- [ ] Rééchantillonnage 16 kHz mono (AVAudioConverter) du .caf → [Float]
- [ ] `avgLogProb` pour HallucinationFilter (logprobs par token whisper.cpp)
- [ ] Réécrire `ModelProvisioner` : DL du .bin unique depuis notre GitHub (SHA256, pas de dézip)
- [ ] `AppDelegate` + `SettingsView` (Mac) : nouveaux ids modèles GGML
- [ ] Build Mac + test capture end-to-end + mesurer le temps de chargement (~1 s attendu)
- [ ] Bump version, commit, release
- [ ] Handoff iOS : adopter le même moteur (xcframework OK iOS ; tester Metal sur device)

---

# TODO — Affinage détection voix + écriture des tâches (session test 2026-06-13)

Phase de TEST en cours (Florian dicte des captures réelles, on relève les patterns). Fixes à appliquer ensuite.

État (2026-06-13) : ✅ Bug A corrigé (commit 94ad4ef) · ✅ Feature modèles Whisper supérieurs (picker) · ✅ Bug D prewarm · Bug B skip (non prioritaire). Rebuild Xcode pour tester en réel.

## Bug A — deadline arrachée du texte (✅ FIXÉ)
Cas réel : dicté « fais-moi penser à annuler mon abonnement TeuxDeux avant le 9 juillet » → écrit « Annuler abonnement application T2 » (le « avant le 9 juillet » a disparu).
- Attendu : tâche **locale**, deadline gardée **littéralement dans le texte** (« ...avant le 9 juillet »), **aucun** event calendrier ni rappel timé.
- Cause : `ParsePromptBuilder.systemPrompt` extrait toute date en `dueDate`/`remindAt` + « Nettoie le texte » → la mention de date est retirée du `text`. Et un « quand » explicite pousse vers `reminders`.
- Fix : nouvelle règle prompt → quand l'intention est « fais-moi penser à X avant/pour [date] » SANS demande de rappel à une heure précise, rester `local` ET **conserver la mention de date dans le texte** (ne pas l'extraire). Le « avant le 9 juillet » fait partie du libellé que Florian doit lire.
- Fichier : [ParsePromptBuilder.swift](AssistToDoCore/Sources/AssistToDoCore/Parsing/ParsePromptBuilder.swift). Penser à ajouter un test dans `ParsePromptBuilderTests`.

## Bug C — compréhension faible (mots rares écrasés par mots fréquents)
Cas réel : « récupérer un colis Amazon » → transcrit « récupérer le courrier » (Whisper `base` biaise vers les n-grams fréquents).
- Pas un bug de prompt : transcription. Le LLM ne peut pas corriger (temp déjà 0, « colis » même présent dans le prompt).
- Lever principal : **monter le modèle Whisper** (`base` → `small` ou `large-v3-turbo`). Le picker Réglages ne propose que tiny/base/small ([SettingsView.swift](AssistToDo/AssistToDo/UI/SettingsView.swift) ligne 47). Ajouter les modèles supérieurs + tester la latence sur le Mac de Florian.

## Feature — débloquer les modèles Whisper supérieurs (demandé Florian)
Florian veut pouvoir essayer les modèles plus lourds, lenteur accrue acceptée.
- Picker actuel = tiny/base/small seulement ([SettingsView.swift](AssistToDo/AssistToDo/UI/SettingsView.swift) ligne 47).
- Ajouter : `large-v3-turbo` (et/ou `large-v3`, `distil-large-v3`). Vérifier les noms exacts supportés par WhisperKit avant de coder (ne pas inventer le slug). Garder un libellé clair (« small = rapide » … « large = précis mais lent »).
- Changement pris en compte au redémarrage (déjà le cas, modèle pré-chargé au launch).

## Bug D — 1ʳᵉ capture lente (démarrage à froid)
Symptôme : la 1ʳᵉ demande après lancement met longtemps, les suivantes sont rapides. Diagnostic = warmup à froid.
- Cause principale = **WhisperKit** : [Transcriber.swift](AssistToDo/AssistToDo/Capture/Transcriber.swift) charge le modèle au launch mais ne fait AUCUNE inférence à vide → la 1ʳᵉ transcription paie compilation CoreML/MLX + chauffe Neural Engine.
- Fix : **prewarm** au lancement. Option `prewarm` dans `WhisperKitConfig` si dispo, sinon passer un court buffer silencieux dans `whisper.transcribe(...)` juste après `load()`. Vérifier l'API WhisperKit exacte.
- Cause secondaire = réseau : 1ᵉʳ appel OpenRouter paie DNS + handshake TLS. Optionnel : prefetch/keep-alive léger au launch. Secondaire vs Whisper.

## Bug B — noms propres / marques mal transcrits (« TeuxDeux » → « T2 »)
NON PRIORITAIRE (décision Florian) : les noms propres bugueront toujours, acceptable. Pas de dico de correction pour l'instant.

---

# TODO — Refonte panneau "second cerveau"

Design validé (maquette) : flux de pensées vocales (75%) + zone "Aujourd'hui · iCloud" (25%).

## Décisions figées (user, 2026-06-12)
- Flux = journal PERMANENT (garde tout). Base future sync Toudou API.
- Flux montre SEULEMENT les pensées ancrées dans l'app : 📌 ma liste/idées (pin), 🔔 rappels (bell), 📝 notes (note).
- **Calendrier JAMAIS dans le flux** (les events vivent dans le Calendrier Apple).
- Ligne = petite icône colorée NUE (style zone du bas) + texte multi-lignes + heure discrète à droite.
- Zone du bas = Rappels + Calendrier du JOUR, live iCloud (lecture seule), inclut items non créés par l'app.
- Actions : garder les swipes actuels (gauche/droite) = supprimer / modifier / cocher.

## Étapes
- [ ] EventKitService : `TodayItem` + `fetchTodayEvents()` + `fetchTodayReminders()` (bornes jour Paris, lecture live).
- [ ] TaskStore : exposer `thoughts` (dest != calendar, createdAt desc, permanent) + `todayEvents`/`todayReminders` + `refreshToday()`. Retirer localTasks/reminderTasks/recentEvents/moveLocal.
- [ ] CaptureCoordinator.route() : persister un miroir pour les NOTES ; NE PLUS persister le calendrier.
- [ ] ListView : flux unifié (icône nue + texte + heure) + zone du bas ; swipes conservés.
- [ ] Build Xcode vert + test manuel.
