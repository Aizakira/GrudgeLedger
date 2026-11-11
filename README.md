# Grudge Ledger

<img src="docs/red-book.png" alt="Grudge Ledger's red book" width="96" align="right">

**Remember the good encounters. Keep a little book of grudges for the rest.**

A small personal player journal for **World of Warcraft Forever**: friends, enemies, notes, guild opinions and PvP encounters, brought together in one addon.

[Français](README.fr.md) · [Download](https://github.com/Aizakira/GrudgeLedger/releases/latest) · [Report a bug or suggest an idea](https://github.com/Aizakira/GrudgeLedger/issues)

## Why this exists

This was put together quickly to solve a simple problem while playing: remembering who was great to group with, who attacked us, and why a familiar name rang a bell. It was **created with the help of ChatGPT, through Codex**, with several rounds of fixes and automated checks. The red book artwork was also generated with OpenAI's image tools.

It is a small hobby project, shared as it is, and it may evolve with playtesting, ideas and contributions. No grand roadmap or promised update schedule. If it is useful to you, take it, try it, fork it, improve it or adapt it to your own needs under the GPLv3 license.

## What it does

- **Right-click actions:** a compact “Grudge Ledger” submenu on supported player portraits and chat names. Mark a friend, caution or enemy, give a positive/negative opinion, add a note or open their record.
- **Visible reminders:** green friend shields, orange warnings and red enemy skulls on visible player nameplates; optional name coloring and tooltip notes.
- **PvP memory:** records observed aggression and deaths. Inferred events are explicitly marked as probable and can be corrected without erasing your personal notes.
- **Friendly and unfriendly gestures:** your own targeted emotes can adjust camaraderie, including toward the opposing faction. Repeated emotes are rate-limited.
- **Guild opinions:** mark an entire guild, with individual exceptions.
- **Nearby encounter alerts:** a small popup and distinct sounds when the client observes a remembered player, with cooldowns and grouped guild alerts.
- **A personal journal:** notes, encounters, shared groups and PvP history, accessed through the red book on the minimap or `/gl`.

## Install

1. Download **`GrudgeLedger-0.2.1.zip`** from [Releases](https://github.com/Aizakira/GrudgeLedger/releases/latest).
2. Extract the `GrudgeLedger` folder into your Forever client's `Interface/AddOns` folder. The final path must be `Interface/AddOns/GrudgeLedger/GrudgeLedger.toc`.
3. Restart WoW and enable Grudge Ledger in the addon list.

No other addon is required. Disable Grudgebook and Worth Remembering if they are installed for the same purpose, to avoid duplicate menus, markers and alerts. GitHub's automatic **Source code** archive contains developer files; only its inner `GrudgeLedger` folder belongs in `AddOns`.

Left-click the minimap book to open the journal, right-click it for settings, or drag it around the minimap. Right-click a player portrait or chat name to start adding people. Search and slash commands are optional. The in-game interface is currently primarily **French**.

| Command | Action |
| --- | --- |
| `/gl` | Open or close the journal |
| `/gl ami` / `/gl mefiance` / `/gl ennemi` | Mark your selected player as friend / caution / enemy |
| `/gl + Great dungeon!` | Add a positive opinion and note about the selected player |
| `/gl - Unpleasant encounter` | Add a negative opinion and note |
| `/gl note` | Open the note editor for your selected player |
| `/gl guilde mefiance` | Mark the selected player's guild as caution |
| `/gl settings` | Open settings |
| `/gl debug` | Open a diagnostic report you can copy yourself |

See the [full usage guide](GrudgeLedger/README.txt) for neutral status, priorities, corrections and data backup.

## Compatibility and limits

Targets **Forever interface 16001**; development used client **1.60.1.70862**. Retail, Classic and other private-server clients are not validated. Nameplate markers require visible nameplates and obey the client's range and visibility rules. This is not a whole-zone radar or a stealth detector.

Forever may hide combat-log information. Inference from observed units, health and honor is imperfect: probable events are separated from confirmed ones, ambiguous cases are skipped and the journal offers corrections. Your explicit classifications take precedence. Duel detection also depends on the available client signals.

The existing offline suite covers ten test scripts, including 45 PvP tracking scenarios. These tests simulate WoW APIs; they do not replace actual gameplay testing. This remains an early version, and bug reports are welcome.

## Your journal stays yours

Every new account starts with an **empty journal**. The addon contains no preset players, guilds or blacklists. Its account-wide database is saved by WoW in `WTF/Account/<account>/SavedVariables/GrudgeLedger.lua`, separately from the addon code. Sharing the addon folder or release ZIP does **not** share your notes. There is no automatic player-to-player database exchange or telemetry.

Never upload your `WTF` folder or SavedVariables when reporting an issue. The optional `/gl debug` report excludes player identities, guild names, notes and raw errors; you choose whether to copy and share it.

## Development and contributions

Python 3.11 and the pinned test dependency are only needed for development, not to play:

```sh
python -m pip install --target test-runtime -r requirements-test.txt
python tests/run_tests.py
```

GitHub Actions runs the same suite on Linux and Windows. See [DEVELOPMENT.txt](DEVELOPMENT.txt) for the optional offline UI renderer. To build an installable archive from the repository root:

```sh
python -m zipfile -c GrudgeLedger-0.2.1.zip GrudgeLedger
```

Issues and pull requests in French or English are welcome. For bugs, include the addon/client versions, steps to reproduce, expected and actual behavior, and a screenshot with personal information hidden if useful. Keep fixes focused and run the existing tests. Please do not submit anyone's personal journal.

## License and acknowledgments

**GNU GPL v3**, see [LICENSE](LICENSE). You may use, study, modify, fork and redistribute the project, including commercially, under that license. When distributing modified versions, preserve the notices, provide the corresponding source and keep them under GPLv3. This is not an unrestricted public-domain release; it is provided without warranty.

Menu integration and nameplate/tooltip lifecycle techniques are adapted from [Worth Remembering by Kyle (maliceftw)](https://github.com/kk-on-gh/WorthRemembering), under GPLv3. The independently implemented PvP module was informed by [Grudgebook](https://www.curseforge.com/wow/addons/grudgebook)'s described approach. Neither addon is bundled or required. See [full credits](GrudgeLedger/CREDITS.txt).

Original contributions, documentation and the included generated book artwork are shared under the same GPLv3 terms. Native WoW textures and sounds are referenced from the installed client, not redistributed. Unofficial project; not affiliated with Blizzard Entertainment or OpenAI.
