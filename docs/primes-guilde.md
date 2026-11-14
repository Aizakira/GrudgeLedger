# Moteur de primes de guilde (branche de prÃ©paration)

GrudgeLedger.Bounties expose les opÃ©rations suivantes, sans fenÃªtre, commande de jeu ni transfert automatique dâ€™or. Les fonctions de modification renvoient un identifiant de dÃ©claration ou nil avec le motif. Les sommes sont des entiers en cuivre.

| Appel | Fonction |
| --- | --- |
| List() | Vue des contrats de la guilde courante, indexÃ©e par identifiant. Ã‰tats open, claimed, fulfilled, paid, withdrawn et expired. |
| Post(guid, nom, cuivre) | Proposer un contrat sur un joueur identifiÃ©. Expiration Ã  sept jours, dix contrats ouverts par auteur, mise initiale de 0 Ã  1 000 po. |
| Pledge(id, cuivre) | Ajouter Ã  sa promesse, dans la limite de 1 000 po par contributeur et contrat. |
| Withdraw(id) | Retirer son contrat encore ouvert. |
| Due(contrat, payeurGUID, beneficiaireGUID) | Reste dÃ» par ce payeur Ã  ce bÃ©nÃ©ficiaire, en cuivre. |
| ConfirmPayment(id, beneficiaireGUID, cuivre) | DÃ©clarer explicitement un rÃ¨glement effectuÃ©. Accepte les versements partiels. La future interface appellera cette opÃ©ration aprÃ¨s confirmation du joueur. |
| ShareDeaths(true ou false) | Consentement par personnage et par guilde aux signalements de dÃ©cÃ¨s pour les avis automatiques. DÃ©sactivÃ© initialement. |

Le suivi JcJ local envoie au module un coup fatal personnel explicite (ou du familier), et une mort attribuÃ©e Ã  un auteur lÃ©tal identifiÃ©. Une dÃ©duction issue du seul honneur ne clÃ´t pas un contrat. Les clients distants nâ€™Ã©crivent pas dans le journal JcJ personnel. Trois dÃ©cÃ¨s en 30 minutes pour un membre ou trois victimes distinctes en deux heures dÃ©clenchent un contrat sans or de trois jours si le partage est actif. Les conditions sâ€™appliquent aux informations connues du client victime.

La dÃ©claration dâ€™un coup fatal inclut au plus quatre partenaires visibles du groupe. Il sâ€™agit de proximitÃ©, pas de preuve de dÃ©gÃ¢ts. Le reste indivisible en cuivre revient Ã  lâ€™auteur du coup fatal. Si lâ€™Ã©metteur du contrat est dÃ©connectÃ©, la demande reste en attente de son arbitrage automatique Ã  rÃ©ception. La premiÃ¨re demande retenue par son client fait foi. Les crÃ©ances entre une personne et elle-mÃªme sont nulles.

Le protocole GLBounty1 utilise exclusivement le canal addon GUILD. Les dÃ©clarations sont conservÃ©es par guilde et royaume sous GrudgeLedgerDB.bountyGuilds. Lâ€™identifiant du personnage et son compteur local permettent de rejouer un message sans doubler les montants. Les pairs reliÃ©s Ã©changent leur cache Ã  la connexion. Les signalements de dÃ©cÃ¨s expirent aprÃ¨s deux heures et les autres dÃ©clarations aprÃ¨s 38 jours : le registre des dettes est temporaire. Le transport repose sur des membres de guilde de confiance ; les relais ne sont pas signÃ©s. Un membre sans addon ne reÃ§oit pas le registre. Le paiement enregistrÃ© est dÃ©claratif, distinct du solde du jeu. Aucun envoi de courrier ou mouvement dâ€™or nâ€™est initiÃ©.

Avant intÃ©gration, essayer sur Forever avec trois comptes : A poste, B contribue, A se dÃ©connecte, C se connecte et retrouve le contrat via B. C tue la cible. A revient et arbitre. VÃ©rifier la rÃ©partition jusque dans le dernier cuivre, puis tester un changement de guilde, une reconnexion en combat, deux auteurs de revendication concurrents et les noms avec royaume. Mesurer le temps de synchronisation dans une guilde chargÃ©e et les limites de dÃ©bit du client. Une synchronisation parfaite pendant une partition rÃ©seau ou aprÃ¨s perte de toutes les copies nâ€™est pas garantie.

## Utilisation sans nouvelle interface

- À une boîte aux lettres, un clic sur une macro contenant `/glprime courrier` remplit le prochain règlement disponible (destinataire du registre de guilde, objet et montant exact restant). Pour sélectionner une dette : `/glprime courrier <contrat> <GUID du bénéficiaire>`. Un brouillon déjà entamé, une pièce jointe ou le mode contre remboursement bloque la préparation. Vérifier les frais de port et cliquer soi-même sur Envoyer.
- Seule la réussite signalée par le jeu pour le brouillon préparé et envoyé au destinataire, à l’objet et au montant prévus enregistre le règlement. Un cadeau, un échec ou un brouillon modifié ne règle pas automatiquement la dette. Après un envoi réel non reconnu (par exemple après une déconnexion), vérifier le paiement avant de refaire un courrier ; le payeur peut le consigner avec `/glprime regler <contrat> <GUID> <cuivre>`.
- `/glprime liste` donne les identifiants. L’auteur utilise `/glprime note <contrat> <texte>` pour modifier une consigne ou `/glprime renouveler <contrat> [texte]` pour renouveler un contrat encore ouvert. Même identifiant, mêmes contributions, nouvelle échéance à sept jours (trois pour un avis automatique), au plus 31 jours après l’ouverture. Les clients doivent utiliser cette version pour lire les renouvellements.
- Une cible de contrat ouverte directement observée déclenche une indication dans le chat si les alertes ennemies sont activées. Délai de deux minutes par contrat ; aucune position n’est envoyée à la guilde et le statut personnel de la cible ne change pas. Le registre de cibles est indexé par GUID pour éviter de reparcourir l’historique à chaque apparition.
- Deux contrats sur la même cible déjà connue sont refusés ; deux joueurs séparés par une coupure réseau peuvent encore publier chacun un contrat. Les mises de contrats concurrents restent distinctes.

Recette sur Forever : préparer une dette précise, annuler, changer le destinataire, recommencer puis envoyer ; vérifier l’or reçu et le solde sur un deuxième client. Contrôler aussi une boîte déjà remplie et le cas d’un destinataire absent du registre. Le client doit fournir les contrôles natifs de courrier utilisés ; à défaut la commande refuse le remplissage.
