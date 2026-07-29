## AssistToDo 1.1.22

### Corrigé · fermeture du studio « toute la journée »
- **Le studio se fermait de 8h à 18h au lieu de ta plage réglée (8h-20h).** Quand tu dis « ferme le studio toute la journée », le modèle inventait une heure de début + une durée, ce qui court-circuitait ta plage configurée. Désormais, pour toute fermeture studio SANS heure d'horloge dictée, l'app applique ta plage des Réglages (Fermeture studio : de … à …), quoi que le modèle propose.
- Si tu dictes une vraie heure (« ferme le studio de 14h à 18h », « ferme la matinée et rouvre à 14h »), ça reste respecté à la lettre.
