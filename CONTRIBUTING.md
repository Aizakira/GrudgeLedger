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
