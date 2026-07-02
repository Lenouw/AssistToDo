# Chantier « Répare + améliore » (2026-06-26)

Constat Florian : « l'app fonctionne pas donc je m'en sers pas ». Post-merge v1.1.10,
l'API Kit (rappels ouverts / archive 24h / nag) n'est PAS branchée dans l'UI iOS.

## Réparations (branchements manquants) — confirmées
- [ ] ListsView : zone Rappels re-faite sur le NOUVEAU modèle (openReminders =
      aujourd'hui + en retard + sans date ; futurs exclus). Retirer le bucket
      « à venir » mort. En retard = rouge + en premier. Cocher / → demain.
- [ ] Rappels ouverts ÉPINGLÉS en haut de « À faire » (le cerveau), pulse si en retard.
- [ ] Écran Archive (tâches faites > 24h) : consulter, restaurer (re-décocher),
      supprimer, bouton « Archiver les tâches faites maintenant ». Sinon les tâches
      cochées DISPARAISSENT après 24h sans trace = impression de perte de données.
- [ ] Nag 2×/jour : appeler notifications.rescheduleReminderNags() après chaque
      refresh des rappels + au foreground.
- [ ] Réglages « Relance des rappels » (activé + heures matin/aprem,
      clés inappReminderNagEnabled / MorningMin / AfternoonMin).
- [ ] AppModel.onForeground : refreshToday() systématique (remplit openReminders),
      puis rescheduleReminderNags().
- [ ] Utiliser store.openReminders (source unique) au lieu du @State local ListsView.
- [ ] Nettoyer code mort (todayReminders inutilisé côté iOS ? store.todayEvents ?).

## Améliorations UX (selon audit UX en cours)
- [ ] Clé OpenRouter absente → bandeau visible « routage désactivé » au lieu d'un
      fallback silencieux vers À faire.
- [ ] (autres selon rapport agents)

## Gates
- Kit 21 + Core 40 verts, build device vert à chaque étape.
