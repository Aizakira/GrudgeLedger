# Protocole de guilde et format de sauvegarde

Ce document est la seule référence pour deux choses : ce que l'addon enregistre sur le disque, et ce qu'il envoie aux autres membres de la guilde. Il décrit l'état du code à la version 0.12.0.

**Règle de tenue à jour.** Toute modification qui ajoute une clé sauvegardée, un champ de guilde ou un type de message met ce document à jour dans la même pull request. Le contrôle `tests/structure_test.lua` échoue si une clé, un champ ou un type d'événement de prime présent dans le code n'est pas cité ici entre accents graves.

## 1. Sauvegarde `GrudgeLedgerDB`

Le jeu écrit cette table sur le disque au `/reload` et à la déconnexion. Elle est commune à tous les personnages du compte.

### Clés de premier niveau

| Clé | Contenu | Module qui écrit | Borne ou durée |
| --- | --- | --- | --- |
| `schema` | Numéro de schéma du carnet, actuellement 2 | `Core.lua` | — |
| `players` | Fiches du carnet personnel, par clé `guid:Player-…` ou `name:prénom nom` | `Core.lua`, seul | Aucune : les souvenirs ne sont jamais supprimés en silence |
| `aliases` | Nom complet en minuscules → clé de fiche ; `false` quand deux personnages portent le même nom | `Core.lua` | — |
| `guilds` | Avis personnel sur une guilde entière, par `royaume:nom` | `Core.lua` | Note de 2 000 octets au plus |
| `settings` | Réglages du joueur | `Core.lua` | Valeurs validées au chargement |
| `unassignedHonor` | Gains d'honneur sans adversaire identifié | `Core.lua` | — |
| `quarantine` | Entrées illisibles mises de côté au lieu d'être effacées | `Core.lua` | — |
| `armoryRequests` | Demandes d'import destinées au compagnon | `Core.lua` | Purgées après 7 jours |
| `detectionLog` | Dernières décisions de détection et d'alerte | `Core.lua` | 200 entrées |
| `battlegroundArchive` | Fiches retirées par le nettoyage des champs de bataille | `Core.lua` | — |
| `battlegroundCleanupVersion` | Marqueur de la migration 2 | `Core.lua` | — |
| `grimoireFontDefaultApplied` | Marqueur de la migration 3 | `Core.lua` | — |
| `authorAccount` | Identifiant aléatoire du compte, 16 caractères hexadécimaux. Diffusé dans les fiches de guilde | `Core.lua` | — |
| `journalEdition` | Compteur des fiches de guilde publiées | `GuildProfiles.lua` | — |
| `bountyGuilds` | Un espace par guilde, par `royaume/guilde`. Détail plus bas | `Bounties.lua`, `GuildProfiles.lua`, `SharedDossiers.lua` | Jamais purgé à ce jour, même après un départ de guilde |
| `bountyHistory` | Primes passées qui concernent chaque personnage | `Bounties.lua` | — |
| `characterHistory` | Historique daté de chaque personnage, par GUID : `state` et `stateAt` (dernière valeur connue et sa date), `changes` (chaque changement : `at`, `key` parmi `level`, `ilvl`, `spec`, `guild` et `gear:emplacement`, `value`, `source`, `by`), `seen`, et `presence` (apparitions : `hours` par case jour × heure, `zones` avec leur nombre, `visits` les plus récentes avec `at` et `zone`, `days` le nombre d'apparitions par jour du calendrier (année × 1000 + jour de l'année), `total`, `since`) | `CharacterHistory.lua`, `CharacterInsights.lua` | 120 changements, 20 visites, 12 zones et 400 jours par personnage, 600 personnages ; les moins récemment vus sont retirés |
| `bountyInbox` | En-têtes de courrier en attente de rapprochement avec une prime | `Bounties.lua` | 128 en-têtes non vérifiés, 38 jours |
| `bountyPins` | Primes épinglées, par personnage | `BountyUI.lua` | — |
| `tracker` | Groupes en cours, pour compter les sessions partagées | `Tracker.lua` | — |
| `zoneExposure` | Temps passé par zone, si le réglage est activé | `ZoneTime.lua` | Archives bornées |
| `partyWarningLastAttempt` | Dernier avertissement envoyé au groupe, par personnage | `Display.lua` | — |
| `gesturePosition` | Position des boutons de gestes | `QuickGestures.lua` | — |
| `minimapProbe` | Dernier résultat de l'essai de minimap | `MinimapProbe.lua` | — |
| `druidRadarTests` | Résultats des essais du radar druide | `DruidRadar.lua` | — |

### Fiche d'un joueur

Chaque entrée de `players` regroupe quatre familles de champs.

| Famille | Champs |
| --- | --- |
| Identité | `key`, `guid`, `name`, `surname`, `fullName`, `class`, `className`, `race`, `raceName`, `raceID`, `sex`, `faction`, `level`, `guild`, `realm`, `guildSeenAt` |
| Avis | `reaction`, `reactionSource`, `reputation`, `tags`, `tagHistory`, `notes` |
| Faits | `history`, `pvp` (victoires, morts, agressions), `groupCount`, `encounters`, `firstSeen`, `lastSeen`, `lastEncounterAt`, `lastDirectEncounterAt` |
| Relevés | `inspection` (équipement, talents et caractéristiques vus en jeu, chacun avec sa date), `armorySnapshot` (copie du relevé Web importé) |

Un événement de `history` porte toujours sa date, sa zone, son auteur (`actorGUID`, `actorName`) et son type : `kill`, `death`, `aggression`, `opening`, `honor`, `reputation`, `reaction`, `grouped` ou `trade`. Depuis la 0.13.1, une victoire, une mort ou une agression porte aussi `build` : `opponent` et `me`, le build de chaque joueur au moment du combat (`level`, `ilvl`, `spec`, `specName`, `stats`, `gear` par emplacement, et pour l'adversaire `at`, `source`, `by`, la date et l'origine du relevé). Depuis la 0.18.0, `me` porte aussi `spec` et `specName`, lus dans nos arbres de talents. Il n'est jamais réécrit. Une correction ne supprime rien : elle marque l'événement `voided` et garde la preuve d'origine.

### Espace d'une guilde

Chaque entrée de `bountyGuilds` contient les champs suivants.

| Champ | Contenu | Borne ou durée |
| --- | --- | --- |
| `guildKey` | Rappel de la clé `royaume/guilde` | — |
| `events` | Journal des événements de primes, tels que reçus, par `auteur:numéro` | 38 jours, sauf reçus encore utiles |
| `seq` | Dernier numéro d'événement émis par ce client | — |
| `scores` | Victoires et morts cumulées, par cible puis par membre | — |
| `shareFights`, `shareDeaths`, `shareSocial` | Accords de partage, par personnage. Absents ou faux par défaut | — |
| `mailUncertain` | Envoi de courrier dont l'accusé n'a pas été reçu | Un par personnage |
| `journal` | Fiches de guilde. Détail ci-dessous | — |
| `dossiers` | Relevés publics, par cible : `fields` (une entrée par champ, avec `data`, `at`, `source`, `by`, `via` et, pour l'équipement, l'identité et les caractéristiques, `dates`), `received`, `sender`, `senderName`. Une inspection d'une cible sans fiche personnelle y est aussi gardée | 256 cibles, la plus ancienne est évincée |
| `dossierSeq` | Dernier numéro de transfert de relevé émis | — |
| `bountyRecords` | Dossier de primes par cible, gardé après l'effacement des événements : `name`, `at` (dernière prime) et `orders` par `auteur:numéro` (`at`, `owner`, `pot` total promis en cuivre, `state`, `endedAt`, `expires`, `quota`, `hunter`, `helpers`, `killedAt`). Chaque membre garde la copie de ce qu'il a vu ; rien n'est transmis | 30 primes par cible, 400 cibles, les plus anciennes sont évincées |
| `socialReports` | Témoignages reçus, par `auteur:cible` : solde, relation, 32 faits au plus, ou marque de retrait | 256 témoignages |

Le champ `journal` contient lui-même : `cards` (fiches publiées, avec leurs avis), `hidden` (cibles masquées localement), `withdrawn` (fiches retirées et leur secret), `secrets` (secrets des fiches publiées par ce compte), `seq`, `auto` (publication automatique), `retired` (cibles à ne pas republier) et `byTarget` (index reconstruit à l'usage).

### Migrations

Trois migrations existent. Elles sont repérées par trois marqueurs indépendants, ce qui est un défaut : les suivantes seront numérotées dans une seule liste.

| N° | Marqueur | Effet | Peut-on revenir en arrière ? |
| --- | --- | --- | --- |
| 1 | `schema` = 2 | Les compteurs et événements « probables » sont fondus dans les « confirmés » ; les doublons d'un même identifiant d'événement sont annulés | Non : aucune copie n'est gardée |
| 2 | `battlegroundCleanupVersion` = 1 | Les événements des champs de bataille connus sont annulés ; les fiches devenues vides vont dans `battlegroundArchive` | Oui : rien n'est effacé |
| 3 | `grimoireFontDefaultApplied` | Le réglage de police revient une fois à sa valeur par défaut | Sans objet |

**Règle pour la migration 4 et les suivantes.**

1. Elle porte un numéro, à la suite de cette table.
2. Elle conserve dans la sauvegarde les valeurs qu'elle remplace.
3. Elle a un test qui charge un carnet synthétique de la version précédente et vérifie que chaque valeur d'origine reste retrouvable.
4. Elle ne s'exécute qu'une fois et peut être rejouée sans dommage.

## 2. Messages de guilde

Tous les messages passent par le canal addon de la guilde, avec le préfixe `GLBounty1`. Un seul fichier les envoie et les reçoit : `Transport.lua`. Les autres modules lui confient des messages terminés ; `Bounties.lua` interprète les primes et les fiches de guilde, `SharedDossiers.lua` les relevés.

### Règles de confiance

- L'expéditeur est identifié par le registre de guilde du jeu. Un message dont l'expéditeur n'y figure pas est ignoré.
- Un message reçu est une donnée à format strict. Il n'est jamais exécuté.
- Un membre peut relayer les événements de primes, les totaux et les retraits de fiche. Il ne peut pas relayer un témoignage : celui-ci n'est accepté que de son auteur.
- Une donnée reçue est un témoignage ou un relevé rapporté, pas une preuve.

### Formes de message

| Forme | Rôle |
| --- | --- |
| `type;auteur;numéro;date;objet;valeur;détail` | Événement de prime, 250 octets au plus. Types ci-dessous |
| `G;auteur;cible;victoires;morts` | Totaux cumulés d'un membre contre une cible, si `shareFights` est accordé |
| `Q` | Demande de rattrapage à la connexion |
| `R;…` | Relais d'un événement ou d'un total, en réponse à `Q` |
| `J;C;cible;empreinte;date;compte;nom` | Publication d'une fiche de guilde |
| `J;T;propriétaire;cible;empreinte;numéro;date;compte;étiquette;0 ou 1` | Avis d'un membre sur une fiche |
| `J;D;propriétaire;cible;secret` | Retrait d'une fiche ; le secret prouve le droit de retirer |
| `J;V;clé` | Demande de rejeu d'une fiche |
| `J;S2;Q;cible;dates` | Demande du relevé public d'une cible. `dates` donne, pour chacun des onze champs publics, la date du relevé déjà détenu (0 s'il manque) |
| `J;S2;P;cible;numéro;nature;partie;total;corps` | Fragment d'un relevé. `nature` vaut `r` pour une réponse contenant des données publiques, `t` pour le seul témoignage de l'expéditeur |

### Types d'événement de prime

| Type | Sens | Auteur admis |
| --- | --- | --- |
| `O` | Prime simple : cible, montant, nom | Tout membre |
| `N` | Prime personnalisée : montant, nombre de victoires, règles de groupe, de partage et de souvenir | Tout membre |
| `A` | Prime automatique, sans montant, valable 3 jours | Tout membre |
| `D` | Mort signalée, si `shareDeaths` est accordé. Refusée au-delà de 2 heures | La victime |
| `P` | Contribution à la cagnotte | Tout membre |
| `K` | Victoire revendiquée sur une prime simple, avec les équipiers visibles | Le chasseur |
| `H` | Victoire revendiquée sur une prime personnalisée, avec niveaux et équipiers de guilde | Le chasseur |
| `U` | Consigne modifiée ou prime prolongée | Le commanditaire |
| `S` | Succession : cette prime remplace une prime close à la même seconde | Le commanditaire |
| `X` | Retrait de la prime | Le commanditaire |
| `F` | Désignation de la revendication gagnante | Le commanditaire |
| `Y` | Paiement déclaré envoyé par un contributeur | Le payeur |
| `V` | Courrier constaté reçu | Le bénéficiaire |

### Relevés `S2`

Le corps d'un relevé est une structure à longueurs préfixées (`t` table, `s` texte, `n` nombre), puis échappée en `%XX`. Seuls les champs d'une liste fermée sont acceptés : identité, équipement, talents, caractéristiques, niveau, JcJ, réputations, champs de bataille, hauts faits, et le témoignage de l'expéditeur.

Ordre des dates d'une demande : `identity`, `gear`, `trees`, `stats`, `level`, `averageItemLevel`, `honorableKills`, `pvpRank`, `reputations`, `battlegrounds`, `achievements`. Chaque date est un temps Unix en secondes.

Échange :

1. Un membre demande chaque cible partagée ou primée, au plus une fois toutes les 5 minutes, en annonçant les dates de ce qu'il détient.
2. Un détenteur ne répond qu'avec les champs plus récents que ceux annoncés. S'il n'a rien de plus récent, il se tait. Un arrivant qui n'a rien est donc servi à sa première demande.
3. La réponse attend de 0 à 7 secondes, selon le membre et la cible. Quand un autre membre commence une réponse `r` pour la même cible, une réponse encore en attente est annulée. Les champs qui manqueraient arrivent à la demande suivante.
4. Le témoignage de l'expéditeur accompagne chaque réponse `r`. Sans données publiques à envoyer, il part seul (`t`) s'il a changé ou s'il n'a pas été diffusé depuis 30 minutes.
5. Un fragment n'ouvre un transfert que s'il en est la partie 1. Un expéditeur n'a qu'un transfert ouvert à la fois ; les parties doivent arriver dans l'ordre.
6. Chaque champ transmis porte son observateur `by` (le membre qui a fait l'inspection ou importé la fiche Armurerie) et, quand il relaie le relevé d'un autre, l'expéditeur le note en `via`. Sans `by`, l'expéditeur est l'observateur. Un membre qui aperçoit lui-même la cible ne devient pas l'observateur des champs reçus.
7. L'équipement, l'identité et les caractéristiques portent `dates`, la date de chaque pièce ou valeur. Un relevé partiel plus récent complète les manques avec les pièces plus anciennes, qui gardent leur propre date. La fiche signale une pièce vue plus d'une heure avant le relevé principal.

Ces deux champs sont facultatifs : un client 0.13.0 les ignore, et une réception sans eux date chaque pièce du relevé entier.

| Limite | Valeur |
| --- | --- |
| Taille d'un fragment | 180 octets |
| Fragments par relevé | 256 |
| Taille d'un relevé encodé | 46 080 octets |
| Transferts entrants simultanés | 8, un par expéditeur |
| Abandon d'un transfert incomplet | 120 secondes après son dernier fragment |
| Délai entre deux demandes pour une cible | 300 secondes |
| Délai entre deux réponses `r` pour une cible | 60 secondes |
| Attente avant une réponse | 0 à 7 secondes, propre à chaque membre |
| Rediffusion d'un témoignage inchangé | 30 minutes |
| Faits par témoignage | 32 |
| Envoi spontané d'un témoignage modifié | Une cible toutes les 30 secondes |
| Décodage | 8 192 éléments, profondeur 10, texte de 2 048 octets, table de 1 024 clés |

### Limites communes

| Limite | Valeur |
| --- | --- |
| Taille d'un message | 255 octets |
| Cadence d'envoi | Un essai toutes les 0,5 seconde, ralenti par la limite du jeu (10 messages d'avance, puis un par seconde selon la documentation, à confirmer sur Forever) |
| Priorité | Primes, totaux, rattrapage et fiches de guilde passent avant les relevés |
| File des relevés | 512 messages ; au-delà, l'envoi du relevé est refusé et réessayé à la demande suivante |
| Refus du jeu | Codes 3, 8 et 11 (limites de débit, messagerie verrouillée) : le message attend. Code 9 (erreur générale) : trois essais. Autre code : message abandonné, avec le reste de son transfert |
| Messagerie verrouillée | Aucun envoi tant que `C_ChatInfo.InChatMessagingLockdown()` répond vrai |
| Messages acceptés d'un même expéditeur | 45 par tranche de 10 secondes |
| Demande `Q` d'un même expéditeur | Une par tranche de 10 secondes |
| Conservation des événements de primes | 38 jours |
| Primes ouvertes par commanditaire | 10 |
| Durée d'une prime | 7 jours, prolongeable jusqu'à 31 |
| Montant d'une cagnotte | 1 000 pièces d'or |

### Compatibilité

Décision du propriétaire, 19 novembre 2026 : pas de compatibilité. Les relevés `S2` exigent la 0.13.0 des deux côtés. Une 0.13.0 ignore les messages `S1` de la 0.12.0, et une 0.12.0 ignore les messages `S2`. Les deux versions continuent d'échanger les primes, les totaux et les fiches de guilde, dont le format n'a pas changé. Les versions antérieures à la 0.12.0 ignorent tous les relevés. Tout changement de forme d'un message doit dire ici ce que voient les clients restés à l'ancienne version.

### Défauts de la 0.12.0 corrigés en 0.13.0

L'audit du 19 novembre 2026 avait confirmé quatre défauts du protocole `S1`. `tests/guild_sync_test.lua` échoue si l'un d'eux revient.

1. Un membre qui se connecte recevait les primes en quelques secondes et les relevés plus de 5 minutes après. Il est désormais servi à sa première demande.
2. Chaque client redemandait et renvoyait tous les relevés toutes les 5 minutes. Au repos, il ne reste que les demandes : une par membre et par cible toutes les 5 minutes.
3. Un fragment isolé occupait un emplacement de réception pendant 300 secondes. Seule une partie 1 ouvre désormais un transfert, un par expéditeur.
4. Un envoi refusé par le jeu pour une autre raison que la limite de débit était compté comme envoyé. Tous les codes de retour sont lus.
