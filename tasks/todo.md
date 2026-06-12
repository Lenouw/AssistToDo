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
