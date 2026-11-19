# Contribution and publication rules

- Keep changes on a branch and submit a pull request; never push directly to `main`.
- Read [CONTRIBUTING.md](CONTRIBUTING.md). Keep the GPLv3 license and personal-data separation.
- Review external code before executing it locally. Never run unreviewed contributor
  code with the owner's credentials or personal game files available.
- Do not approve, merge, install or release an external contribution without
  Aizakira's explicit authorization for the reviewed commit. A passing test run,
  an earlier approval invalidated by new commits, or access to the owner's GitHub
  credentials is not that authorization.
- Owner-authored work explicitly requested by Aizakira may use the owner's PR-only
  review exception after all required checks pass. Never weaken rules to merge it.
- Keep workflows read-only, with pinned actions and no automatic publication.
  Do not add secrets, privileged fork workflows, collaborators or bypass actors
  without explicit authorization.
- Official release publication is a separate decision; never publish a contributor's
  build or attachment as an official release without review and authorization.

# Structure rules

These rules keep the addon modular while it grows. `tests/structure_test.lua`
enforces them on every test run. When it fails, fix the code, never the check.
Today's exceptions are frozen in that test; a list may only shrink.

1. **Dependency direction.** `Core.lua` calls nothing defined in another addon
   file. It emits an event with `GL.Emit`; other modules subscribe with `GL.On`.
2. **One door to the network.** Only the transport file (`Bounties.lua` today)
   sends or receives addon messages. Other modules hand it a message.
3. **One answer for character data.** The value, source, provider and date of
   gear, talents, stats and identity are resolved in one place. No new file reads
   `record.inspection`, `armorySnapshot`, `GrudgeLedgerArmory` or a guild dossier.
4. **Readable code.** One statement per line, descriptive names, lines of at most
   160 characters, a comment on every chosen cap or delay. A file may not get worse.
5. **One reference document.** `docs/protocole-et-sauvegarde.fr.md` lists every
   saved key, guild field and message kind. Update it in the same change.
   Migrations are numbered, keep what they replace, and are tested on a synthetic
   journal from the previous version.

Extract a module when a fix needs it, not as a separate rewrite.

# Definition of done

- A small check fails if the defect returns.
- `python tests/run_tests.py` passes.
- Network change: a multi-client scenario covers a late joiner, the game's send
  rate and a refused send.
- Interface change: the offline view is regenerated and compared in French,
  English and Spanish.
- A short in-game recipe states the expected result. The owner runs it before the
  next feature starts. A simulated test is not an in-game validation.
- The report separates code facts, executed tests, owner observations and
  hypotheses.
