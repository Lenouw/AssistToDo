## AssistToDo 1.1.19

### Corrigé · le bon jour de la semaine
- **« mardi prochain » créait l'événement à mercredi.** Le modèle de langage calcule mal les jours de la semaine. Désormais l'app **calcule le jour elle-même** (fiable, en heure de Paris) à partir de l'expression dictée, et recale l'heure sur le bon jour. « mardi prochain », « jeudi », « demain », « après-demain »… tombent juste.
- Les dates absolues (« le 25 juillet ») restent gérées comme avant.
