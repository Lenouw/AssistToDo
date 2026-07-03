## AssistToDo 1.1.17

### Nouveau moteur de transcription · chargement instantané
- Passage de WhisperKit (CoreML/Neural Engine) à **whisper.cpp** (ggml + Metal), le même moteur que l'app Handy.
- **Fini le temps de chauffe.** Le modèle se charge par mmap en ~1 à 2 secondes, sans aucune compilation. Avant, Large v3 Turbo compilait 2-3 min au premier lancement.
- Modèle **Large v3 Turbo (q8_0, 874 Mo)** par défaut, précis, téléchargé une seule fois depuis notre serveur puis chargé hors-ligne.
- Transcription rapide sur GPU Metal (test réel : 8 s d'audio transcrits en ~3 s).

### Note
- Au premier lancement de cette version, si le modèle n'est pas déjà là, il se télécharge une fois (barre de progression dans Réglages › Transcription).
