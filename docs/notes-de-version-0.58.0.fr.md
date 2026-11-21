# Grudge Ledger 0.58.0 : notes de version

Version de test pour la guilde. Elle regroupe tout le travail depuis la 0.32.0.

## À lire avant d'installer

- **Toute la guilde doit passer en 0.58.0.** Les échanges de guilde ont changé : un membre resté sur une ancienne version ne reçoit pas tout. L'onglet Guilde affiche « Versions à jour », et la discussion prévient quand un membre a une version ancienne.
- **Le partage avec la guilde est activé d'office** : vos victoires et vos morts (avec l'endroit et l'adversaire), vos repérages et vos avis. Un message le rappelle à la première connexion dans chaque guilde. Pour arrêter : options, pages Relations et Alertes, et la case « Vision de guilde ». Vos notes ne sont jamais partagées.
- **Un carnet par faction.** Sur un royaume JcJ rien ne change. Sur un royaume JcE, vos personnages Horde et Alliance ont chacun leur carnet. Un ancien carnet tenu par les deux factions est séparé une fois, sans rien effacer.
- Redémarrez le jeu après l'installation (de nouveaux fichiers sont arrivés).

## Ce qui change

**En haut : Journal, Relations, Guilde, Primes.**

- **Journal** : listes rapides en un clic, un seul panneau de filtres, plus de lignes et plus parlantes.
- **Fiche d'un joueur** : ce que le jeu laisse lire d'un ennemi (classe, race, faction, niveau), « Comment il vous a tué », son modèle 3D gardé pendant la session après l'avoir croisé, ses coups de main.
- **Relations** : le **Bilan**, votre carte de joueur en neuf cartes à tourner (qui vous êtes, vos chiffres, vos trois personnes, votre territoire, les classes et races qui vous tuent, qui frappe le premier, votre honneur, votre guilde), à copier dans la discussion. Puis le registre des **Dettes** (une vie pour une vie), les **Rivalités**, la **Carte** des combats (du monde à la zone, les zones meurtrières en rouge, vos morts et victoires à leur place) et les **Classements**.
- **Guilde** (nouveau) : le **Journal de guilde** (qui a tué qui, où, quand, avec les filtres du Journal), les **Ennemis de la guilde** (les joueurs qui tuent vos compagnons), les **Guildes**, la case « Vision de guilde » et les chiffres de la semaine.
- **Alertes** : « **Tueur de guilde** » (orange, son à elle) quand vous croisez un joueur qui a tué un membre, avec un bouton « Rechercher ». « **Recherché** » (dorée, son de pièces) quand vous croisez un joueur mis à prix.
- **Primes** : refaites. Les primes en lignes, les filtres du Journal, un contrat lisible, et la création commence par « **Avis de recherche · gratuit** » ou « Prime en or ».

## À tester en guilde

1. Ouvrir l'onglet Guilde : « Versions à jour » doit compter tout le monde.
2. Mourir contre un joueur ennemi, puis regarder le Journal de guilde d'un autre membre : la mort doit y être, avec la zone.
3. Croiser ce même joueur avec un autre membre : l'alerte « Tueur de guilde » doit sonner.
4. Cliquer « Rechercher » sur l'alerte : l'avis doit apparaître dans l'onglet Primes de toute la guilde.
5. Croiser à nouveau le joueur : l'alerte « Recherché » doit sonner (son de pièces).
6. Créer une prime en or, y contribuer avec un autre membre, la remporter : le règlement doit suivre dans l'Historique.
7. Ouvrir Relations, Bilan : tourner les neuf cartes et essayer « Copier ».
8. Ouvrir la Carte des combats : zoomer du monde jusqu'à une zone, les zones où vous mourez sont rouges.
9. Un membre qui se connecte doit retrouver les combats partagés pendant son absence.
10. Décocher « Vision de guilde » : vos combats doivent disparaître chez les autres.

## Signaler un problème

Tapez `/gl debug`, faites une capture de ce qui s'affiche et de l'écran concerné, et envoyez-la au créateur de l'addon, ou ouvrez un ticket sur GitHub.
