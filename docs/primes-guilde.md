# Moteur de primes de guilde (branche de préparation)

Historique du prototype 0.10.8. Pour les règles de groupe, le quota, les écrans et le courrier manuel de l’alpha, voir le [guide 0.11.0-alpha.1](alpha-fonctionnelle.fr.md). Le bouton au nom de la cible prépare le courrier ; seul le joueur l’envoie.

GrudgeLedger.Bounties expose les opérations suivantes, sans fenêtre, commande de jeu ni transfert automatique d’or. Les fonctions de modification renvoient un identifiant de déclaration ou nil avec le motif. Les sommes sont des entiers en cuivre.

| Appel | Fonction |
| --- | --- |
| List() | Vue des contrats de la guilde courante, indexée par identifiant. États open, claimed, fulfilled, paid, withdrawn et expired. |
| Post(guid, nom, cuivre) | Proposer un contrat sur un joueur identifié. Expiration à sept jours, dix contrats ouverts par auteur, mise initiale de 0 à 1 000 po. |
| Pledge(id, cuivre) | Ajouter à sa promesse, dans la limite de 1 000 po par contributeur et contrat. |
| Withdraw(id) | Retirer son contrat encore ouvert. |
| Due(contrat, payeurGUID, beneficiaireGUID) | Reste dû par ce payeur à ce bénéficiaire, en cuivre. |
| ConfirmPayment(id, beneficiaireGUID, cuivre) | Déclarer explicitement un règlement effectué. Accepte les versements partiels. La future interface appellera cette opération après confirmation du joueur. |
| ShareDeaths(true ou false) | Consentement par personnage et par guilde aux signalements de décès pour les avis automatiques. Désactivé initialement. |

Le suivi JcJ local envoie au module un coup fatal personnel explicite (ou du familier), et une mort attribuée à un auteur létal identifié. Une déduction issue du seul honneur ne clôt pas un contrat. Les clients distants n’écrivent pas dans le journal JcJ personnel. Trois décès en 30 minutes pour un membre ou trois victimes distinctes en deux heures déclenchent un contrat sans or de trois jours si le partage est actif. Les conditions s’appliquent aux informations connues du client victime.

La déclaration d’un coup fatal inclut au plus quatre partenaires visibles du groupe. Il s’agit de proximité, pas de preuve de dégâts. Le reste indivisible en cuivre revient à l’auteur du coup fatal. Si l’émetteur du contrat est déconnecté, la demande reste en attente de son arbitrage automatique à réception. La première demande retenue par son client fait foi. Les créances entre une personne et elle-même sont nulles.

Le protocole GLBounty1 utilise exclusivement le canal addon GUILD. Les déclarations sont conservées par guilde et royaume sous GrudgeLedgerDB.bountyGuilds. L’identifiant du personnage et son compteur local permettent de rejouer un message sans doubler les montants. Les pairs reliés échangent leur cache à la connexion. Les signalements de décès expirent après deux heures et les autres déclarations après 38 jours : le registre des dettes est temporaire. Le transport repose sur des membres de guilde de confiance ; les relais ne sont pas signés. Un membre sans addon ne reçoit pas le registre. Le paiement enregistré est déclaratif, distinct du solde du jeu. Aucun envoi de courrier ou mouvement d’or n’est initié.

Avant intégration, essayer sur Forever avec trois comptes : A poste, B contribue, A se déconnecte, C se connecte et retrouve le contrat via B. C tue la cible. A revient et arbitre. Vérifier la répartition jusque dans le dernier cuivre, puis tester un changement de guilde, une reconnexion en combat, deux auteurs de revendication concurrents et les noms avec royaume. Mesurer le temps de synchronisation dans une guilde chargée et les limites de débit du client. Une synchronisation parfaite pendant une partition réseau ou après perte de toutes les copies n’est pas garantie.

## Utilisation sans nouvelle interface

- � une bo�te aux lettres, un clic sur une macro contenant `/glprime courrier` remplit le prochain r�glement disponible (destinataire du registre de guilde, objet et montant exact restant). Pour s�lectionner une dette : `/glprime courrier <contrat> <GUID du b�n�ficiaire>`. Un brouillon d�j� entam�, une pi�ce jointe ou le mode contre remboursement bloque la pr�paration. V�rifier les frais de port et cliquer soi-m�me sur Envoyer.
- Seule la r�ussite signal�e par le jeu pour le brouillon pr�par� et envoy� au destinataire, � l�objet et au montant pr�vus enregistre le r�glement. Un cadeau, un �chec ou un brouillon modifi� ne r�gle pas automatiquement la dette. Apr�s un envoi r�el non reconnu (par exemple apr�s une d�connexion), v�rifier le paiement avant de refaire un courrier ; le payeur peut le consigner avec `/glprime regler <contrat> <GUID> <cuivre>`.
- `/glprime liste` donne les identifiants. L�auteur utilise `/glprime note <contrat> <texte>` pour modifier une consigne ou `/glprime renouveler <contrat> [texte]` pour renouveler un contrat encore ouvert. M�me identifiant, m�mes contributions, nouvelle �ch�ance � sept jours (trois pour un avis automatique), au plus 31 jours apr�s l�ouverture. Les clients doivent utiliser cette version pour lire les renouvellements.
- Une cible de contrat ouverte directement observ�e d�clenche une indication dans le chat si les alertes ennemies sont activ�es. D�lai de deux minutes par contrat ; aucune position n�est envoy�e � la guilde et le statut personnel de la cible ne change pas. Le registre de cibles est index� par GUID pour �viter de reparcourir l�historique � chaque apparition.
- Deux contrats sur la m�me cible d�j� connue sont refus�s ; deux joueurs s�par�s par une coupure r�seau peuvent encore publier chacun un contrat. Les mises de contrats concurrents restent distinctes.

Recette sur Forever : pr�parer une dette pr�cise, annuler, changer le destinataire, recommencer puis envoyer ; v�rifier l�or re�u et le solde sur un deuxi�me client. Contr�ler aussi une bo�te d�j� remplie et le cas d�un destinataire absent du registre. Le client doit fournir les contr�les natifs de courrier utilis�s ; � d�faut la commande refuse le remplissage.
