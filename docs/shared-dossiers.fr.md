# Récupération automatique des fiches partagées

Une fiche de guilde ou une prime active déclenche automatiquement une demande de données publiques aux membres connectés. Un client qui connaît l'équipement, les talents, les caractéristiques, l'identité, le niveau, le JcJ, les réputations ou les hauts faits JcJ répond avec les champs disponibles. Le destinataire n'a pas besoin du compagnon pour recevoir ces données en jeu. Le dossier ouvert est rafraîchi à la réception, et le cache reste enregistré par guilde et royaume.

La réception d'une fiche et la reconnexion demandent également son import d'Armurerie. Une observation directe essaie l'inspection native. Le compagnon existant reste le moyen de consulter le Web : les API de l'addon ne permettent pas de lancer cet outil ni d'effectuer des requêtes HTTP. WoW ne transmet ses nouvelles sauvegardes au compagnon qu'à la déconnexion ou au `/reload`, et relit son module au chargement suivant. Aucun redémarrage/rechargement n'est forcé pendant le jeu. Sans membre possédant les données, sans inspection autorisée et sans compagnon, les champs restent inconnus.

Les portraits en texture ne sont pas transmis. La race, le sexe et les références d'équipement permettent au client de reconstruire un mannequin ; ce n'est pas la garantie du visage exact. Les liens d'objet conservent les références de variantes disponibles ; les infobulles détaillées reposent sur les données natives du client. Les notes privées, tags personnels et historiques de combat ne sont pas copiés dans ce transfert.

Le JcJ affiche aussi le détail **V / D par membre**, à partir des résultats déjà partagés par le registre. D représente les morts de ce membre face à la cible. Le réglage existant de partage des résultats reste respecté. Ce sont des totaux attribués, pas une chronologie exhaustive ni une preuve de tous les combats de la cible. Les événements reçus ne changent pas le bilan personnel.

## Transport et limites

Le protocole `S1` passe par le canal addon de guilde existant, avec contrôle de l'expéditeur dans le registre de guilde. Il échange des données à schéma limité, jamais du code Lua. Les morceaux sont réassemblés avant application : un transfert incomplet conserve le dernier relevé exploitable. Les demandes sont réessayées toutes les cinq minutes ; les champs manquants peuvent être complétés sans effacer les champs déjà connus. Les observations plus récentes ont priorité. Les valeurs restent des données rapportées par un membre de confiance, pas des preuves signées par Blizzard.

Les plafonds sont de 256 dossiers par guilde, huit transferts entrants simultanés, 46 080 octets encodés par transfert et 512 messages en attente. Le transport existant envoie deux messages par seconde. Les groupes importants ou une connexion perdue peuvent donc retarder le chargement ; la reprise périodique réessaie les demandes. Un membre peut relayer les relevés qu'il a déjà reçus pour une cible connue, même si leur premier fournisseur est absent. La diffusion des éditions de fiches suit toujours les règles du module Fiches de guilde.

Les deux clients doivent avoir cette version pour échanger les relevés. Les anciennes versions continuent à recevoir les primes et les avis mais ignorent les nouveaux messages.

Si un relevé dépasse la taille maximale, les sections sont priorisées : identité, équipement, talents, caractéristiques et JcJ avant les longues listes annexes. Une section trop volumineuse est omise sans bloquer les autres ; elle peut encore être obtenue localement par le compagnon. Les détails d'objets sont reconstruits à partir de leurs références natives, pas par copie de toutes les infobulles du fournisseur.

## Recette sur Forever

1. A possède un relevé et partage une fiche ou crée une prime. B n'a ni contact personnel ni compagnon. Vérifier chez B l'équipement, les talents et le libellé du fournisseur, sans ajouter la cible au journal.
2. Faire la même vérification sur une ancienne fiche après reconnexion. Couper la connexion pendant un transfert, puis vérifier que le relevé précédent reste visible et que la prochaine demande complète la fiche.
3. Observer une cible inspectable avec une fiche incomplète. Contrôler les données réellement fournies par le client et leur mise à jour. Les refus d'inspection doivent laisser les valeurs inconnues.
4. Avec le partage des résultats activé chez deux membres, contrôler les lignes V / D de chacun, puis le bilan personnel, qui doit rester inchangé chez le destinataire.
5. Masquer une fiche, changer de guilde, retirer ou terminer une prime sans fiche associée : les relevés de la guilde précédente ne doivent plus être utilisés.

Les tests automatisés utilisent plusieurs clients simulés avec le vrai TOC et le vrai transport, des doublons, des pertes de morceaux, la reconnexion, le relais, des entrées malformées et des données partielles. Ils ne remplacent pas cette recette dans le client.
