# Grudge Ledger

<img src="docs/red-book.png" alt="Grudge Ledger's red book" width="96" align="right">

**Remember the good encounters. Keep a little book of grudges for the rest.**

A small personal player journal for **World of Warcraft Forever**: friends, enemies, notes, guild opinions and PvP encounters, brought together in one addon.

[Français](README.fr.md) · [Download](https://github.com/Aizakira/GrudgeLedger/releases/latest) · [Report a bug or suggest an idea](https://github.com/Aizakira/GrudgeLedger/issues)

## Why this exists

This was put together quickly to solve a simple problem while playing: remembering who was great to group with, who attacked us, and why a familiar name rang a bell. It was **created with the help of ChatGPT, through Codex**, with several rounds of fixes and automated checks. The red book and relationship icons were also generated with OpenAI's image tools.

It is a small hobby project, shared as it is, and it may evolve with playtesting, ideas and contributions. No grand roadmap or promised update schedule. If it is useful to you, take it, try it, fork it, improve it or adapt it to your own needs under the GPLv3 license.

## What it does

- **Right-click actions:** a compact “Grudge Ledger” submenu on supported player portraits and chat names. Mark a friend, caution or enemy, give a positive/negative opinion, add a note or open their record.
- **Visible reminders:** green hearts for friends, orange watchful eyes for caution and red broken hearts for enemies on visible player nameplates; optional name coloring and tooltip notes.
- **Faction filters and character details:** combine friends/caution/enemies with Alliance or Horde, with a count of the matching people. Race and class appear under each name and in the selected record, with native icons when available. Unknown factions have their own filter; older records fill in on the next observed encounter. Race never determines faction.
- **PvP memory:** records observed aggression and deaths. Inferred events are explicitly marked as probable and can be corrected without erasing your personal notes.
- **Friendly and unfriendly gestures:** your own targeted emotes can adjust camaraderie, including toward the opposing faction. Repeated emotes are rate-limited.
- **Guild opinions:** mark an entire guild, with individual exceptions.
- **Nearby encounter alerts:** a small popup above the main chat in the lower-left area, with distinct sounds, cooldowns and grouped guild alerts. It follows the chat's position, leaving room above its tabs. Friends in your party or raid never trigger these alerts. Other friends alert on first sighting, then only after more than ten minutes without an observed presence; every sighting renews this window, including across UI reloads. Encounter clocks are separate for each of your characters.
- **No automatic roster clutter:** joining a group does not add unknown players. Group history is kept for existing contacts; legacy entries containing only group sessions are hidden without deleting them. Opinions, notes and PvP records remain visible.
- **A personal journal:** notes, encounters, shared groups and PvP history, accessed through the red book on the minimap or `/gl`.

![Offline preview of the ancient-book journal, with synthetic example records](docs/journal.png)

The journal is an open, aged book with two parchment pages, stitched red leather, layered page edges and restrained brass corners. The index keeps a relationship icon, explicit label and dark readable ink. Classification and note-taking stay at the top; less frequent actions sit at the foot of the page. Its visual direction was inspired by Overlord, using original artwork. This preview is rendered from the actual Lua layout outside WoW, with synthetic records and approximated native fonts/icons.

Titles, names and journal text use WoW’s native calligraphic font families (Morpheus for the Latin alphabet). Notes use a 15-pixel reading/editing font; compact controls and small labels retain their regular font.

In **Settings** (`/gl settings`), enable **“Police classique (plus lisible)”** to use the native chat font at the same sizes instead of calligraphy. Disable it to restore the grimoire style. Titles, names and notes update immediately, drafts are preserved, and the choice is saved. Compact buttons keep their regular font.

## Grudge balance

Automatic records count **−10 per death, −1 per aggression and +1 per victory**. Negative gestures add to that balance: one death, one negative gesture and two victories leave **−9**, still **caution (orange)** with nearby alerts. Victories alone never create friendship; friendly gestures do not hide outstanding negative PvP debt. Explicit classifications and manual opinions stay authoritative. Existing automatic records are recalculated without deleting notes, counters or history.

A **gray medallion** marks known neutral people in the journal and on their visible nameplates. Neutral contacts do not trigger popups or sounds; unknown players remain unmarked.

## Install

1. Download **`GrudgeLedger-0.4.3.zip`** from [Releases](https://github.com/Aizakira/GrudgeLedger/releases/latest).
2. Extract the `GrudgeLedger` folder into your Forever client's `Interface/AddOns` folder. The final path must be `Interface/AddOns/GrudgeLedger/GrudgeLedger.toc`.
3. Restart WoW and enable Grudge Ledger in the addon list.

No other addon is required. Disable Grudgebook and Worth Remembering if they are installed for the same purpose, to avoid duplicate menus, markers and alerts. GitHub's automatic **Source code** archive contains developer files; only its inner `GrudgeLedger` folder belongs in `AddOns`.

Left-click the minimap book to open the journal, right-click it for settings, or drag it around the minimap. Right-click a player portrait or chat name to start adding people. Search and slash commands are optional. The in-game interface is currently primarily **French**.

For visible icons and colors, click **“Activer le repérage (icônes + couleurs)”** in settings, or run `/gl reperage` outside combat. This enables Forever's friendly-player nameplates, enemy nameplates and out-of-combat display, along with the addon's markers and name coloring. Plain floating world names are not editable nameplate labels. A friend in your party keeps their heart; only the nearby popup is suppressed. If the tooltip says Friend but the heart is missing, enable recognition outside combat. Native name-only nameplates are supported, including when Threat Plates hides its own name text. A player classified as **Ennemi** is red; **Méfiance** or a single negative opinion is orange.

| Command | Action |
| --- | --- |
| `/gl` | Open or close the journal |
| `/gl ami` / `/gl mefiance` / `/gl ennemi` | Mark your selected player as friend / caution / enemy |
| `/gl + Great dungeon!` | Add a positive opinion and note about the selected player |
| `/gl - Unpleasant encounter` | Add a negative opinion and note |
| `/gl note` | Open the note editor for your selected player |
| `/gl guilde mefiance` | Mark the selected player's guild as caution |
| `/gl settings` | Open settings |
| `/gl reperage` | Enable nameplates, markers and colors outside combat |
| `/gl debug` | Open a diagnostic report you can copy yourself |

See the [full usage guide](GrudgeLedger/README.txt) for neutral status, priorities, corrections and data backup.

## Compatibility and limits

Targets **Forever interface 16001**; development used client **1.60.1.70862**. Retail, Classic and other private-server clients are not validated. Nameplate markers require visible nameplates and obey the client's range and visibility rules. This is not a whole-zone radar or a stealth detector.

Forever may hide combat-log information. The addon also reads its public death recap, waiting up to two seconds for delayed data. Multiple attackers are recorded by GUID: an explicit lethal hit is confirmed, while other participants in the fatal attack remain probable. Without usable direct evidence, recent hostile PvP combatants actually targeting you may be recorded as probable participants; bystanders are excluded. Counters belong to each person's record: three participants in one death do not mean three player deaths. Inferences can be corrected and coverage is limited by the data the client exposes. Previously missed deaths are not reconstructed automatically.

Explicit buttons and manual opinions retain priority, including after an emote. Gestures alone no longer pin a relationship: `/spit` cannot keep a killer at caution when a PvP death is subsequently recorded. Duel detection still depends on the available client signals.

The existing offline suite covers fifteen test scripts, including 71 tracking scenarios. These tests simulate WoW APIs; they do not replace actual gameplay testing. This remains an early version, and bug reports are welcome.

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
python -m zipfile -c GrudgeLedger-0.4.3.zip GrudgeLedger
```

Issues and pull requests in French or English are welcome. For bugs, include the addon/client versions, steps to reproduce, expected and actual behavior, and a screenshot with personal information hidden if useful. Keep fixes focused and run the existing tests. Please do not submit anyone's personal journal.

## License and acknowledgments

**GNU GPL v3**, see [LICENSE](LICENSE). You may use, study, modify, fork and redistribute the project, including commercially, under that license. When distributing modified versions, preserve the notices, provide the corresponding source and keep them under GPLv3. This is not an unrestricted public-domain release; it is provided without warranty.

Menu integration and nameplate/tooltip lifecycle techniques are adapted from [Worth Remembering by Kyle (maliceftw)](https://github.com/kk-on-gh/WorthRemembering), under GPLv3. The independently implemented PvP module was informed by [Grudgebook](https://www.curseforge.com/wow/addons/grudgebook)'s described approach. Neither addon is bundled or required. See [full credits](GrudgeLedger/CREDITS.txt).

Original contributions, documentation and the included generated book and relationship artwork are shared under the same GPLv3 terms. Native WoW textures and sounds are referenced from the installed client, not redistributed. Unofficial project; not affiliated with Blizzard Entertainment or OpenAI.
