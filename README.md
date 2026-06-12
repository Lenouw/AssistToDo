# AssistToDo

Capture vocale éclair de tâches pour macOS. Tu maintiens un raccourci, tu parles, et ta pensée est transcrite **en local** (hors-ligne, WhisperKit) puis rangée automatiquement par LLM (OpenRouter) : liste interne (ton « second cerveau »), Rappels Apple, Calendrier Apple, ou liste de courses dans Notes. L'app ne vole jamais le focus de l'app active. Rollover quotidien, rappels locaux.

Cible : macOS 15 (Sequoia), Mac Apple Silicon.

## Installation

1. Télécharge le **`.dmg`** depuis la [dernière release](https://github.com/Lenouw/AssistToDo/releases/latest).
2. Ouvre le DMG, glisse **AssistToDo** dans **Applications**.
3. **Premier lancement** (app non signée par Apple) : dans Applications, **clic-droit sur AssistToDo › Ouvrir**, puis confirme **Ouvrir**. (Un double-clic affiche une alerte Gatekeeper : c'est normal, passe par le clic-droit une seule fois.)
4. Au premier lancement, l'app **télécharge le modèle de transcription** (~une fois, besoin réseau).

## Usage
- **Appui long** sur le raccourci (défaut `⌃⌥Espace`) : capture vocale.
- **Appui bref** : ouvre la liste (colonne à droite).
- Icône barre de menus : liste, Réglages.

## Configuration
Ouvre les **Réglages** (icône barre de menus) :
- **Raccourci** de capture.
- **Clé OpenRouter** (`sk-or-...`), la tienne, stockée dans le Trousseau. Modèle par défaut `google/gemini-2.5-flash`.
- **Permissions** : Micro, Notifications, Calendrier, Rappels.
- **Note de courses** : la note Apple qui reçoit tes articles dictés.
- **Catégories d'agenda** + **règles de classement** personnalisées.

## Mises à jour
L'app vérifie au lancement s'il existe une version plus récente sur GitHub et propose de la télécharger. Manuel possible dans **Réglages › À propos › Vérifier les mises à jour**.

## Vie privée
- **Transcription 100% locale** (WhisperKit) : aucune voix envoyée sur le réseau.
- Seul le **texte transcrit** part vers OpenRouter (avec ta clé) pour le rangement. Routage désactivable (tout reste local).
- Aucune donnée collectée par l'app.

## Désinstallation propre
L'app ne modifie aucun réglage système global. Pour tout retirer :
1. Quitter l'app, désactiver l'ouverture au démarrage (Réglages app ou Réglages Système › Général › Ouverture).
2. Supprimer l'app.
3. Données locales : `~/Library/Containers/Lenouw.AssistToDo/` (store SwiftData).
4. Clé API : Keychain, service `com.assisttodo.openrouter` (via Trousseau d'accès).

## Build / publier (dev)
Ouvrir `AssistToDo/AssistToDo.xcodeproj`, `⌘R`. Cœur métier testable :
```bash
cd AssistToDoCore && swift test
```
Fabriquer un DMG distribuable :
```bash
./scripts/release.sh        # → dist/AssistToDo-X.Y.Z.dmg
gh release create vX.Y.Z dist/AssistToDo-X.Y.Z.dmg --title "AssistToDo X.Y.Z" --notes-file RELEASE_NOTES.md
```
