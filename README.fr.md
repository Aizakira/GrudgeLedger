# Grudge Ledger — Le journal des rancunes

<img src="docs/red-book.png" alt="Le livre rouge de Grudge Ledger" width="96" align="right">

**Se souvenir des bonnes rencontres… et garder une petite trace des autres.**

Un petit addon pour **World of Warcraft Forever**, qui rassemble amis, ennemis, notes personnelles, avis sur les guildes et souvenirs de PvP.

[English](README.md) · [Télécharger](https://github.com/Aizakira/GrudgeLedger/releases/latest) · [Signaler un problème ou proposer une idée](https://github.com/Aizakira/GrudgeLedger/issues)

## Pourquoi cet addon ?

Il a été créé assez vite pour répondre à un besoin tout simple en jouant : reconnaître les personnes avec qui on a passé un bon moment, celles qui nous ont agressés, et se rappeler pourquoi un nom nous dit quelque chose.

Il a été **réalisé avec l'aide de ChatGPT, via Codex**, puis corrigé et vérifié au fil des essais et des tests automatisés. Les illustrations du livre rouge ont également été générées avec les outils d'image d'OpenAI.

C'est un petit projet personnel, partagé tel quel. Il pourra évoluer avec les retours, les envies et les contributions, sans calendrier promis. Prenez-le, testez-le, modifiez-le, faites votre propre version : il est là pour être utile et partagé, dans le cadre de sa licence GPLv3.

## Ce qu'il propose

- **Un menu au clic droit** sur les portraits et noms du chat pris en charge : Ami, Méfiance, Ennemi, avis positif ou négatif, note et fiche personnelle.
- **Des repères visuels** sur les barres de noms visibles : bouclier vert pour les amis, avertissement orange pour la méfiance, crâne rouge pour les ennemis. La coloration supplémentaire des noms est facultative.
- **Un historique PvP** des agressions et des morts observées, avec distinction entre faits confirmés et déductions probables. Une attribution erronée peut être corrigée.
- **La camaraderie par les emotes** que vous envoyez à un joueur ciblé, y compris de l'autre faction. Les répétitions sont limitées pour éviter de gonfler les scores.
- **Des avis sur des guildes entières**, avec des exceptions individuelles.
- **Des alertes de rencontre** avec un petit son, des délais entre répétitions et un regroupement pour les membres d'une même guilde.
- **Un journal personnel** pour les notes, rencontres, groupes partagés et événements PvP, accessible par le livre de la minimap ou `/gl`.

## Installation et premiers pas

1. Télécharger **`GrudgeLedger-0.2.1.zip`** dans les [versions publiées](https://github.com/Aizakira/GrudgeLedger/releases/latest).
2. Extraire le dossier `GrudgeLedger` dans `Interface/AddOns` du client Forever. Le fichier doit se trouver ici : `Interface/AddOns/GrudgeLedger/GrudgeLedger.toc`.
3. Redémarrer WoW et activer Grudge Ledger dans la liste des addons.

Aucune dépendance n'est nécessaire. Désactivez Grudgebook et Worth Remembering si vous les utilisez pour le même rôle, afin d'éviter les doublons de menus, marqueurs et alertes. Les archives automatiques **Source code** de GitHub contiennent aussi les fichiers de développement : seul leur dossier intérieur `GrudgeLedger` va dans `AddOns`.

Un clic gauche sur le livre ouvre le journal, un clic droit ouvre les réglages. Vous pouvez le faire glisser autour de la minimap. Pour ajouter quelqu'un, faites un clic droit sur son portrait ou son nom dans le chat, puis survolez **Grudge Ledger**. Pas besoin de recherche ni de commande. L'interface en jeu est actuellement principalement en français.

Quelques commandes facultatives, également utilisables dans une macro :

```text
/gl
/gl ami
/gl mefiance
/gl ennemi
/gl + Merci pour le donjon !
/gl - Mauvaise rencontre
/gl note
/gl guilde mefiance
/gl settings
/gl debug
```

Les actions concernent le joueur ciblé. Le [guide complet](GrudgeLedger/README.txt) détaille les classements, les corrections et les sauvegardes.

## Compatibilité et limites

Prévu pour **Forever, interface 16001** ; développé avec le client **1.60.1.70862**. Les versions Retail, Classic et les autres serveurs ne sont pas validés. Les marqueurs nécessitent des barres de noms visibles et respectent les limites de portée du jeu. Ce n'est ni un radar couvrant toute la zone, ni un détecteur de furtivité.

Forever peut masquer le journal de combat. Les déductions PvP ne sont donc pas infaillibles : elles sont indiquées comme probables, les situations ambiguës sont ignorées et vous pouvez corriger l'historique. Vos classements explicites restent prioritaires. La détection des duels dépend elle aussi des signaux disponibles.

Dix scripts de tests automatisés, dont 45 scénarios de suivi PvP, accompagnent les sources. Ils simulent les API de WoW et ne remplacent pas les essais en jeu. C'est encore une jeune version : vos retours sont les bienvenus.

## Chacun son livre

Le journal est **vierge au départ** : aucun joueur, aucune guilde, aucune liste noire préremplie. Il est commun aux personnages d'un même compte et enregistré séparément par WoW dans `WTF/Account/<compte>/SavedVariables/GrudgeLedger.lua`.

Partager le dossier de l'addon ou son ZIP ne partage pas vos notes. Il n'y a ni échange automatique de listes entre joueurs ni télémétrie. Pour un signalement de bug, ne publiez pas votre dossier `WTF` ou vos SavedVariables. Le diagnostic facultatif `/gl debug` exclut les identités des joueurs, les noms des guildes, les notes et les erreurs brutes ; vous décidez de le copier et de le transmettre.

## Participer ou modifier

Les issues et pull requests en français ou en anglais sont bienvenues. Pour un bug, précisez les versions de l'addon et du client, les étapes, le résultat attendu et le résultat observé. Masquez les informations personnelles des captures. Pour le code, privilégiez les changements ciblés et lancez les tests existants.

Python 3.11 est nécessaire uniquement pour les tests de développement :

```sh
python -m pip install --target test-runtime -r requirements-test.txt
python tests/run_tests.py
```

Les mêmes tests sont exécutés sur Linux et Windows par GitHub Actions. Voir [DEVELOPMENT.txt](DEVELOPMENT.txt) pour le rendu d'interface facultatif hors jeu. Depuis la racine du dépôt, cette commande crée une archive installable :

```sh
python -m zipfile -c GrudgeLedger-0.2.1.zip GrudgeLedger
```

## Licence et crédits

Le projet est sous **GNU GPL v3** : vous pouvez l'utiliser, l'étudier, le modifier, le partager et même le redistribuer commercialement, dans les conditions de cette licence. Les versions modifiées redistribuées doivent conserver les mentions, fournir leurs sources correspondantes et rester sous GPLv3. Le logiciel est fourni sans garantie. Voir [LICENSE](LICENSE).

Certaines techniques d'intégration des menus, barres de noms et infobulles sont adaptées de [Worth Remembering, par Kyle (maliceftw)](https://github.com/kk-on-gh/WorthRemembering), déjà sous GPLv3. Le suivi PvP a été réimplémenté en s'inspirant de l'approche décrite par [Grudgebook](https://www.curseforge.com/wow/addons/grudgebook). Aucun de ces addons n'est inclus ni requis. Les [crédits détaillés](GrudgeLedger/CREDITS.txt) sont conservés.

Les contributions originales, la documentation et les illustrations générées incluses sont partagées sous les mêmes conditions GPLv3. Les textures et sons natifs de WoW sont référencés depuis le client, sans être redistribués. Projet non officiel, sans affiliation avec Blizzard Entertainment ou OpenAI.
