## AssistToDo 1.1.16

### Corrigé
- **Plus de fausse « échec (transcription) » pendant le chargement du modèle.** Le modèle Large v3 Turbo a un temps de chauffe long au premier lancement (compilation interne, ~2-3 min). Pendant ce temps, une capture était marquée en échec alors qu'il fallait juste attendre. Désormais la capture reste **« en attente »** et se traite toute seule dès que le modèle est prêt, sans rien perdre.

### Conseil
- Pour une capture **instantanée**, garde le modèle **Small** (hors-ligne, prêt en quelques secondes). Large v3 Turbo donne un peu plus de précision mais demande d'attendre sa chauffe après chaque lancement. Réglages › Transcription.
