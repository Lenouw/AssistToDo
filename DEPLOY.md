# Déploiement · Installation OTA AssistToDo iPhone

Méthode tant que le MacBook Air reste en Xcode 16.4 (pas d'image développeur pour l'iPhone 18 Pro) : build Release signé Apple Development (profil incluant l'UDID 00008160-001615D60EE00036), .ipa + manifest.plist + page `itms-services` publiés temporairement sur lessitesdeflo.fr (skill lessitesdeflo, mode demo, dossier opaque), installation depuis Safari sur l'iPhone, dossier supprimé par FTP ensuite.

## En cours

- **URL** : https://lessitesdeflo.fr/demo/d-5da30b/
- **Déployé le** : 2026-10-16 · **Mode** : demo (noindex, dossier opaque, sans mot de passe : l'installeur iOS ne gère pas l'authentification)
- **Version** : 1.2.1 (2), commit feat/ios après 64a1b11
- **Build** : `xcodebuild -scheme AssistToDoiOS -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/dd-ios-rel -allowProvisioningUpdates build`, puis Payload/ zippé en .ipa
- **Secrets** : aucun (Release, DevSecrets sous #if DEBUG et vide)
- **Vérifié** : 200 page, manifest 200 application/xml, ipa 200 application/octet-stream SHA-256 identique au local (4f4816d8…), noindex, listing parent 403, /.env et /.htpasswd 403
- **À faire** : supprimer www/demo/d-5da30b/ dès que Florian confirme l'installation

## Historique

- 2026-09-27 · demo/d-f58c04 · 1.0 (1) · supprimé après installation (404 vérifié)
