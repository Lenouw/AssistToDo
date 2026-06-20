# Chantier "AssistToDo iPhone — premium" (2026-06-20)

Direction design validée : **B · Studio nuit** (dark, gris chaud foncé, accent violet #6E56F7, mono liste dev).
Mode : design + features en parallèle.

## Design (Studio nuit)
- [x] Palette Studio nuit + Color(hex:) dans AssistToDoKit (Theme.swift), thème sombre verrouillé + tint app
- [x] Vraie waveform en barres audio-réactives (CaptureView) — moment signature
- [x] États capture soignés (écoute/transcription/résultat/ajouté) + dot recording
- [x] Bouton héros : accent, anneau de respiration, spring + haptique au touch
- [ ] Listes : fond bg, .listStyle(.plain), cartes surface, couleurs par zone
- [x] Checkbox bounce + strikethrough + haptique
- [x] Captures : cartes + dot d'état partagé + play accent
- [x] Live Activity / Dynamic Island : tint accent + mini-waveform + dot
- [x] Widget launcher : fond accent-soft
- [ ] Maquette haute-fi (image gen + Magnific) pour valider le rendu

## Features (quick wins)
- [x] Reformulation propre (DÉJÀ dans ParsePromptBuilder, commit Mac antérieur)
- [x] Feedback haptique aux 3 moments (début capture / ajout / coche)
- [ ] Aperçu + undo de routage (où part chaque item, annulation geste)
- [ ] Nudge quotidien du brain dump (notif locale à heure choisie)

## Plus tard (ambitieux)
- [x] Multi-items en une dictée (DÉJÀ dans le prompt : « Découpe les phrases multi-tâches »)
- [ ] Recherche universelle
- [ ] Tags/zones de vie sur les tâches + filtres
- [ ] Brief studio avant RDV client
