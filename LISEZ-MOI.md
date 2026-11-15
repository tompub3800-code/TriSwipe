# TriSwipe

## Ce qu'il te faut
- Ton Mac avec **Xcode 16 ou plus récent** (gratuit sur l'App Store)
- Ton iPhone (iOS 17 minimum) et son câble
- Ton identifiant Apple (le compte gratuit suffit)

## Installation (une dizaine de minutes la première fois)
1. **Décompresse** le zip, puis double-clique sur `TriSwipe.xcodeproj`. Xcode s'ouvre.
2. **Connecte ton compte Apple** : menu Xcode > Settings > Accounts > « + » > Apple ID.
3. Dans la colonne de gauche, clique sur **TriSwipe** (l'icône bleue tout en haut), puis sur l'onglet **Signing & Capabilities**.
   Dans **Team**, choisis ton nom (Personal Team).
4. **Branche ton iPhone** et déverrouille-le. Accepte « Faire confiance à cet ordinateur ».
5. Sur l'iPhone, active le **Mode développeur** : Réglages > Confidentialité et sécurité > Mode développeur. L'iPhone redémarre.
6. En haut de Xcode, choisis ton iPhone dans la liste des appareils, puis clique sur **▶︎** (ou Cmd + R).
7. La première fois, l'iPhone bloque l'appli. Va dans Réglages > Général > VPN et gestion de l'appareil, touche ton adresse mail, puis **Faire confiance**.
8. Relance l'appli et autorise **l'accès à toutes les photos**.

> Avec un compte Apple gratuit, l'appli doit être réinstallée tous les **7 jours** : rebranche l'iPhone et refais ▶︎ dans Xcode (30 secondes). Tes progrès restent enregistrés. Le compte développeur payant (99 €/an) supprime cette limite.

## Si ça bloque
- **« Failed to register bundle identifier »** : dans Signing & Capabilities, change le *Bundle Identifier*, par exemple `com.tom.triswipe.hob2`.
- **Une erreur rouge à la compilation** : fais une capture d'écran du message et envoie-la-moi.

## Comment ça marche
| Geste | Action |
|---|---|
| Glisser à droite → | Garder |
| Glisser à gauche ← | Envoyer dans la corbeille de l'appli |
| Glisser vers le haut ↑ | Ranger dans un album (existant ou nouveau) |
| Glisser vers le bas ↓ | Décider plus tard |
| Toucher deux fois | Mettre en favori ❤️ |
| Pastilles d'albums | Ranger en un seul toucher dans tes derniers albums |
| ↺ | Annuler le dernier geste (sans limite) |

- **Rien n'est supprimé directement.** Ce que tu jettes arrive dans la corbeille de l'appli. Tu y vérifies les vignettes, tu récupères ce que tu veux, puis tu valides en une seule fois. Les photos restent encore 30 jours dans « Supprimés récemment » de l'app Photos.
- **Tri par mois** avec une barre de progression, ou **tri rapide** : tout, « Ce jour-là », captures d'écran, vidéos les plus longues (idéal pour libérer beaucoup de place vite).
- **Filtres** : photos, vidéos ou tout ; ordre récent, ancien ou au hasard.
- **Ta progression est enregistrée** : une photo déjà triée ne revient jamais.
- **Statistiques** : espace libéré, nombre de photos triées.
- Tout reste sur ton téléphone. Pas de pub, pas de limite, pas d'abonnement.
