## AssistToDo 1.1.21

### Corrigé · dates absolues avec un nom de jour
- **« le jeudi 6 août » tombait sur le mauvais jour.** Depuis la 1.1.19, quand une date exacte était précédée d'un nom de jour (« jeudi 6 août », « vendredi 25 »), l'app prenait le nom du jour comme une date relative et ignorait le numéro. Corrigé : une date avec un numéro reste absolue (le nom du jour n'est qu'une étiquette). « le jeudi 6 août » → 6 août.
- Les jours purement relatifs (« mardi prochain », « demain ») restent calculés de façon fiable.
