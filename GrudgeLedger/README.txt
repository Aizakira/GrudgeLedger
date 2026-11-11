GRUDGE LEDGER — 0.5.5
Journal des amis et des rancunes pour WoW Forever (interface 16001).

INSTALLATION
Copier le dossier GrudgeLedger dans Interface/AddOns, puis redémarrer le jeu.
Utiliser Grudge Ledger seul pour cette fonction : désactiver Grudgebook et Worth
Remembering pour éviter plusieurs menus et marqueurs concurrents.
Aucune dépendance à ces deux addons n'est nécessaire.


Correctif 0.5.5 : préparation de la minimap depuis le diagnostic

Suppression de l'appel à GetMaskTexture, que la minimap Forever ne fournit pas.
Le masque à restaurer provient des appels natifs SetMaskTexture observés depuis
le chargement de l'addon. Aucun masque par défaut n'est imposé aux autres addons.
Après /reload, ouvrir /gl debug puis cliquer « Préparer la minimap ».
Ce bouton réapplique l'apparence native avec la rotation actuelle, sans modifier
les réglages sauvegardés ni un habillage personnalisé déjà observé. Aucun scan
ne démarre automatiquement ; la préparation est refusée en combat ou pendant un test.
Une fois prête : cibler un joueur immobile visible sur la minimap et cliquer
« Test druide ». Placer la souris sur une zone vide du monde dans les trois
secondes, puis rester immobile en félin avec le pistage des humanoïdes actif.
Vérifications : 20 suites, dont 90 cas du détecteur. La lecture réelle des joueurs
par le moteur du jeu reste à démontrer ; ceci corrige seulement la préparation.

Nouveautés 0.5.3 : gestes et historique lisible

Les boutons utilisent maintenant la cible sélectionnée, comme /kiss et /spit
sans argument, au lieu de transmettre le nom littéral « target ». Les demandes
refusées par l'API n'ajoutent plus d'avis via les boutons. Les deux factions
passent par les émotes natives ; aucune émote personnalisée n'est substituée.
ATTENTION : cela ne rétablit pas le texte ciblé de /spit, retiré par Blizzard.
Si Forever conserve cette restriction, le destinataire voit un crachat au sol.
L'addon ne peut ni forcer son texte ni confirmer ce que l'autre client reçoit.

L'historique distingue « Vous a tué », « Vous l'avez vaincu » et les participations
possibles. Date, lieu, avis et raisons personnelles restent visibles. Les preuves
techniques restent dans « Corriger le PvP » ; rien n'est supprimé de la sauvegarde.
Les nouveaux événements gardent aussi la sous-zone et la quête explicitement suivie
si elles sont lisibles. Une quête suivie n'est pas une preuve de l'activité réelle.
Les gestes sont des demandes, pas des accusés de réception. Les anciens événements
ne reçoivent aucun contexte inventé. Depuis 0.5.2, un /reload suffit à charger 0.5.3.

Vérifications : 20 suites Lua 5.1 et 27 vues simulées. La réception des émotes entre
factions nécessite encore une vérification par les joueurs sur le client réel.

Nouveauté 0.5.2 : essai du détecteur druide, sans survol manuel de minimap

Il s'agit d'un test de capacité, pas encore d'un radar continu. Rien ne démarre
au chargement, aucun pistage n'est changé et aucune rancune n'est modifiée.
Le précédent test de curseur virtuel a échoué sur le client 70888.
Cette nouvelle méthode déplace temporairement une minimap invisible sous la
souris immobile, via les API Lua du client. Elle ne déplace jamais la souris.

Pour le seul essai nécessitant le vrai client :
1. Redémarrer WoW une fois pour charger le nouveau fichier et son masque.
2. À l'abri, en extérieur, se mettre en félin et activer Pistage des humanoïdes.
3. Cibler un autre joueur immobile, dont le point est visible sur la minimap.
   Un ami convient ; choisir un joueur sous forme humanoïde.
4. Placer la souris sur le décor, hors fenêtres et minimap, puis taper
   /glradar test et rester immobile, sans clic, pendant au maximum 12 secondes.
   Le bouton « Test druide » dans Diagnostic laisse trois secondes pour replacer
   la souris. La minimap est masquée temporairement pendant le balayage.
5. Copier le résultat avec /glradar rapport, ou via /gl debug.
   /glradar stop interrompt l'essai ; bouger ou entrer en combat l'arrête aussi.

Un résultat positif exige deux lectures du nom témoin, séparées et encadrées
par des contrôles vides. Un nom de propriétaire de familier ne suffit pas.
Un résultat négatif ne prouve pas l'absence d'humanoïdes : mouvement du témoin,
grille de 225 positions et faible fréquence d'images peuvent limiter l'essai.
Les dix derniers résultats gardent le build, l'étape, le motif et les compteurs,
sans noms de joueurs ni infobulles. Les propriétés lisibles sont revérifiées après
restauration ; pour le masque sans getter, seul l'appel du setter est observable,
pas son rendu effectif par le moteur.
Si elle échoue, le test demande /reload et refuse un nouvel essai jusque-là.
Désactiver NodeSight pendant ce test : deux scanners ne doivent pas déplacer
la même minimap. Les autres contrôles de minimap ne sont pas forcés/désactivés.

Il reste à démontrer la lecture sur Forever avant d'envisager le radar continu,
ses alertes lointaines et l'option de pistage en félin. Aucun succès simulé ne
déverrouille ces fonctions. Aucune approbation spécifique de Blizzard n'a été
obtenue ; l'accès à une API ou l'existence d'un autre addon n'en constitue pas une.

Nouveauté 0.5.1 : une icône de bisou reconnaissable
Lèvres rouges peintes soufflant un cœur rose, générées avec l'outil d'images
d'OpenAI, dans le cadre natif de WoW. Redémarrer le jeu pour charger la nouvelle
texture. Le fonctionnement des gestes reste identique.

Nouveautés 0.5.0 : chroniques, guildes et diagnostic

- Statistiques dans le livre (/gl stats) : bourreaux, victoires, antagonistes par solde négatif, amis par score, amis et menaces recroisés. Morts/victoires probables ont leurs propres classements. Un clic ouvre la fiche.
- Guildes (/gl guildes) : nombre de rancunes personnelles et d'amis parmi les membres connus, morts confirmées/probables et agressions confirmées. Cliquer une guilde permet de la marquer à surveiller, amie, ou d'ouvrir ses avis et notes. Les choix personnels restent prioritaires. Les avis hérités d'une guilde ne créent pas artificiellement de rancunes personnelles dans le classement. Les faits sans guilde connue restent non attribués ; une ancienne guilde enregistrée au moment des faits conserve ces événements.
- Bisou / crachat : deux boutons avec les cadres natifs de WoW, au-dessus du chat, sous les alertes. Clic sur un joueur ciblé : /kiss (+1) ou /spit (−1), avec le même délai de 30 secondes par sentiment que les macros. Un geste positif n'efface pas une dette PvP. Ctrl + glisser déplace les deux boutons ; position mémorisée et bouton de remise en place dans les réglages. Aucun geste n'est envoyé automatiquement. Désactivables dans les réglages.
- Rencontres distinctes : compteur démarré à cette version, pour les joueurs déjà suivis ou couverts par un avis de guilde. Une nouvelle rencontre demande plus de dix minutes sans observation ; chaque présence renouvelle le délai. Le rechargement ne compte pas deux fois. Horloges séparées par personnage, statistiques réunies dans ce livre de compte. Ce n'est ni une mesure de distance ni du temps passé ensemble, et aucun ancien passage n'est inventé.
- Diagnostic local (/gl traces) : les 200 dernières décisions de détection/alerte, avec la raison (identité absente, délai, ami du groupe, alerte désactivée, affichée, etc.). Répétitions limitées à une fois par 30 secondes ; effaçable et désactivable. Les noms de ce journal local sont privés. /gl debug produit la version anonymisée pour un signalement. Les données sont dans WTF/SavedVariables, jamais dans le code distribué. WoW écrit la sauvegarde lors d'un /reload ou d'une déconnexion normale.
- Test minimap intégré (/glprobe test, /glprobe stop) : contrôle expérimental sur un point immobile avec référence au survol, relecture sans survol et contrôle vide anti-cache. Le résultat sans noms est sauvegardé avec le build du client et visible dans Diagnostic. Ce test manuel n'est pas la fonctionnalité finale : aucun radar automatique ni changement automatique de pistage n'est activé. Un résultat négatif sur un point resté immobile invalide cette méthode dans cet essai. Un résultat positif isolé ne suffit pas à valider un radar en mouvement.

La précédente extension temporaire GrudgeLedgerProbe doit être retirée ou désactivée : le test est désormais inclus dans Grudge Ledger. Redémarrer le jeu après l'installation de cette version pour charger les nouveaux fichiers.

Les tests Lua vérifient la logique simulée, y compris une API fonctionnelle, vide, protégée, indisponible ou un cache trompeur. Ils ne prouvent pas que le client réel donne accès aux points de la minimap : les essais dans Forever restent nécessaires. Une absence de trace ne prouve pas l'absence du joueur dans le monde.

UTILISATION
Clic droit sur le portrait d'un joueur ou son nom dans le chat, puis survoler
« Grudge Ledger » : les actions s'ouvrent dans un sous-menu natif du jeu.
Choisir Ami, Méfiance, Ennemi, Automatique, un avis +1/-1, une note ou sa fiche.
Les actions sur la guilde sont regroupées dans son sous-menu « Guilde ».
Le bouton livre de la minimap ouvre le journal. La recherche est facultative.
Le bouton livre se place sur le bord de la minimap, en tenant compte de sa
taille. Le faire glisser permet de choisir son emplacement ; clic droit ouvre
les réglages. Après cette mise à jour graphique, redémarrer le jeu pour charger
aussi les nouvelles textures des icônes.
La fiche réunit les notes, les groupes partagés, les agressions et les morts PvP.
« Corriger le PvP » permet d'annuler un événement attribué à tort. Ses effets
disparaissent des compteurs et du classement automatique ; il reste marqué
« annulé » dans l'historique. Les notes et les choix personnels sont conservés.

FILTRES, RACE ET CLASSE
Dans le journal, choisir une relation (Tous, Amis, Méfiance, Ennemis), puis une
faction (Toutes, Alliance, Horde, Inconnue). Les deux filtres et la recherche se
combinent ; le compteur indique le nombre de fiches correspondantes. Une faction
Neutre fournie par le jeu reste connue et apparaît dans Toutes.
Chaque ligne affiche la faction, la race et la classe. Les icônes natives de race
et de classe sont utilisées si le client les fournit ; sinon un point
d'interrogation reste accompagné du libellé connu. La fiche affiche les libellés
complets. La liste conserve huit personnes par page pour rester compacte.
Les informations viennent du jeu, sans déduire la faction ni interdire de
combinaisons race/classe. Une ancienne fiche sans race se complète lors d'une
prochaine observation. Une information cachée ou indisponible ne remplace pas
une ancienne valeur connue. Notes et classements restent conservés.

MARQUEURS ET ALERTES
Cœur vert : ami. Œil orange : méfiance/agression.
Cœur brisé rouge : ennemi/rancune forte, notamment après une mort PvP.
Médaillon gris : personne connue devenue neutre. Aucun popup ni son pour les
neutres ; les inconnus et les anciennes fiches de groupe seules ne sont pas marqués.
Un petit « ? » accompagne les marqueurs fondés uniquement sur une déduction
PvP. Une mort probable reste signalée comme telle, même si une agression était
confirmée. Le « ? » disparaît après correction ou confirmation pertinente.
Les icônes nécessitent les barres de noms du jeu. Le bouton des Réglages permet
d'activer le repérage (icônes + couleurs), hors combat, également avec /gl reperage.
Il active les barres des joueurs alliés, les barres ennemies et leur affichage
hors combat, puis les icônes et couleurs de Grudge Ledger. Il n'est pas exécuté
automatiquement au démarrage. Les simples noms flottants ne sont pas des barres
modifiables par l'addon. Portée et visibilité dépendent
du jeu : ce n'est pas un radar de toute la zone ni un détecteur de furtivité.
La coloration supplémentaire des noms est facultative, désactivée au départ.
Les alertes de proximité affichent le joueur et un souvenir, avec des sons
distincts. Les amis du groupe ou du raid ne déclenchent pas d'alerte.
Pour les autres amis : première rencontre, puis plus de dix minutes sans présence
observée avant une nouvelle alerte. Chaque recroisement repousse ce délai ; rester
ensemble ne relance jamais le popup. Le compteur est conservé après /reload et
séparé pour chacun de vos personnages. Une cible hors de portée ou une simple
présence distante dans le groupe ne compte pas comme une rencontre.
Les rancunes conservent un délai de trois minutes par défaut, les sons sont limités.
Elles apparaissent au-dessus du chat principal, avec une marge pour ses onglets
et les petits panneaux. Elles suivent sa position sans disparaître s'il est masqué.
Les membres d'une même guilde aperçus dans les six secondes sont regroupés
dans une alerte, avec leur nombre observé. Son clic ouvre la première fiche.
Les alertes individuelles et les agressions personnelles gardent la priorité.
Cliquer une alerte ouvre la fiche ; elle ne change jamais automatiquement la cible.

GUILDES ET HISTORIQUE PVP 0.4.6
La fiche conserve la dernière guilde connue. Une réponse vide, cachée ou en erreur
ne prouve pas un départ de guilde et n'efface plus cette information. Une nouvelle
guilde observée la remplace ; une guilde quittée peut donc rester indiquée comme
dernière guilde connue tant qu'aucune information fiable ne la remplace.
Les cibles, survols et barres de noms enrichissent les contacts existants, même
après la mort et hors combat. Un cache local de 256 observations maximum, valable
60 secondes, aide à retrouver la guilde d'un attaquant identifié par le récapitulatif.
Ce cache ne crée aucune fiche pour les simples passants et disparaît au rechargement.
Chaque nouvelle mort, victoire ou agression mémorise séparément la guilde, son
serveur et la date de son observation. L'historique indique quand il s'agit d'une
dernière information connue. Les événements anciens ou de guilde inconnue ne sont
jamais réattribués après coup, même si le joueur rejoint une autre guilde.
Les statistiques de guilde séparent les déductions des faits confirmés et excluent
les événements annulés. Une même mort identifiée ne compte qu'une fois par guilde,
même avec plusieurs attaquants ; une preuve confirmée prime sur les participations
probables. Plusieurs guildes peuvent participer à la même mort : leurs totaux ne
s'additionnent pas pour calculer vos morts. Sans identifiant commun, aucun regroupement
des anciens événements n'est deviné.
Les classements de guildes sont disponibles depuis la version 0.5.0.

FINITION DU LIVRE 0.4.5
Le journal utilise le contour transparent de son illustration : l'ancienne
ombre rectangulaire noire a été retirée. Les boutons sur le cuir portent une
écriture dorée, ceux sur le parchemin une encre brune, avec un trait discret.
Guildes, Réglages, fermeture et Ajouter une note partagent ces styles ; les
états de survol, clic, désactivation et sélection restent distincts.
Aucune texture nouvelle ni donnée personnelle modifiée. /reload suffit.

RETOUR AU CALCUL AUTOMATIQUE 0.4.4
L'ancien bouton personnel « Neutre » remettait le score à zéro et le verrouillait,
même avec une dette PvP encore négative. Il devient « Automatique » dans le
journal et le menu du joueur. /gl auto fait la même chose ; /gl neutre reste un
alias compatible. Ce choix recalcule le solde à partir des rencontres PvP et
des gestes enregistrés, sans effacer l'historique ni les notes.
Les anciennes fiches verrouillées par « Neutre » repassent automatiquement à ce
calcul au chargement. Exemple : une mort (-10), un geste négatif (-1) et deux
victoires (+2) redonnent -9, donc Méfiance orange, pas Neutre.
Un vrai zéro obtenu par un avis manuel +1/-1 reste un choix personnel ; les
classements Ami, Méfiance et Ennemi restent prioritaires. Les règles de guilde
restent distinctes. « Automatique » n'impose donc jamais une couleur neutre.

SOLDE DE RANCUNE 0.4.2
Le classement automatique utilise les événements actifs : mort -10, agression -1,
victoire +1. Les événements probables restent explicitement signalés ; une victoire
confirmée ne confirme pas une ancienne mort probable. Les gestes négatifs s'ajoutent
au solde. Exemple : une mort, un geste négatif et deux victoires donnent -9.
À -10 ou moins après une mort, le classement est Ennemi (rouge). De -9 à -1,
il reste Méfiance (orange), avec l'alerte de proximité. À 0, il devient Neutre.
Les gestes amicaux ne cachent pas une dette PvP encore négative. Les victoires
remboursent progressivement la dette sans créer d'amitié à elles seules.
Les classements Ami/Méfiance/Ennemi et avis manuels gardent leur priorité : ils ne sont pas effacés
par les victoires. Les notes et l'historique restent conservés. À la mise à jour,
les fiches automatiques sont recalculées à partir des compteurs et gestes existants.
Annuler un événement recalcule son effet ; /reload ne compte jamais deux fois.
La limite affichée de -100 ne supprime pas la dette réelle au-delà de ce seuil.

CAMARADERIE ET HISTORIQUE
Les gestes amicals que vous envoyez à un joueur ciblé (/kiss, /wink, /hug, /wave,
/thank, etc.) donnent +1. Les gestes négatifs (/rude, /insult, /taunt, etc.) donnent
-1. Les noms de commandes d'emote peuvent varier avec la langue du client.
Les gestes automatiques de même sens envers une personne sont limités à un
avis toutes les 30 secondes : alterner /kiss et /wink n'augmente pas ce rythme.
Les gestes positifs et négatifs ont des délais séparés. Les avis manuels +1/-1
restent immédiats et ne sont pas soumis à ce délai.
Seules vos demandes d'emotes sont observées : les emotes reçues ne modifient pas
votre journal. Cela enregistre votre intention, pas la réaction de l'autre joueur.
La camaraderie est bornée de -100 à +100 : positive = ami, 0 = neutre,
-1 à -9 = méfiance, -10 ou moins = ennemi. Les boutons directs changent le
classement immédiatement. Ami/Méfiance/Ennemi et les avis manuels restent prioritaires, même
après une emote. Les gestes seuls ne verrouillent pas le classement : un /spit
ne peut pas empêcher le passage en ennemi après un décès PvP. Les compteurs PvP
restent séparés de la camaraderie personnelle.

Forever peut masquer le journal de combat. Après un décès, l'addon consulte aussi
le récapitulatif natif de mort et attend au plus deux secondes s'il arrive en
retard. Les sources de dégâts accessibles sont enregistrées par GUID, même sans
avoir ciblé ces adversaires. Un coup fatal explicite est confirmé. Les autres
participants à l'attaque mortelle sont marqués ennemis avec une participation
PROBABLE, pas comme auteurs de plusieurs coups fatals. Chaque fiche compte une
participation maximum au même décès. Un PNJ identifié comme source fatale ne
transforme pas les agresseurs joueurs en tueurs.
Sans récapitulatif exploitable, les adversaires PvP en combat qui vous ciblaient
réellement juste avant le décès peuvent être enregistrés comme participants
probables, y compris à plusieurs. Une baisse de santé peut également produire
des agressions probables. Les simples passants sont exclus ; les situations
ambiguës ou les données indisponibles peuvent toujours empêcher une attribution.
Une agression n'est comptée qu'une fois par adversaire et par combat. Les preuves
restent consultables et corrigeables. Les anciens décès manqués ne sont pas
reconstitués automatiquement après une mise à jour.

GUILDES
Le menu du joueur et la fenêtre Guildes permettent de classer une guilde entière
et de conserver une note. Les règles sont liées au royaume et au nom exact.
Les membres héritent du marqueur et de l'alerte. Le nom de la guilde indique la
raison. Un avis individuel explicite peut faire exception à la règle de guilde.
Une appartenance devenue inconnue n'est pas devinée ; les changements connus
sont actualisés lors des rencontres. Aucune guilde n'est préclassée.

COMMANDES (FACULTATIVES, UTILISABLES DANS UNE MACRO)
/gl                         ouvre/ferme le journal
/gl + Merci pour le donjon   avis positif sur le joueur ciblé
/gl - Mauvaise attitude     avis négatif sur le joueur ciblé
/gl ami                     classe immédiatement la cible comme amie
/gl mefiance                classe la cible en orange
/gl ennemi                  classe la cible en rouge
/gl auto                    revient au solde automatique, sans effacer la dette
/gl neutre                  alias de /gl auto
/gl note Super donjon !     ajoute une note sur la cible
/gl note                    ouvre l'éditeur de note pour la cible
/gl guilde mefiance         classe la guilde du joueur ciblé
/gl settings                ouvre les réglages
/gl reperage                active barres de noms, icônes et couleurs, hors combat
/gl debug                   ouvre le diagnostic copiable (également dans Réglages)
/grudges                    alias de /gl

CODE ET DONNÉES SÉPARÉS
Le dossier Interface/AddOns/GrudgeLedger contient uniquement le programme.
L'archive de distribution est vierge : aucun joueur, aucune guilde, aucune note.
Chaque compte conserve son journal, commun à ses personnages, dans :
  WTF/Account/<compte>/SavedVariables/GrudgeLedger.lua
WoW peut également créer un fichier .bak. Aucun échange entre joueurs n'est fait.
Pour partager l'addon, partager son dossier ou son ZIP, jamais le dossier WTF.
Pour sauvegarder uniquement le journal, quitter normalement WoW puis copier
GrudgeLedger.lua (et éventuellement son .bak). Le programme reste séparé.
Une mise à jour du dossier de l'addon ne supprime pas ce journal.
Le diagnostic se copie avec Ctrl+C. Il contient les versions, les disponibilités
d'API, les réglages techniques autorisés et le nombre d'erreurs conservées.
Il n'inclut pas les noms, guildes, notes, GUID, historiques ou erreurs brutes.
Rien n'est envoyé automatiquement.

CHOIX DE POLICE 0.4.3
Dans Réglages (/gl settings), cocher « Police classique (plus lisible) » pour
utiliser l'écriture native du chat dans les titres, les noms et les notes du
journal. Décocher rétablit la calligraphie grimoire. Les tailles, couleurs des
relations, notes et brouillons sont conservés. Le choix s'applique immédiatement
et reste sauvegardé pour le compte. Les fenêtres ouvertes ensuite le respectent.
Le style grimoire reste le choix initial. Aucun fichier de police ajouté.
Après installation de cette mise à jour, /reload suffit ; les changements de
police suivants se font directement depuis les réglages.

ÉCRITURE DE GRIMOIRE 0.4.1
Les titres, noms dans l’index et fiches utilisent les familles calligraphiques
natives de WoW (Morpheus pour l’alphabet latin). La lecture et la saisie des notes
utilisent QuestFont_Large à 15 pixels. Les boutons, filtres et petites indications
gardent leur police compacte. Les variantes natives prennent en charge les autres
alphabets ; aucun fichier de police ni addon supplémentaire n’est nécessaire.
Un /reload suffit à appliquer ce changement.

LIVRE OUVERT ET LISIBILITÉ 0.4.0
Deux pages de parchemin vieilli, une couverture en cuir cousu et des ferrures
discrètes remplacent les grands aplats du journal. L’index affiche toujours
l’icône et le libellé de relation, en encre sombre, avec une sélection ocre.
Le classement et l’ajout de note restent en haut ; avis +1/-1, guilde et correction
PvP passent au pied de la page. Les notes commencent plus haut dans la fiche.
Une nouvelle texture originale est incluse. Si elle manque après /reload,
quitter puis relancer WoW ; aucun redémarrage de l’ordinateur nécessaire.
Les fonds unis de secours préservent la lisibilité même sans les images.
Aucune modification des données personnelles ni des règles de suivi.

LISIBILITÉ ET COMPAGNONS DE GROUPE 0.3.1
Les fonds ont des couches explicites. Un fond uni reste présent sous le parchemin,
même quand sa texture n'est pas disponible : l'encre sombre reste lisible.
L'index affiche une icône et un libellé Ami/Méfiance/Ennemi/Neutre par personne.
Rejoindre un groupe n'ajoute plus les inconnus au journal. Les groupes partagés
sont suivis pour les contacts déjà enregistrés ou reconnus par un avis de guilde.
Les anciennes fiches constituées uniquement de groupes sont masquées sans être
effacées ; une ouverture explicite reste possible. Les avis, notes et historiques
PvP restent visibles, y compris les avis neutres choisis et les faits annulés.
Un /reload charge le correctif. Si une texture manque encore, quitter puis
relancer WoW ; il n'est pas nécessaire de redémarrer l'ordinateur.

PRÉSENTATION DU JOURNAL 0.3.0
Le journal prend la forme d'un livre ancien : index sombre, fiche sur parchemin,
encre brune, reliure bordeaux et illustration originale d'un livre ouvert.
Le nom, le classement et l'identité précèdent les actions. Les notes personnelles
apparaissent en premier. Les boutons signalent le classement actif, les fenêtres
secondaires partagent le même cadre et l'éditeur de notes utilise le parchemin.
L'inspiration artistique vient d'Overlord ; ses illustrations ne sont pas copiées.
Deux nouvelles textures sont incluses : redémarrer WoW si elles ne se chargent
pas après /reload. Les données personnelles et les règles de suivi sont conservées.

SUIVI DES ATTAQUES MULTIPLES 0.2.7
Ajout du récapitulatif de mort public de Forever, avec contrôle de fraîcheur,
données secrètes ignorées et déduplication. Suppression du blocage de toutes les
attributions lorsqu'il y avait plusieurs attaquants. Reprise des plaques déjà
visibles et du suivi après un rechargement en combat. Les noms Given-Realm ne
sont plus interprétés comme prénom + patronyme. Un avis issu de /spit ne bloque
plus le classement automatique PvP ; les vrais choix manuels sont conservés.

MARQUEURS ET NOMS NATIFS 0.2.6
Correction de l'ancrage lorsque Threat Plates masque son propre texte et laisse
afficher le nom natif de WoW, notamment en mode nom uniquement. Un ami du groupe
garde son cœur ; seules ses alertes de proximité sont supprimées. Le diagnostic
affiche les réglages des plaques alliées/ennemies pour distinguer une absence
de plaque d'un problème de rendu. Si les icônes manquent, utiliser /gl reperage
hors combat : les noms flottants sans plaque ne peuvent pas porter de marqueur.

FILTRES ET IDENTITÉS 0.2.5
Filtres de faction cumulables avec les relations, compteur de sélection, race
et classe avec icônes natives. Les observations partielles et les fusions de
fiches conservent des libellés cohérents. Une sélection masquée par les filtres
cesse d’être active ; une fiche identifiée plus précisément reste sélectionnée.

RENCONTRES ET ICÔNES 0.2.4
Les alertes amicales suivent désormais le temps sans présence observée, au lieu
du temps écoulé depuis le dernier popup. Aucun rappel pour un ami dans le groupe
ou le raid. Les nouveaux symboles cœur vert, œil orange et cœur brisé rouge
remplacent le bouclier, l'avertissement et le crâne. Redémarrer WoW pour charger
les nouvelles textures.

REPÉRAGE DES JOUEURS ALLIÉS 0.2.3
Le bouton utilise désormais le réglage des joueurs alliés de Forever, au lieu
de l'ancien réglage général. L'activation regroupe barres de noms, icônes et
coloration, via les Réglages ou /gl reperage. Une activation refusée par le jeu
est signalée. Ennemi donne le rouge ; Méfiance ou un simple avis -1 donne l'orange.
Les commandes françaises accentuées conservent leurs caractères sous Windows.

PLACEMENT DES ALERTES 0.2.2
Les alertes de rencontre quittent le centre pour se placer en bas à gauche,
au-dessus du chat principal. Sans fenêtre de chat native, elles utilisent un
emplacement fixe en bas à gauche. Elles restent limitées aux bords de l'écran.

AJUSTEMENT 0.2.1
Dans la minimap, le livre est désormais une illustration sans cercle intégré,
de 17–18 pixels dans le bouton standard de 31 pixels. Le fond et la bordure
dorée proviennent de l'interface native de WoW, comme pour les autres addons.
Le médaillon décoratif reste dans les en-têtes du journal.

PRÉSENTATION 0.2.0
Médaillon circulaire au livre rouge, thème grimoire sombre avec accents bordeaux
et or, boutons et sélections harmonisés. Les fenêtres et les alertes bénéficient
d'espacements et d'une hiérarchie visuelle plus clairs. Le contenu des notes et
le fonctionnement des classements sont conservés.

CORRECTIFS 0.1.2
Le menu clic droit ne contient plus qu'une entrée Grudge Ledger, ouvrant les
actions au survol. Les actions de guilde ont leur propre sous-menu.

CORRECTIFS 0.1.1
Les événements de vol de ressource ne sont plus interprétés comme des coups
fatals. Une demande de duel ignorée ne bloque plus durablement le suivi après
son délai d'attente et la sortie de combat. Les combats de duel longs restent
exclus tant que le combat continue. Sans signal confirmant le duel, le client
ne permet pas toujours de distinguer une invitation ignorée d'un duel accepté.

VALIDATION
Les tests automatisés Lua 5.1 et les relectures croisées couvrent les menus,
identités, classements, sauvegardes, marqueurs, sons, emotes, groupes et PvP.
Ils n'exécutent pas le client WoW : le rendu et les API effectives de Forever
doivent aussi être vérifiés en jeu. Aucun contrôle du jeu n'a été automatisé.
Protocole conseillé : classer une cible amie puis automatique, ajouter une note,
tester une emote, classer une guilde avec une exception personnelle, recharger
puis vérifier la conservation. Tester ensuite le PvP en conditions contrôlées.

Licence et crédits : voir LICENSE et CREDITS.txt.
