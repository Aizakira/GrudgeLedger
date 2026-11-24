# Protocole de guilde et format de sauvegarde

Ce document est la seule référence pour deux choses : ce que l'addon enregistre sur le disque, et ce qu'il envoie aux autres membres de la guilde. Il décrit l'état du code à la version 0.12.0.

**Règle de tenue à jour.** Toute modification qui ajoute une clé sauvegardée, un champ de guilde ou un type de message met ce document à jour dans la même pull request. Le contrôle `tests/structure_test.lua` échoue si une clé, un champ ou un type d'événement de prime présent dans le code n'est pas cité ici entre accents graves.

## 1. Sauvegarde `GrudgeLedgerDB`

Le jeu écrit cette table sur le disque au `/reload` et à la déconnexion. Elle est commune à tous les personnages du compte.

Depuis la 0.54.0, le carnet est tenu **par faction** : `players`, `aliases`, `guilds`, `unassignedHonor` et `battlegroundArchive` sont ceux de la faction du personnage joué. Le carnet de l'autre faction attend dans `books`, intact. Le reste est commun au compte (réglages) ou déjà rangé par guilde ou par personnage.

### Clés de premier niveau

| Clé | Contenu | Module qui écrit | Borne ou durée |
| --- | --- | --- | --- |
| `sharingNotice` | Ancien marqueur du message de partage (0.51.0, un par compte). Plus lu depuis la 0.54.0 : le message est noté dans l'espace de chaque guilde (`noticed`) | `GuildMap.lua` | — |
| `book` | Faction du carnet en cours (`Alliance` ou `Horde`), depuis la 0.54.0. Absent avant la migration 5 | `Core.lua` | — |
| `books` | Carnets des autres factions, par faction : mêmes clés (`players`, `aliases`, `guilds`, `unassignedHonor`, `battlegroundArchive`) | `Core.lua` | Jamais purgé |
| `characterFactions` | Faction de chaque personnage du compte vu depuis la 0.54.0, par GUID | `Core.lua` | Un par personnage |
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
| `migrations` | Migrations exécutées, par numéro, avec leur date | `Core.lua` | Une entrée par migration |
| `replacedWeights` | Poids de rancune d'avant la migration 4 (`aggression`, `death`, `victory`), gardés pour mémoire | `Core.lua` | Écrit une seule fois |
| `authorAccount` | Identifiant aléatoire du compte, 16 caractères hexadécimaux. Jamais diffusé tel quel : depuis la 0.22.0, les fiches de guilde portent une empreinte propre à chaque guilde (SHA-256 de l'identifiant et de la clé de guilde, 16 caractères), qui ne relie pas les personnages d'une guilde à l'autre | `Core.lua`, `GuildProfiles.lua` | — |
| `journalEdition` | Compteur des fiches de guilde publiées | `GuildProfiles.lua` | — |
| `bountyGuilds` | Un espace par guilde, par `royaume/guilde`. Détail plus bas | `Bounties.lua`, `GuildProfiles.lua`, `SharedDossiers.lua` | Jamais purgé à ce jour, même après un départ de guilde |
| `bountyHistory` | Primes passées qui concernent chaque personnage | `Bounties.lua` | — |
| `errorLog` | Les vingt dernières erreurs de l'addon (date, version, texte coupé à 400 caractères, nombre de répétitions), gardées d'une session à l'autre pour le rapport de `/gl debug` (0.61.0) | `Core.lua` | Les plus anciennes sortent au-delà de vingt |
| `bountyPaymentWatch` | Par personnage, l'or pas encore envoyé sur chaque prime remportée, au dernier calcul (0.58.4) : un paiement envoyé pendant votre absence est annoncé à la connexion suivante | `BountyUI.lua` | Réécrit à chaque calcul ; seules les primes encore attendues y restent |
| `characterHistory` | Historique daté de chaque personnage, par GUID : `state` et `stateAt` (dernière valeur connue et sa date), `changes` (chaque changement : `at`, `key` parmi `level`, `ilvl`, `spec`, `guild` et `gear:emplacement`, `value`, `source`, `by`), `seen`, et `presence` (apparitions : `hours` par case jour × heure, `zones` avec leur nombre, `visits` les plus récentes avec `at` et `zone`, `days` le nombre d'apparitions par jour du calendrier (année × 1000 + jour de l'année), `total`, `since`) | `CharacterHistory.lua`, `CharacterInsights.lua` | 120 changements, 20 visites, 40 zones et 400 jours par personnage, 600 personnages ; les moins récemment vus sont retirés |
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
| Coups de main | `assists` (nombre), depuis la 0.36.0 : vous combattiez ce joueur, le jeu vous a donné de l'honneur pour sa mort, le coup fatal venait d'un joueur hors de votre groupe. Compté à part, jamais dans le solde ni dans les victoires. Chaque coup de main ajoute un événement `assist` à `history` |
| Duels | `duels` (`wins`, `losses`), depuis la 0.31.0 : comptés à part, jamais dans le solde. Chaque duel ajoute un événement `duel` (`won`) à `history` |
| Faits | `history`, `pvp` (victoires, morts, agressions), `groupCount`, `encounters`, `firstSeen`, `lastSeen`, `lastEncounterAt`, `lastDirectEncounterAt` |
| Relevés | `inspection` (équipement, talents et caractéristiques vus en jeu, chacun avec sa date), `armorySnapshot` (copie du relevé Web importé) |

Depuis la 0.45.0, un combat (`kill`, `death`, `aggression`, `assist`) garde aussi sa position quand le jeu la donne : `mapID`, `mapX`, `mapY` (0 à 1, trois décimales). Elle reste dans le journal. La guilde n'apprend l'endroit d'une victoire ou d'une mort que si le joueur coche « Vision de guilde » (0.49.0, message `M`). Un événement de `history` porte toujours sa date, sa zone, son auteur (`actorGUID`, `actorName`) et son type : `kill`, `death`, `aggression`, `opening`, `honor`, `assist`, `reputation`, `reaction`, `grouped` ou `trade`. Depuis la 0.13.1, une victoire, une mort ou une agression porte aussi `build` : `opponent` et `me`, le build de chaque joueur au moment du combat (`level`, `ilvl`, `spec`, `specName`, `stats`, `gear` par emplacement, et pour l'adversaire `at`, `source`, `by`, la date et l'origine du relevé). Depuis la 0.18.0, `me` porte aussi `spec` et `specName`, lus dans nos arbres de talents. Il n'est jamais réécrit. Une correction ne supprime rien : elle marque l'événement `voided` et garde la preuve d'origine. Depuis la 0.27.0, le contexte `combat` d'une victoire peut porter `assist`, le nom du membre du groupe qui a porté le coup fatal. Les combats affichés (`GL.Fights`) sont calculés à la lecture : des événements à moins de deux minutes d'écart forment un combat, une mort ou une victoire le termine, sauf une victoire du groupe dans la minute qui suit votre mort. Les membres d'un groupe absents du carnet sont gardés en mémoire pour la session seulement, jamais sauvegardés.

### Espace d'une guilde

Chaque entrée de `bountyGuilds` contient les champs suivants.

| Champ | Contenu | Borne ou durée |
| --- | --- | --- |
| `guildKey` | Rappel de la clé `royaume/guilde` | — |
| `events` | Journal des événements de primes, tels que reçus, par `auteur:numéro` | 38 jours, sauf reçus encore utiles |
| `seq` | Dernier numéro d'événement émis par ce client | — |
| `since` | Date où ce carnet a connu la guilde (0.58.5) : un relais à votre nom plus récent, que vous n'avez pas, est une invention signalée | — |
| `scores` | Victoires et morts cumulées, par cible puis par membre | — |
| `shareFights`, `shareDeaths`, `shareSocial` | Partages, par personnage. Depuis la 0.51.0 ils sont actifs tant que la valeur n'est pas `false` : seul un refus explicite les coupe | — |
| `shareSightings` | Accord d'envoi des repérages (veille de guilde, 0.30.0), par personnage. Actif depuis la 0.51.0 tant que la valeur n'est pas `false` : l'envoi révèle la zone où l'on se trouve. Les repérages reçus ne sont jamais sauvegardés | — |
| `noticed` | Date du message unique qui prévient qu'on partage avec cette guilde (0.54.0) | — |
| `shareMap` | « Vision de guilde » (0.49.0), par personnage. Active depuis la 0.51.0 tant que la valeur n'est pas `false` : cochée, le personnage envoie l'endroit de ses victoires et de ses morts et garde ceux des autres | — |
| `places` | Combats partagés, par membre : lignes `date;carte;x;y;genre;adversaire;nom` (x et y en millièmes, genre `d` mort ou `k` victoire), la plus récente d'abord. Vidé quand la case est décochée. Sert à la carte et à l'alerte « Tueur de guilde » | 150 membres, 40 lignes par membre, 38 jours |
| `mapForgot` | Date du dernier `MX` de chaque membre : un relais plus ancien de ses combats est refusé. Effacée dès qu'il partage à nouveau | Un par membre |
| `mailUncertain` | Envoi de courrier dont l'accusé n'a pas été reçu | Un par personnage |
| `mailReturned` | Courriers de paiement revenus déjà déclarés (`Z`), pour ne pas les déclarer deux fois (0.62.0) | Un par courrier |
| `journal` | Fiches de guilde. Détail ci-dessous | — |
| `dossiers` | Relevés publics, par cible : `fields` (une entrée par champ, avec `data`, `at`, `source`, `by`, `via` et, pour l'équipement, l'identité et les caractéristiques, `dates`), `received`, `sender`, `senderName`. Une inspection d'une cible sans fiche personnelle y est aussi gardée | 256 cibles, la plus ancienne est évincée |
| `dossierSeq` | Dernier numéro de transfert de relevé émis | — |
| `bountyRecords` | Dossier de primes par cible, gardé après l'effacement des événements : `name`, `at` (dernière prime) et `orders` par `auteur:numéro` (`at`, `owner`, `pot` total promis en cuivre, `state`, `endedAt`, `expires`, `quota`, `hunter`, `helpers`, `killedAt`). Chaque membre garde la copie de ce qu'il a vu ; rien n'est transmis | 30 primes par cible, 400 cibles, les plus anciennes sont évincées |
| `socialReports` (lecture) | Depuis la 0.25.0, la somme des témoignages reçus et les mauvaises étiquettes des fiches de guilde donnent l'avis de la guilde sur un joueur (calculé à l'usage, non sauvegardé) : −10 ou moins ennemi, négatif ou mauvaise étiquette méfiance, +10 ou plus ami. Il ne s'applique que sans relation personnelle | — |
| `socialWithdrawn` | Pour chaque membre, numéro de son dernier retrait de tous ses témoignages (message `W`) ; un témoignage plus ancien est refusé | Un par membre |
| `socialPublisher` | Le personnage du compte qui donne l'avis du compte dans cette guilde (0.62.0). Les autres personnages du compte retirent leurs témoignages, pour que la guilde ne compte pas le même avis une fois par personnage | Un |
| `directClaims` | Clés des victoires de prime entendues de leur propre chasseur ou déclarées par vous (0.62.0). Seules elles peuvent désigner le gagnant : une victoire relayée par un autre membre ne le peut pas. Nettoyée avec les événements | Une par victoire |
| `directSince` | Date à partir de laquelle une victoire de prime doit avoir été entendue de son chasseur, ou retenue par l'auteur de la prime, pour compter (0.62.0). Les victoires plus anciennes comptent comme avant | Une |
| `relayed` | Clés des événements de prime reçus par relais, c'est-à-dire transmis par un autre membre (0.62.0). Ils ne comptent pas dans le quota de 600 messages du membre nommé. Si l'auteur les redit lui-même, ils redeviennent les siens. Nettoyé avec les événements. Depuis la 0.62.0, un relais au nom d'un membre connecté est refusé, pour les primes comme pour la carte | Un par événement relayé |
| `socialReports` | Témoignages reçus, par `auteur:cible` : solde, relation, 32 faits au plus, ou marque de retrait | 256 témoignages |

Le champ `journal` contient lui-même : `cards` (fiches publiées, avec leurs avis), `hidden` (cibles masquées localement), `withdrawn` (fiches retirées et leur secret), `secrets` (secrets des fiches publiées par ce compte), `seq`, `auto` (publication automatique), `retired` (cibles à ne pas republier) et `byTarget` (index reconstruit à l'usage).

### Migrations

Depuis la 0.23.0, les migrations sont numérotées dans `migrations` (numéro → date d'exécution ; 0 quand elle a eu lieu avant cette liste). Les trois anciens marqueurs restent lus et comptent comme faits. La migration 1 garde désormais ce qu'elle remplace : `migrated1` sur la fiche (compteurs « probables » fondus) et sur chaque événement (`confidence` et `evidence` d'origine). Sur un carnet déjà migré avant la 0.23.0, l'information perdue ne revient pas.

| N° | Marqueur | Effet | Peut-on revenir en arrière ? |
| --- | --- | --- | --- |
| 1 | `schema` = 2 | Les compteurs et événements « probables » sont fondus dans les « confirmés » ; les doublons d'un même identifiant d'événement sont annulés | Oui depuis la 0.23.0 : `migrated1` garde les valeurs remplacées. Non pour un carnet migré avant |
| 2 | `battlegroundCleanupVersion` = 1 | Les événements des champs de bataille connus sont annulés ; les fiches devenues vides vont dans `battlegroundArchive` | Oui : rien n'est effacé |
| 3 | `grimoireFontDefaultApplied` | Le réglage de police revient une fois à sa valeur par défaut | Sans objet |
| 4 | `migrations[4]` | « Une vie pour une vie » (0.42.0) : `grudgeVictory` apparaît (5 ; une victoire valait toujours 1) et une agression laissée à l'ancienne valeur par défaut (5, avec une mort à 5) passe à 2. Les poids choisis par le joueur sont conservés, tous les soldes automatiques sont recalculés | Oui : `replacedWeights` garde les anciennes valeurs, à remettre dans les réglages |

**Règle pour la migration 4 et les suivantes.**

1. Elle porte un numéro, à la suite de cette table.
2. Elle conserve dans la sauvegarde les valeurs qu'elle remplace.
3. Elle a un test qui charge un carnet synthétique de la version précédente et vérifie que chaque valeur d'origine reste retrouvable.
4. Elle ne s'exécute qu'une fois et peut être rejouée sans dommage.

Migration 5 (0.54.0), un carnet par faction. À la première connexion, la faction de chaque personnage qui a signé des faits est retrouvée : connue pour les personnages vus depuis la 0.54.0, sinon déduite de ses faits (on combat l'autre faction, on groupe et on échange avec la sienne). Chaque fait et chaque note va au carnet de la faction de son auteur. Une fiche qui a des faits des deux côtés est copiée, chaque copie gardant les siens et recomptant ses victoires, morts et agressions. Les faits sans auteur connu suivent la faction de l'adversaire : un combat va au carnet de la faction opposée à la sienne, un groupe au carnet de la sienne ; sans faction connue, ils restent dans le carnet en cours. Chaque copie d'une fiche garde le dernier avis de son propre historique, ou aucun (0.58.5). L'honneur sans adversaire (`unassignedHonor`) suit le personnage qui l'a gagné. Les avis sur les guildes sont copiés dans les deux carnets. Rien n'est effacé.

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
| `M;1;auteur;date;carte;x;y;genre;adversaire;nom` | Victoire (`k`) ou mort (`d`) de l'auteur : endroit et adversaire (identifiant et nom, 48 octets au plus, vides si inconnus), si `shareMap` est accordé. Gardé seulement par un membre qui a lui aussi coché la case. Reçu de l'auteur, il est tenu pour le sien. Reçu en relais (`R;M;…`), c'est un témoignage de guilde, refusé s'il précède un `MX` de l'auteur |
| `MQ` | Demande de ce que la guilde sait, quand un membre coche la case : chaque membre qui partage renvoie ses propres combats (40 au plus), et l'un d'eux, après 4 à 20 secondes et si personne ne l'a fait avant lui, relaie les 120 combats les plus récents des autres. Une réponse par demandeur toutes les 30 secondes. Depuis la 0.58.0, `Q` (connexion) ne déclenche que le relais, qui comprend alors aussi les combats du membre qui relaie |
| `GLP;marque` | Marque anonyme du joueur derrière le personnage (0.61.0) : huit chiffres hexadécimaux tirés du code aléatoire de l'installation et du nom de la guilde. Envoyée avec `GLV` et `GLVR`, jamais relayée, jamais sauvegardée. Sert seulement à compter les joueurs distincts de la guilde qui ont l'addon |
| `GLV;version`, `GLVR;version` | Version de l'addon du membre (0.58.0). `GLV` à la connexion ; chaque membre y répond par `GLVR`, une fois toutes les dix secondes au plus pour un même arrivant, et une seconde arrivée dans ce délai reçoit sa réponse dix secondes plus tard (0.58.6), et une réponse n'appelle jamais de réponse. Gardée en mémoire seulement, jamais sauvegardée. Un membre entendu sans cette annonce a une version antérieure à la 0.58.0 |
| `MX` | Le membre a décoché la case : ses combats sont effacés chez les autres et la date est notée dans `mapForgot` |
| `Q` | Demande de rattrapage à la connexion |
| Lots différés (0.60.1) | Les rattrapages partent en lots après les messages urgents : `journal:own` (fiches, avis et retraits de fiches de guilde, deux lots au plus), `bounty:join` (ses 300 événements de prime les plus récents, à sa propre connexion). Un total de combats `G` relayé est refusé au-delà de 2 000 victoires ou morts ; 100 000 quand il vient de son auteur |
| `R;…` | Relais d'un événement ou d'un total, en réponse à `Q`. Chaque membre envoie d'abord ses propres événements : les 150 plus récents parmi ceux des 38 derniers jours et ses reçus plus anciens, avec leur place réservée dans la file (envoyés à nouveau si un arrivant vient pendant l'envoi précédent ; deux lots au plus, celui qui part et le suivant). Un seul membre relaie ceux des autres : au plus 300 événements récents (dont 60 morts) puis 150 totaux, coupés à la place libre de la file en gardant 120 lignes, pour ces deux lots comme pour le relais des primes, au relais de la carte quand la vision de guilde est partagée et qu'il n'attend pas déjà. Le relais qui porte le plus d'événements de primes part le premier (2 à 20 secondes) ; les autres annulent le leur dès qu'ils voient passer un relais d'un autre membre. Au plus 900 relais nouveaux acceptés par membre et par session. Les types `F` (gagnant), `V` (réception), `X` (retrait), `U` et `S` (modification, succession) ne sont jamais acceptés en relais : ils n'arrivent que de leur auteur. Un relais ne parle que d'un membre de la liste de guilde. Le membre nommé dans un relais ignore ce que les autres disent en son nom ; s'il ne le connaît pas, la discussion le dit une fois en nommant le membre qui l'a transmis, sans le dire fautif (plantage, autre ordinateur ou invention). Deux victoires (`K`, `H`) d'un même chasseur sur un contrat comptent seulement à une minute d'écart au moins. Au plus 600 événements par membre sur 38 jours, 1 500 cibles et 60 membres par cible dans `scores` |
| `J;C;cible;empreinte;date;compte;nom` | Publication d'une fiche de guilde |
| `J;T;propriétaire;cible;empreinte;numéro;date;compte;étiquette;0 ou 1` | Avis d'un membre sur une fiche |
| `J;D;propriétaire;cible;secret` | Retrait d'une fiche ; le secret prouve le droit de retirer |
| `J;V;clé` | Demande de rejeu d'une fiche |
| `J;S2;Q;cible;dates` | Demande du relevé public d'une cible. `dates` donne, pour chacun des onze champs publics, la date du relevé déjà détenu (0 s'il manque) |
| `J;S2;V;cible;carte;relation;nom;zone` | Veille de guilde (0.30.0). L'expéditeur voit `cible` en ce moment. `carte` est l'identifiant de sa carte (0 si inconnu), `relation` vaut `e` (ennemi), `w` (méfiance), `b` (cible de prime) ou `h` (appel à l'aide, 0.31.0 : envoyé par le bouton « Appeler la guilde » d'une alerte, même sans `shareSightings`, et affiché chez tous les membres), `nom` et `zone` sont échappés et limités à 48 caractères. Envoyé seulement si `shareSightings` est coché, au plus une fois par cible toutes les deux minutes et une fois toutes les dix secondes en tout ; pas renvoyé si un membre vient de signaler la même cible dans la même carte |
| `J;S2;W;numéro` | L'expéditeur retire tous ses témoignages dans cette guilde. Envoyé dès qu'il décoche le partage, puis à chaque connexion tant que la case reste décochée |
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
| `Z` | Paiement revenu au payeur sans avoir été ouvert (0.62.0) : la somme est due à nouveau. Les versions plus anciennes l'ignorent | Le payeur |
| `V` | Courrier constaté reçu | Le bénéficiaire |

### Relevés `S2`

Le corps d'un relevé est une structure à longueurs préfixées (`t` table, `s` texte, `n` nombre), puis échappée en `%XX`. Seuls les champs d'une liste fermée sont acceptés : identité, équipement, talents, caractéristiques, niveau, JcJ, réputations, champs de bataille, hauts faits, et le témoignage de l'expéditeur.

Ordre des dates d'une demande : `identity`, `gear`, `trees`, `stats`, `level`, `averageItemLevel`, `honorableKills`, `pvpRank`, `reputations`, `battlegrounds`, `achievements`. Chaque date est un temps Unix en secondes.

Échange :

1. Un membre demande chaque cible partagée ou primée, au plus une fois toutes les 5 minutes, en annonçant les dates de ce qu'il détient.
2. Un détenteur ne répond qu'avec des relevés publics : fiches Armurerie et inspections. Rien de son carnet personnel n'y figure, ni la date de sa dernière rencontre (audit 0.12.0, problème 8). Il ne répond qu'avec les champs plus récents que ceux annoncés. S'il n'a rien de plus récent, il se tait. Un arrivant qui n'a rien est donc servi à sa première demande.
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
