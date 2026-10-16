# Déploiement · Installation OTA AssistToDo iPhone

Méthode tant que le MacBook Air reste en Xcode 16.4 (pas d'image développeur pour l'iPhone 18 Pro) : build Release signé Apple Development (profil incluant l'UDID 00008160-001615D60EE00036), .ipa + manifest.plist + page `itms-services` publiés temporairement sur lessitesdeflo.fr (skill lessitesdeflo, mode demo, dossier opaque), installation depuis Safari sur l'iPhone, dossier supprimé par FTP ensuite.

## En cours

- **URL** : https://lessitesdeflo.fr/demo/d-ffcd38/
- **Déployé le** : 2026-10-16 · **Mode** : demo (noindex, dossier opaque)
- **Version** : 1.2.2 (4) : Travail synchronisé via Toudou (fusion Mac v1.2.2) + état de synchro visible
- **Vérifié** : page 200, manifest 200 application/xml, ipa 200 application/octet-stream, SHA-256 identique au local (3a31fc94…), noindex, listing parent 403, /.env et /.htpasswd 403
- **À faire** : supprimer www/demo/d-ffcd38/ dès que Florian confirme l'installation

## Historique

- 2026-10-16 · demo/d-5da30b · 1.2.1 (2 puis 3) · supprimé après installation (404 vérifié)
- 2026-09-27 · demo/d-f58c04 · 1.0 (1) · supprimé après installation (404 vérifié)
