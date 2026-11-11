GRUDGE LEDGER — 0.4.1
Journal des amis et des rancunes pour WoW Forever (interface 16001).

INSTALLATION
Copier le dossier GrudgeLedger dans Interface/AddOns, puis redémarrer le jeu.
Utiliser Grudge Ledger seul pour cette fonction : désactiver Grudgebook et Worth
Remembering pour éviter plusieurs menus et marqueurs concurrents.
Aucune dépendance à ces deux addons n'est nécessaire.

UTILISATION
Clic droit sur le portrait d'un joueur ou son nom dans le chat, puis survoler
« Grudge Ledger » : les actions s'ouvrent dans un sous-menu natif du jeu.
Choisir Ami, Méfiance, Ennemi, Neutre, un avis +1/-1, une note ou sa fiche.
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
classement immédiatement. Les boutons et avis manuels restent prioritaires, même
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
/gl neutre                  retire son marquage personnel sans perdre l'historique
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
Protocole conseillé : classer une cible amie puis neutre, ajouter une note,
tester une emote, classer une guilde avec une exception personnelle, recharger
puis vérifier la conservation. Tester ensuite le PvP en conditions contrôlées.

Licence et crédits : voir LICENSE et CREDITS.txt.
