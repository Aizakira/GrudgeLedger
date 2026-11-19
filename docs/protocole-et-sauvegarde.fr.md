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

Un événement de `history` porte toujours sa date, sa zone, son auteur (`actorGUID`, `actorName`) et son type : `kill`, `death`, `aggression`, `opening`, `honor`, `reputation`, `reaction`, `grouped` ou `trade`. Une correction ne supprime rien : elle marque l'événement `voided` et garde la preuve d'origine.

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
| `dossiers` | Relevés publics reçus, par cible : `fields` (une entrée par champ, avec `data`, `at` et `source`), `received`, `sender`, `senderName` | 256 cibles, la plus ancienne est évincée |
| `dossierSeq` | Dernier numéro de transfert de relevé émis | — |
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

Tous les messages passent par le canal addon de la guilde, avec le préfixe `GLBounty1`. Un seul fichier les envoie et les reçoit : `Bounties.lua`.

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
| `J;S1;Q;cible` | Demande du relevé public d'une cible |
| `J;S1;P;cible;numéro;partie;total;corps` | Fragment d'un relevé |

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

### Relevés `S1`

Le corps d'un relevé est une structure à longueurs préfixées (`t` table, `s` texte, `n` nombre), puis échappée en `%XX`. Seuls les champs d'une liste fermée sont acceptés : identité, équipement, talents, caractéristiques, niveau, JcJ, réputations, champs de bataille, hauts faits, et le témoignage de l'expéditeur.

| Limite | Valeur |
| --- | --- |
| Taille d'un fragment | 180 octets |
| Fragments par relevé | 256 |
| Taille d'un relevé encodé | 46 080 octets |
| Transferts entrants simultanés | 8 |
| Durée de vie d'un transfert incomplet | 300 secondes |
| Délai entre deux demandes, et entre deux réponses, pour une cible | 300 secondes |
| Faits par témoignage | 32 |
| Envoi spontané d'un témoignage modifié | Une cible toutes les 30 secondes |
| Décodage | 8 192 éléments, profondeur 10, texte de 2 048 octets, table de 1 024 clés |

### Limites communes

| Limite | Valeur |
| --- | --- |
| Taille d'un message | 255 octets |
| Cadence d'envoi | Un message toutes les 0,5 seconde, ralentie par la limite du jeu |
| File des relevés | 512 messages ; au-delà, l'envoi du relevé est refusé |
| Messages acceptés d'un même expéditeur | 45 par tranche de 10 secondes |
| Demande `Q` d'un même expéditeur | Une par tranche de 10 secondes |
| Conservation des événements de primes | 38 jours |
| Primes ouvertes par commanditaire | 10 |
| Durée d'une prime | 7 jours, prolongeable jusqu'à 31 |
| Montant d'une cagnotte | 1 000 pièces d'or |

### Compatibilité

Les relevés `S1` exigent la 0.12.0 ou une version compatible des deux côtés. Les versions antérieures reçoivent les primes et les avis et ignorent le reste. Tout changement de forme d'un message doit dire ici ce que voient les clients restés à l'ancienne version.

### Défauts connus de la 0.12.0

L'audit du 19 novembre 2026 a confirmé quatre défauts de ce protocole. Ils ne sont pas corrigés par ce document.

1. Un membre qui se connecte reçoit les primes en quelques secondes et les relevés plus de 5 minutes après.
2. Chaque client redemande et renvoie tous les relevés toutes les 5 minutes, même sans nouveauté.
3. Un fragment isolé occupe un emplacement de réception pendant 300 secondes ; huit suffisent à bloquer la réception.
4. Un envoi refusé par le jeu pour une autre raison que la limite de débit est compté comme envoyé.
