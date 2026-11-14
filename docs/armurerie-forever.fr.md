# Armurerie Forever : portraits, équipement et talents

Étude du 14 novembre 2026 pour Grudge Ledger.

## Ce que Blizzard publie

La [fiche officielle de Ganjha Meuuh](https://worldofwarcraft.blizzard.com/en-us/forever/eu/armory/character/ganjha-meuuh) a répondu à une lecture publique. Son état de profil contenait un avatar, 16 entrées dans le champ d’équipement, des arbres avec des talents et une date de mise à jour. Il s’agit d’une observation du site, pas d’un contrat sur son format ni d’un historique des combats. [L’Armurerie officielle](https://worldofwarcraft.blizzard.com/en-us/forever/eu/armory) indique un niveau minimal de 10. L’absence d’un profil ou d’un objet ne prouve pas que le personnage ne porte rien.

## Ce que peut faire le journal seul

Le client [dessine le portrait à partir d’une unité](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/UnitDocumentation.lua). Le GUID sert à vérifier l’identité ; il ne contient pas le visage. La 0.10.5 retient les textures vues pendant la session même si le journal est fermé. La mémoire est bornée : après éviction ou rechargement, il faut revoir le personnage ou disposer d’un avatar déjà importé. Nous n’avons identifié aucune API Lua Forever fournissant une requête HTTP générale vers l’Armurerie ni un export du portrait natif sous forme d’image persistante.

## Faisabilité d’un onglet Équipement et talents

- **Observation en jeu :** tester sur deux clients de factions opposées si le jeu autorise l’inspection dans le contexte précis de la rencontre. [Les événements d’inspection du client](https://github.com/Gethe/wow-ui-source/blob/forever/Interface/AddOns/Blizzard_APIDocumentationGenerated/PaperDollInfoDocumentation.lua) ne garantissent pas que les informations d’un adversaire sont accessibles après sa mort, hors de portée ou en combat. Ne conserver que les champs réellement obtenus pour le GUID attendu, avec l’heure d’observation. Les talents ennemis en combat restent à valider.
- **Fiche web :** un outil externe peut récupérer avatar, équipement et talents, vérifier l’identité et préparer des données locales pour le prochain chargement de l’addon. L’importeur de portraits existant couvre déjà la validation des avatars, mais il est facultatif et n’est pas lancé par le jeu. Pour automatiser ce mode, il faudrait distribuer un compagnon séparé, gérer les profils absents et les erreurs de réseau, et afficher la date de mise à jour Blizzard.
- **Présentation recommandée :** distinguer « Observé en jeu à … » et « Dernière fiche Armurerie du … ». Une nouvelle consultation ne doit jamais réécrire le souvenir d’un combat. Prévoir aussi une fiche indisponible, une inspection partielle et un changement d’équipement après le combat dans la validation.

Conclusion : un onglet autonome peut présenter ce que le jeu a permis d’observer. Un onglet alimenté automatiquement par le site pour n’importe quel ennemi exige un composant extérieur au jeu ; même alors, la fiche web ne prouve pas l’équipement porté à l’instant du combat.
