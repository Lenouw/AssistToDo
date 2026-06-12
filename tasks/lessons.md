# Leçons — AssistToDo

Format : `[date] | ce qui a mal tourné | règle pour l'éviter`

- 2026-06-12 | Le LLM mettait les events sans date sur "aujourd'hui", et appliquait une date dictée pour un item à TOUS les items de la phrase. Côté Swift, `route()` faisait aussi `dueDate ?? Date()`. | Ne JAMAIS inventer de date. Prompt : date/heure d'un item ne se propage pas aux autres ; calendar exige une date réellement dictée, sinon reminders/local avec dueDate=null. Swift : filet de sécurité, jamais de `Date()` par défaut pour un event.
- 2026-06-12 | Apple Notes : impossible de créer de vraies cases à cocher (checklist) via AppleScript/`body` HTML. La seule voie (simulation clavier System Events) OBLIGE Notes au premier plan → vole le focus → rejeté par l'utilisateur ("préhistorique"). | Ne pas partir sur la frappe clavier pour écrire dans une autre app. Pour les courses : texte simple dans Apple Notes (un `<div>` par ligne, focus préservé). Cases cochables = seulement faisable dans une app qu'on contrôle. Présenter le triangle d'impossibilité (cases + Notes partagé + sans focus volé : choisir 2) AVANT de coder.
- 2026-06-12 | Note de courses des Réglages ignorée : le LLM renvoyait un `noteName` deviné qui écrasait la note configurée (→ écriture/création dans une mauvaise note). | Rendre le réglage utilisateur autoritaire ; ignorer le `noteName` du LLM pour les courses (sauf besoin explicite vérifié).
- 2026-06-12 | Articles de courses notés "Acheter X" au lieu du nom seul. | Prompt notes : `text` = nom de l'article seul, jamais de verbe.
