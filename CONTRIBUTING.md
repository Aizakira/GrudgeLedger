# Contribuer / Contributing

Le code reste public sous GPLv3. Vous pouvez le lire, le copier, le modifier et
redistribuer vos propres versions dans les conditions de cette licence.
Vos forks sont indépendants de l'addon officiel.

Pour proposer une modification à ce dépôt :

1. Créez un fork et une branche pour votre changement.
2. Décrivez le problème, le résultat attendu et les vérifications effectuées.
3. Ouvrez une pull request vers `main`. Les corrections, traductions,
   améliorations graphiques et documentaires sont bienvenues.
4. Attendez la revue de **@Aizakira**, propriétaire du dépôt et responsable de
   tous les fichiers. Chaque nouveau changement rend les anciennes approbations
   caduques : la version finale doit être relue.

Les tests Linux et Windows doivent réussir sur une branche à jour avant
l'intégration. Ils ne remplacent pas une revue humaine et ne garantissent pas
l'absence de code malveillant. Les contributions externes demandent aussi une
autorisation avant l'exécution de leurs workflows : cela autorise les tests,
pas l'intégration ni la publication.

Ne joignez jamais de journal personnel, de dossier `WTF` ou `SavedVariables`, de
jeton ou de mot de passe. Signalez les nouvelles dépendances, binaires, scripts,
accès réseau et modifications de workflows afin qu'ils puissent être examinés.
Suivez les commandes de test du [README](README.fr.md) et gardez les changements ciblés.

La fusion et la publication des versions officielles restent des décisions du
propriétaire. Il n'y a ni fusion ni publication automatique. Les contributeurs
utilisent des forks, sans obtenir d'accès en écriture à ce dépôt : sur un dépôt
personnel GitHub, cet accès permettrait aussi de gérer des releases.

GitHub ne permet pas d'approuver sa propre pull request. Le propriétaire dispose
donc d'une exception de revue **uniquement via une pull request**, pour intégrer
son propre travail autorisé. Cette exception ne permet ni de pousser directement
sur `main`, ni de contourner les tests obligatoires, ni de réécrire son historique.
Les outils automatisés ne doivent pas employer cette exception pour intégrer une
contribution externe sans son accord explicite.

Les règles actives sont consultables dans [Repository rules](https://github.com/Aizakira/GrudgeLedger/rules).

## Règles de structure

Six règles gardent l'addon modulaire pendant qu'il grandit. Le contrôle
`tests/structure_test.lua` les vérifie à chaque lancement des tests ; s'il échoue,
on corrige le code, pas le contrôle. Le texte de référence est dans
[AGENTS.md](AGENTS.md).

1. **Sens des dépendances.** Le cœur (`Core.lua`) n'appelle aucun autre fichier.
   Il émet un événement ; les autres modules s'y abonnent.
2. **Une seule porte vers le réseau.** Un seul fichier envoie et reçoit les
   messages de guilde.
3. **Une seule réponse pour les données d'un personnage.** Valeur, source,
   fournisseur et date se décident à un seul endroit.
4. **Code lisible.** Une instruction par ligne, des noms explicites, des lignes
   de 160 caractères au plus.
5. **Un seul document de référence.** Toute donnée sauvegardée et tout message de
   guilde figurent dans [docs/protocole-et-sauvegarde.fr.md](docs/protocole-et-sauvegarde.fr.md).

6. **L'addon seul.** Chaque fonction dit, dès sa proposition, si elle marche avec
   l'addon seul. Ce qui demande un programme extérieur au jeu (archive Armurerie,
   photos du studio) est facultatif : ce n'est jamais le seul moyen de remplir une
   page. `tests/addon_alone_test.lua` et les vues hors jeu `dossier-fresh` et
   `dossier-read` montrent la fiche sans rien d'extérieur. Ce que le jeu laisse
   lire à un addon se mesure en jeu (`/gl sonde`) avant de construire dessus.

Les écarts d'aujourd'hui sont figés dans le contrôle : leur liste peut seulement
raccourcir. Un module s'extrait quand une correction en a besoin, pas dans un
chantier séparé.

Un changement est terminé quand un petit test échoue si le défaut revient, que
tous les tests passent, et qu'une recette courte en jeu a été faite par le
propriétaire. Un changement réseau demande en plus un scénario à plusieurs
clients. Un test simulé ne vaut pas une validation en jeu.

## Versions

Utiliser une seule branche de référence, `main`, et un dossier installable, `GrudgeLedger/`. Incrémenter le numéro majeur.mineur.correctif dans le TOC à chaque diffusion. Le tag Git est `v<version>`. Le canal Alpha se règle sur GitHub (préversion) et CurseForge (Alpha). Après validation du commit, `python tools/package_addon.py` produit le ZIP commun aux deux plateformes à partir des fichiers suivis.

## English

Forks, issues and pull requests in French or English are welcome. The code remains
GPLv3; independent forks do not become official releases. Submit focused changes
with an explanation and relevant tests. Do not include private journals, account
data or credentials; disclose new dependencies, binaries and workflow changes.

**@Aizakira reviews all files.** External contributions need owner approval,
resolved review conversations and passing Linux/Windows checks on an up-to-date
branch. New commits dismiss prior approvals. External fork workflows need manual
permission to run; allowing tests is not permission to merge or release.

Only the owner currently has write access. Official merges and releases are
manual. A PR-only owner exception exists because GitHub forbids self-approval;
mandatory tests and main-branch history protection have no bypass. Automated
tools must not use the owner's credentials to approve, merge or publish external
contributions without explicit authorization for the reviewed revision.
