# Leçons — AssistToDo

Format : `[date] | ce qui a mal tourné | règle pour l'éviter`

- 2026-06-12 | Le LLM mettait les events sans date sur "aujourd'hui", et appliquait une date dictée pour un item à TOUS les items de la phrase. Côté Swift, `route()` faisait aussi `dueDate ?? Date()`. | Ne JAMAIS inventer de date. Prompt : date/heure d'un item ne se propage pas aux autres ; calendar exige une date réellement dictée, sinon reminders/local avec dueDate=null. Swift : filet de sécurité, jamais de `Date()` par défaut pour un event.
- 2026-06-12 | Apple Notes : impossible de créer de vraies cases à cocher (checklist) via AppleScript/`body` HTML (limite connue du dictionnaire de script). | Pour une checklist cochable : soit la gérer dans l'app, soit passer par un Raccourci (Shortcuts), soit GUI-scripting (System Events, fragile + permission Accessibilité + vole le focus). Ne pas promettre des checkboxes Notes via AppleScript.
- 2026-06-12 | Articles de courses notés "Acheter X" au lieu du nom seul. | Prompt notes : `text` = nom de l'article seul, jamais de verbe.
