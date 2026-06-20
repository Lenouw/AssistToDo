# Chantier "AssistToDo iPhone — premium" (2026-06-20)

Direction design validée : **C · Clarté chaude** (clair, fond crème, accent bleu profond #2E5FCB). [B Studio nuit testée puis abandonnée : trop sombre.]
Mode : design + features en parallèle.

## Design (Studio nuit)
- [x] Palette Studio nuit + Color(hex:) dans AssistToDoKit (Theme.swift), thème sombre verrouillé + tint app
- [x] Vraie waveform en barres audio-réactives (CaptureView) — moment signature
- [x] États capture soignés (écoute/transcription/résultat/ajouté) + dot recording
- [x] Bouton héros : accent, anneau de respiration, spring + haptique au touch
- [x] Listes : fond bg, .listStyle(.plain), cartes surface, couleurs par zone
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


## Design direction C — TERMINÉ (commits 049dc04 → 885bff9)
- [x] Palette claire crème + bleu profond, thème clair verrouillé
- [x] En-tête "Aujourd'hui" + date (plus le nom de l'app)
- [x] Hiérarchie de priorité visible (tri + drapeau + semibold + fond teinté haute, basse grisée)
- [x] Lignes scannables (colonne d'alignement constante, méta ciblée)
- [x] Empty state invitant
- [x] Agenda en mini-blocs horaires
- [x] Rappels scannables + "En retard" rouge
- [x] Captures en cartes + onde + pastille de statut
- [x] Réglages + sheet Fait accordés au crème
- [x] Capture : transcript title3 lisible
