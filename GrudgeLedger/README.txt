GRUDGE LEDGER — 0.2.2
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
aussi la nouvelle texture du livre.
La fiche réunit les notes, les groupes partagés, les agressions et les morts PvP.
« Corriger le PvP » permet d'annuler un événement attribué à tort. Ses effets
disparaissent des compteurs et du classement automatique ; il reste marqué
« annulé » dans l'historique. Les notes et les choix personnels sont conservés.

MARQUEURS ET ALERTES
Vert avec un bouclier : ami. Orange avec un avertissement : méfiance/agression.
Rouge avec un crâne : ennemi/rancune forte, notamment après une mort PvP.
Un petit « ? » accompagne les marqueurs fondés uniquement sur une déduction
PvP. Une mort probable reste signalée comme telle, même si une agression était
confirmée. Le « ? » disparaît après correction ou confirmation pertinente.
Les icônes nécessitent les barres de noms du jeu. Le bouton des Réglages permet
d'activer les noms alliés et ennemis, hors combat. Portée et visibilité dépendent
du jeu : ce n'est pas un radar de toute la zone ni un détecteur de furtivité.
La coloration supplémentaire des noms est facultative, désactivée au départ.
Les alertes de proximité affichent le joueur et un souvenir, avec des sons
distincts. Les répétitions sont espacées et les sons limités pour éviter le bruit.
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
classement immédiatement. Votre classement explicite reste prioritaire sur les
déductions automatiques ; les nouveaux combats restent néanmoins dans l'historique.

Forever peut masquer le journal de combat. Les déductions à partir des unités,
des pertes de vie et de l'honneur sont indiquées PROBABLES et séparées des faits
confirmés. Une cible proche ou un gain d'honneur seuls ne suffisent pas à attribuer
une agression ou un coup fatal. Les cas ambigus sont laissés sans attribution.
Une agression n'est comptée qu'une fois par adversaire et par combat.

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
