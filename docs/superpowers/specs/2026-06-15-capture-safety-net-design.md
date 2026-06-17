# Spec — Filet de sécurité de capture (« jamais perdre une idée »)

Date : 2026-06-15
Statut : design validé avec Florian. Prochaine étape = plan d'implémentation (skill writing-plans).
Portée : sous-projet A de l'évolution « vrai assistant ». Concerne Mac **et** iPhone (code partagé `AssistToDoKit`).

## 1. Objectif

Garantir qu'**aucune idée dictée n'est jamais perdue**, même si un étage du pipeline bugue (transcription faible, réseau LLM coupé, calendrier indisponible, crash). L'**audio est la source de vérité** : il est sauvegardé durablement avant tout traitement, et toute capture est **rejouable** (re-transcription + re-classement) à tout moment.

### Incident fondateur (preuve du besoin)
Vocal du 2026-06-15 : « Mets-moi un rendez-vous pro demain avec Léa Mathis du Crédit Agricole pour une réservation studio… rendez-vous demain à 14h. » L'app a créé une **tâche locale sans date** (« Rendez-vous avec Leah Matisse… ») au lieu d'un **événement calendrier demain 14h (agenda pro)**. Cause : le modèle Whisper `small` a **lâché « demain à 14h »** ; le LLM a reçu un transcript amputé. L'audio, lui, contenait bien l'info (re-transcrit a posteriori avec un meilleur moteur → routage parfait). Avec ce filet, la capture se **re-traite en un tap** et l'événement est récupéré.

## 2. Périmètre

### Dans le périmètre
- Sauvegarde **durable** de chaque audio (hors dossier temp).
- **Journal de captures** persistant (SwiftData, dans `AssistToDoKit`).
- **Pipeline en machine à états** explicite, avec gestion d'échec par étape + retry.
- Comportement **hors-ligne** (transcription locale + tâche texte brut « à enrichir », ré-enrichie au retour réseau).
- Écran **« Captures »** (historique) + action **« Re-traiter »** (re-transcrire + re-router) et **« Re-router seulement »** (garder le transcript, relancer le LLM).
- **Rétention** configurable + suppression manuelle.

### Hors périmètre (sous-projets ultérieurs)
- Upload de l'audio sur un serveur (Option B) — l'audio reste **local par appareil**.
- Sorties riches : fiches projet / notes type Notion (sous-projet B).
- Agent superviseur qui reclasse (sous-projet C).

## 3. Architecture

### 3.1 Stockage de l'audio
- Écriture **immédiate** du fichier audio dans un dossier **persistant** :
  - Mac : `Application Support/<bundle>/Captures/`.
  - iPhone : `Documents/Captures/` (sauvegardé iCloud).
- Format inchangé (CAF mono float, normalisé true-peak — déjà corrigé).
- Plus jamais `temporaryDirectory` (qui se vide).

### 3.2 Journal de captures (nouveau modèle SwiftData, `AssistToDoKit`)
`CaptureRecord` :
- `id: UUID`
- `createdAt: Date`
- `audioFilename: String` (relatif au dossier Captures)
- `durationSec: Double`
- `status: CaptureStatus` (cf. §3.3)
- `transcript: String?`
- `transcriptModel: String?` (modèle Whisper utilisé)
- `parsedSummary: String?` (libellé/résumé produit par le LLM)
- `producedTaskIds: [UUID]` (tâches/items créés à partir de cette capture, pour traçabilité et re-traitement idempotent)
- `lastError: String?`
- `attempts: Int`
- `updatedAt: Date`

Lien capture ↔ tâches : une capture peut produire 1..n items (multi-tâches). Le re-traitement **remplace** les items précédents (supprime `producedTaskIds`, recrée) pour rester idempotent.

### 3.3 Pipeline = machine à états
`CaptureStatus` :
`recorded → transcribing → transcribed → routing → done`
ou états d'échec : `failed(stage, reason)` avec `stage ∈ {transcription, llm, routing}`.

Étapes :
1. **recorded** : audio écrit, `CaptureRecord` créé. (Point de non-perte : dès ici, l'idée est sauvée.)
2. **transcribing → transcribed** : Whisper local (hors-ligne OK). Échec → `failed(transcription)`, audio conservé.
3. **routing** : garde-fou local (filtre bruit) → LLM (OpenRouter) → résolution dates (DateResolver) → routage (`route()` existant : local/reminders/calendar/notes).
   - LLM injoignable (hors-ligne / erreur) → **fallback texte brut** : créer un item **local** « à enrichir » (statut capture `transcribed`, flag `needsEnrichment`), à ré-router plus tard.
   - Création Apple (EKEvent/EKReminder) échoue → `failed(routing)`, l'item reste **local** en repli, audio + transcript conservés pour re-traitement.
4. **done** : items créés et (si applicable) synced.

### 3.4 Re-enrichissement automatique
- Au lancement / au retour réseau / à chaque cycle de sync : repérer les captures `transcribed` avec `needsEnrichment` (LLM jamais passé) ou `failed(llm/routing)` et **les rejouer automatiquement** (best-effort, sans bloquer).
- Idempotent via `producedTaskIds`.

### 3.5 Re-traitement manuel (feature « Captures »)
- Écran **Captures** (par plateforme) : liste des `CaptureRecord` (récent en haut), avec statut, transcript, libellé produit, lecture de l'audio.
- Actions :
  - **Re-traiter** : relit l'audio → re-transcrit (avec le modèle Whisper courant) → re-route. Remplace les items précédents.
  - **Re-router seulement** : garde le transcript existant, relance LLM + routage (utile si le transcript est bon mais le routage a foiré).
  - **Écouter** l'audio. **Supprimer** la capture (et son audio).

### 3.6 Rétention
- L'audio est gardé **tant que la capture n'est pas `done`**, puis **30 jours** (valeur par défaut, réglable dans les Réglages : « Garder les audios N jours », option « indéfini »).
- Nettoyage auto au lancement : supprime les audios des captures `done` dont `createdAt` dépasse le délai. Le `CaptureRecord` (métadonnées + transcript) peut être gardé plus longtemps que l'audio.
- Suppression manuelle possible à tout moment.

## 4. Découpage en unités (pour le plan)

1. **Stockage durable** : dossier `Captures` persistant + migration de `AudioCapture.writeNormalizedFile` (cesser d'utiliser temp).
2. **Modèle `CaptureRecord`** + `CaptureStore` (SwiftData, `AssistToDoKit`) : CRUD + requêtes par statut. Tests in-memory.
3. **Pipeline machine à états** : refactor de `CaptureCoordinator` pour piloter via `CaptureRecord` (statuts, échecs, fallback texte brut, retry). Lien capture↔items via `producedTaskIds`.
4. **Re-enrichissement auto** : passe au lancement / retour réseau (best-effort).
5. **UI Captures + re-traitement** : écran historique (Mac et iPhone séparément), actions re-traiter / re-router / écouter / supprimer.
6. **Rétention** : réglage + nettoyage auto.

Chaque unité testable indépendamment. La logique (machine à états, idempotence du re-traitement, fallback) est dans `AssistToDoKit` → testée comme l'existant (12 tests Kit). Coordination iOS via `ASSISTTODO-HANDOFF.md` (Kit partagé).

## 5. Décisions figées
- **Local-first** : audio jamais uploadé sur serveur (Option A). Privé, hors-ligne robuste, simple.
- **Re-traitement = feature centrale** (manuel + auto).
- **Rétention** : 30 j par défaut, réglable (jusqu'à indéfini), suppression manuelle.
- Le cerveau par capture reste : Whisper local + LLM OpenRouter `gemini-2.5-flash`. Pas de nouvel agent ici (l'agent superviseur = sous-projet C).

## 6. Risques / notes
- Le modèle `small` charcute les fins de phrase (incident fondateur). Indépendant de ce filet, mais le filet en limite l'impact (re-traitement). Florian gère le choix de modèle (utilise le Large).
- Migration SwiftData : ajout de `CaptureRecord` = additif (migration légère).
- Disque : audios ~1 Mo/capture ; la rétention borne l'accumulation.
