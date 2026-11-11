# Grudge Ledger — Le journal des rancunes

<img src="docs/red-book.png" alt="Le livre rouge de Grudge Ledger" width="96" align="right">

**Se souvenir des bonnes rencontres… et garder une petite trace des autres.**

Un petit addon pour **World of Warcraft Forever**, qui rassemble amis, ennemis, notes personnelles, avis sur les guildes et souvenirs de PvP.

[English](README.md) · [Télécharger](https://github.com/Aizakira/GrudgeLedger/releases/latest) · [Signaler un problème ou proposer une idée](https://github.com/Aizakira/GrudgeLedger/issues)

## Pourquoi cet addon ?

Il a été créé assez vite pour répondre à un besoin tout simple en jouant : reconnaître les personnes avec qui on a passé un bon moment, celles qui nous ont agressés, et se rappeler pourquoi un nom nous dit quelque chose.

Il a été **réalisé avec l'aide de ChatGPT, via Codex**, puis corrigé et vérifié au fil des essais et des tests automatisés. Les illustrations du livre rouge et les icônes de relation ont également été générées avec les outils d'image d'OpenAI.

C'est un petit projet personnel, partagé tel quel. Il pourra évoluer avec les retours, les envies et les contributions, sans calendrier promis. Prenez-le, testez-le, modifiez-le, faites votre propre version : il est là pour être utile et partagé, dans le cadre de sa licence GPLv3.

## Ce qu'il propose

- **Un menu au clic droit** sur les portraits et noms du chat pris en charge : Ami, Méfiance, Ennemi, avis positif ou négatif, note et fiche personnelle.
- **Des repères visuels** sur les barres de noms visibles : cœur vert pour les amis, œil orange pour la méfiance, cœur brisé rouge pour les ennemis. La coloration supplémentaire des noms est facultative.
- **Des filtres de faction et des identités détaillées** : combiner Amis, Méfiance ou Ennemis avec Alliance ou Horde, avec le nombre de personnes correspondantes. Race et classe apparaissent sous chaque nom et dans la fiche, avec leurs icônes natives lorsqu’elles sont disponibles. Les factions inconnues ont leur filtre ; les anciennes fiches se complètent à la prochaine rencontre observée. La race ne détermine jamais la faction.
- **Un historique PvP** des agressions et des morts observées, avec distinction entre faits confirmés et déductions probables. Une attribution erronée peut être corrigée.
- **La camaraderie par les emotes** que vous envoyez à un joueur ciblé, y compris de l'autre faction. Les répétitions sont limitées pour éviter de gonfler les scores.
- **Des avis sur des guildes entières**, avec des exceptions individuelles.
- **Des alertes de rencontre** en bas à gauche, au-dessus du chat principal, avec un petit son, des délais entre répétitions et un regroupement pour les membres d'une même guilde. Elles suivent la position du chat en laissant une marge au-dessus des onglets. Aucun rappel pour les amis du groupe ou du raid. Les autres amis sont annoncés à la première rencontre, puis seulement après plus de dix minutes sans présence observée : chaque recroisement repousse ce délai, même après un rechargement d'interface. Chaque personnage possède son propre compteur.
- **Une liste centrée sur vos relations** : rejoindre un groupe n’ajoute plus les inconnus. Les groupes partagés sont suivis pour vos contacts ; les anciennes fiches constituées uniquement de groupes sont masquées sans effacement. Les avis, notes et événements PvP restent visibles.
- **Un journal personnel** pour les notes, rencontres, groupes partagés et événements PvP, accessible par le livre de la minimap ou `/gl`.

![Aperçu hors jeu du journal sur parchemin, avec des personnages fictifs](docs/journal.png)

Le journal est un livre ouvert : deux pages de parchemin vieilli, du cuir rouge cousu, des tranches de feuilles et de fines ferrures. L’index conserve les icônes et les libellés de relation, avec une encre sombre lisible. Le classement et la prise de notes restent en haut ; les actions moins fréquentes passent au pied de la page. L’inspiration vient d’Overlord, avec des illustrations originales. Cet aperçu provient du véritable agencement Lua, simulé hors jeu avec des personnages fictifs ; les polices et icônes natives sont approximées.

Les titres, les noms et le texte de la fiche utilisent désormais les familles calligraphiques natives de WoW (Morpheus pour l’alphabet latin). Les notes se lisent et se saisissent en 15 pixels ; les commandes et petites indications conservent une police compacte.

## Solde de rancune

Les fiches automatiques comptent **−10 par mort, −1 par agression et +1 par victoire**. Les gestes négatifs s'ajoutent : une mort, un geste négatif et deux victoires donnent **−9**, donc **Méfiance (orange)** avec une alerte de proximité. Les victoires seules ne créent jamais d'amitié ; les gestes amicaux ne masquent pas une dette PvP encore négative. Les classements et avis manuels restent prioritaires. Les anciennes fiches automatiques sont recalculées sans effacer notes, compteurs ni historique.

Un **médaillon gris** identifie les personnes connues neutres dans le journal et sur leurs barres de noms. Elles ne déclenchent ni popup ni son. Les inconnus ne reçoivent pas de marqueur.

## Installation et premiers pas

1. Télécharger **`GrudgeLedger-0.4.2.zip`** dans les [versions publiées](https://github.com/Aizakira/GrudgeLedger/releases/latest).
2. Extraire le dossier `GrudgeLedger` dans `Interface/AddOns` du client Forever. Le fichier doit se trouver ici : `Interface/AddOns/GrudgeLedger/GrudgeLedger.toc`.
3. Redémarrer WoW et activer Grudge Ledger dans la liste des addons.

Aucune dépendance n'est nécessaire. Désactivez Grudgebook et Worth Remembering si vous les utilisez pour le même rôle, afin d'éviter les doublons de menus, marqueurs et alertes. Les archives automatiques **Source code** de GitHub contiennent aussi les fichiers de développement : seul leur dossier intérieur `GrudgeLedger` va dans `AddOns`.

Un clic gauche sur le livre ouvre le journal, un clic droit ouvre les réglages. Vous pouvez le faire glisser autour de la minimap. Pour ajouter quelqu'un, faites un clic droit sur son portrait ou son nom dans le chat, puis survolez **Grudge Ledger**. Pas besoin de recherche ni de commande. L'interface en jeu est actuellement principalement en français.

Pour voir les icônes et couleurs, cliquez sur **« Activer le repérage (icônes + couleurs) »** dans les réglages, ou utilisez `/gl reperage` hors combat. Cela active les barres des joueurs alliés, les barres ennemies et leur affichage hors combat, ainsi que les marqueurs et couleurs de l'addon. Les simples noms flottants ne sont pas des barres de noms modifiables. Un ami du groupe conserve son cœur ; seul le popup de proximité est supprimé. Si l'infobulle indique Ami mais que le cœur manque, activer le repérage hors combat. Le mode natif « nom uniquement » est pris en charge, y compris lorsque Threat Plates masque son propre texte. **Ennemi** donne le rouge ; **Méfiance** ou un simple avis négatif donne l'orange.

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
/gl reperage
/gl debug
```

Les actions concernent le joueur ciblé. Le [guide complet](GrudgeLedger/README.txt) détaille les classements, les corrections et les sauvegardes.

## Compatibilité et limites

Prévu pour **Forever, interface 16001** ; développé avec le client **1.60.1.70862**. Les versions Retail, Classic et les autres serveurs ne sont pas validés. Les marqueurs nécessitent des barres de noms visibles et respectent les limites de portée du jeu. Ce n'est ni un radar couvrant toute la zone, ni un détecteur de furtivité.

Forever peut masquer le journal de combat. L'addon consulte aussi son récapitulatif natif de mort, avec jusqu'à deux secondes d'attente. Il enregistre plusieurs agresseurs par GUID : le coup fatal explicite est confirmé, les autres participations à l'attaque mortelle sont probables. Sans preuve exploitable, seuls des adversaires en combat qui vous ciblaient récemment peuvent être retenus comme participants probables ; les simples passants sont exclus. Les compteurs sont individuels : trois participants à un même décès ne signifient pas trois morts du personnage. Les déductions peuvent être corrigées et la couverture reste limitée par les données fournies par le jeu. Les anciens décès manqués ne sont pas reconstitués automatiquement.

Les boutons et avis manuels conservent leur priorité, même après une emote. Les gestes seuls ne verrouillent plus le classement : un `/spit` ne bloque pas le passage en ennemi après une mort PvP. La détection des duels dépend des signaux disponibles.

Treize scripts de tests automatisés, dont 71 scénarios de suivi, accompagnent les sources. Ils simulent les API de WoW et ne remplacent pas les essais en jeu. C'est encore une jeune version : vos retours sont les bienvenus.

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
python -m zipfile -c GrudgeLedger-0.4.2.zip GrudgeLedger
```

## Licence et crédits

Le projet est sous **GNU GPL v3** : vous pouvez l'utiliser, l'étudier, le modifier, le partager et même le redistribuer commercialement, dans les conditions de cette licence. Les versions modifiées redistribuées doivent conserver les mentions, fournir leurs sources correspondantes et rester sous GPLv3. Le logiciel est fourni sans garantie. Voir [LICENSE](LICENSE).

Certaines techniques d'intégration des menus, barres de noms et infobulles sont adaptées de [Worth Remembering, par Kyle (maliceftw)](https://github.com/kk-on-gh/WorthRemembering), déjà sous GPLv3. Le suivi PvP a été réimplémenté en s'inspirant de l'approche décrite par [Grudgebook](https://www.curseforge.com/wow/addons/grudgebook). Aucun de ces addons n'est inclus ni requis. Les [crédits détaillés](GrudgeLedger/CREDITS.txt) sont conservés.

Les contributions originales, la documentation et les illustrations générées incluses sont partagées sous les mêmes conditions GPLv3. Les textures et sons natifs de WoW sont référencés depuis le client, sans être redistribués. Projet non officiel, sans affiliation avec Blizzard Entertainment ou OpenAI.
