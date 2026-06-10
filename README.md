# AssistToDo

App macOS native de capture vocale éclair de tâches. Raccourci maintenu → tu parles → la tâche est transcrite (offline, WhisperKit), structurée par LLM (OpenRouter), ajoutée à ta liste. Appui bref = ouvre la liste. Rollover quotidien, rappels locaux.

## Usage
- **Appui long** sur le raccourci (défaut `⌃⌥Espace`) : capture vocale.
- **Appui bref** : ouvre la liste (colonne à droite).
- Icône barre de menus : liste, Réglages, debug.

## Build
Ouvrir `AssistToDo/AssistToDo.xcodeproj`, `⌘R`. Dépendances SwiftPM résolues automatiquement (WhisperKit, KeyboardShortcuts, package local `AssistToDoCore`).

Le cœur métier (dates, parsing, rollover) est dans `AssistToDoCore` (package SwiftPM testable) :
```
cd AssistToDoCore && swift test
```

## Désinstallation propre
L'app ne modifie aucun réglage système global ni process système. Pour tout retirer :
1. Quitter l'app (menu barre de menus → Quitter).
2. Désactiver l'ouverture au démarrage (Réglages Système → Général → Ouverture, retirer AssistToDo) ou via les Réglages de l'app.
3. Supprimer l'app.
4. Données locales (conteneur sandbox de l'app) : `~/Library/Containers/<bundle id AssistToDo>/` — contient le store SwiftData. Supprimer ce dossier purge les tâches.
5. Clé API : stockée en Keychain (service `com.assisttodo.openrouter`). Supprimable via Trousseau d'accès.

## Configuration
Clé OpenRouter saisie à l'onboarding ou dans les Réglages (stockée en Keychain). Modèle LLM par défaut : `google/gemini-2.5-flash`. Modèle de transcription par défaut : `base`.
