# VoieGo

VoieGo est une application Flutter iOS/Android qui présente les prochains passages à proximité pour les bus, métros, RER et Transiliens d’Île-de-France. L’interface reprend la direction visuelle 3 choisie : bleu nuit, accents cyan, temps d’attente immédiatement lisible et parcours en deux choix.

## Ce qui fonctionne

- choix du réseau puis de la ligne ;
- localisation avec permission explicite ;
- recherche de l’arrêt de la ligne le plus proche ;
- prochains départs issus de PRIM/Navitia en mode temps réel ;
- information trafic de la ligne ;
- changement de direction, suivi local, rafraîchissement automatique et manuel ;
- mode démonstration automatique lorsqu’aucune URL de backend n’est configurée ;
- projets natifs iOS, Android et Web ;
- workflow GitHub qui produit une IPA iOS non signée.

## Architecture sûre pour PRIM

La clé PRIM ne doit jamais être placée dans l’application. Le dossier `backend/` contient un proxy Cloudflare Worker qui :

1. charge le catalogue des lignes depuis l’API PRIM/Navitia ;
2. cherche l’arrêt de la ligne le plus proche des coordonnées reçues ;
3. récupère les départs temps réel et l’information trafic ;
4. normalise les réponses et les met en cache pour limiter le quota PRIM.

Les horaires affichés sont des estimations temps réel. PRIM ne fournit pas dans ce catalogue une position GPS brute et continue du véhicule : l’application parle donc volontairement de prochain passage, et non de géolocalisation exacte du train.

## Lancer l’application

Sans backend, l’app démarre immédiatement avec des données de démonstration :

```sh
flutter pub get
flutter run
```

Avec le proxy déployé :

```sh
flutter run --dart-define=VOIEGO_API_BASE_URL=https://api.votre-domaine.fr
```

## Déployer le proxy PRIM

```sh
cd backend
npm install
npx wrangler secret put PRIM_API_KEY
npm run deploy
```

Remplacez `ALLOWED_ORIGIN = "*"` dans `backend/wrangler.toml` par votre origine Web avant une mise en production. Les applications natives ne dépendent pas de CORS, mais la restriction protège l’éventuelle version Web.

## Générer l’IPA non signée sur GitHub

1. poussez ce dossier à la racine d’un dépôt GitHub ;
2. dans **Settings → Secrets and variables → Actions → Variables**, créez `VOIEGO_API_BASE_URL` avec l’URL HTTPS du proxy ;
3. ouvrez **Actions → IPA iOS non signé → Run workflow** ;
4. téléchargez l’artefact `VoieGo-unsigned-…` à la fin du job.

Le workflow utilise `flutter build ios --release --no-codesign`, place `Runner.app` dans `Payload/`, puis crée `VoieGo-unsigned.ipa`. Cette IPA n’est pas installable telle quelle sur un iPhone : elle doit être signée avec un certificat et un profil Apple valides. Pour l’App Store, utilisez ensuite une archive signée depuis Xcode ou votre chaîne CI de distribution.

## Données et conformité

- Source : Île-de-France Mobilités / PRIM.
- Ne commitez jamais `PRIM_API_KEY`.
- Ajoutez avant publication : politique de confidentialité, page support, consentement analytique si nécessaire et textes App Store sur la localisation.
- Vérifiez les identifiants de bundle, l’équipe Apple, les captures App Store et la fiche de confidentialité avant soumission.
