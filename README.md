# Grudge Ledger

**0.10.3.** Outdoor combat now credits each contributing opponent once per death, even when a creature lands the final blow. Previous attributions are combined on upgrade. Resurrecting enables a fresh nearby warning. The journal keeps recently seen portraits during the session and shows your recorded honor on the contact summary. Enemy honor is unknown.


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
- **PvP memory:** records observed aggression and deaths. Each result counts once and can be corrected without erasing your personal notes.
- **Friendly and unfriendly gestures:** your own targeted emotes can adjust camaraderie, including toward the opposing faction. Repeated emotes are rate-limited.
- **Guild opinions:** mark an entire guild, with individual exceptions.
- **Guild history:** keep the last observed guild and snapshot it separately for each new PvP event, including its realm and observation time. Missing replies do not erase known guilds; later membership changes never rewrite old encounters. Unknown guilds stay unknown. Guild rankings use these event snapshots to count each death once per guild.
- **Nearby encounter alerts:** a small popup above the main chat in the lower-left area, with distinct sounds, cooldowns and grouped guild alerts. It follows the chat's position, leaving room above its tabs. Friends in your party or raid never trigger these alerts. Other friends alert on first sighting, then only after more than ten minutes without an observed presence; every sighting renews this window, including across UI reloads. Encounter clocks are separate for each of your characters.
- **No automatic roster clutter:** joining a group does not add unknown players. Group history is kept for existing contacts; legacy entries containing only group sessions are hidden without deleting them. Opinions, notes and PvP records remain visible.
- **A personal journal:** notes, encounters, shared groups and PvP history, accessed through the red book on the minimap or `/gl`.

![Offline preview of the ancient-book journal, with synthetic example records](docs/journal.png)

The campaign register brings together the journal, rankings, guilds and personal PvP summary. Filter contacts by relationship and faction, then open a record to see its automatic score, latest encounter, history or notes. Race portraits and class icons use identity information supplied by the game.

The leather, cloth and parchment share a decorative background. The medallion, title plaque, settings and close buttons have independent textures. The gold wordmark is a separate texture. WoW renders names and journal entries in PT Serif, with bold headings and italic annotations. Classic mode uses the native game font. The offline preview uses fictional contacts.

Open the cog or use `/gl settings` to set the font, text size and spacing. The first-use guide can be opened again from **Données et aide**.

The index opens with the most recent interaction first. A new encounter, fight, gesture, trade or note can move a contact up. Submitting a search restores the preferred result order. Clearing it returns the index to chronological order.

### Keeping portraits when players leave view

The journal prefers the live portrait, then the saved Armory avatar for that exact character. Hover over a journal row to see the source. The optional desktop importer needs Python 3 and Pillow. Run it on demand and choose your own game folder and region.

```powershell
python -m pip install Pillow
python tools/sync_portraits.py "F:/game/World of Warcraft/_forever_" --region eu
```

Add `--name "First Surname"` for one contact. WoW writes journal records at logout or on `/reload`. The importer looks up saved names on Blizzard's public Armory, checks each avatar's character ID and saves a 64 × 64 texture. Notes, opinions and events stay on your computer. Restart the game after importing and enable **Grudge Ledger - Private portraits**. A subsequent run refreshes images after seven days, or immediately with `--force`. Images live in the separate `Interface/AddOns/GrudgeLedgerPortraits` folder. Share only `GrudgeLedger`. To clear the image cache, remove the private folder while the game is closed.

### New in 0.10.0

**Summary → Overview → Initiative** shows who opened observed fights and how confirmed victories break down. **Revenge** requires a confirmed earlier death of this character to the same opponent, an observed opening hit from your side, and a confirmed victory. Winning after the opponent opens counts as a response. Victories with a missing opening still count under **Unknown initiative**, including older fights.

Select **Honor received** to review recorded outdoor PvP rewards for the selected period and character. **Journal → Head-to-head** shows rewards tied to one opponent. Shared honor counts even when a teammate lands the killing blow. The game reports the honor paid to your character. Your opponent’s payout is unknown.

### New in 0.9.2

**Head-to-head** shows this character’s outcomes. Open the matching fight history to review the evidence. Shared honor is excluded when the game identifies a different killer in the same encounter. A delayed combat-log confirmation for a continuously observed corpse updates the original victory.

Repeat-encounter rankings start on the second recorded meeting. Zone statistics display incomplete time coverage alongside excluded fights.

### New in 0.9.1

The Journal opens the most recent contact on first use with an existing ledger. Guilds shows the first matching guild, and the PvP summary puts personal rivals directly below the counters. Press Enter or click the magnifying glass to search the Journal.

In outdoor PvP, a personal killing-blow event can confirm a victory even when the combat log is unavailable. A matching later signal upgrades the original entry. To correct a past victory that you witnessed, open **History → Verify → I dealt the killing blow**. The original fight stays in place and the history identifies your personal confirmation.

### New in 0.8.0

- **Journal → Face-à-face** shows this character’s confirmed outcomes against a contact, the current streak and the most recent win following a loss. Each victory still counts as +1. New combat history can show levels, health at first PvP observation, distinct opponents and pet or NPC involvement.
- **Bilan → Par zone** opens the combat breakdown for each district. The optional zone clock measures connected outdoor time from activation and pauses while AFK or in instances. **Mon année** can prepare a text copy of the selected totals.
- The friends ranking includes observed time grouped together. An optional trade history records completed exchanges with existing contacts, including items and money given and received.
- Optional indirect alerts distinguish a known threat heard nearby or targeted by a visible party member from a direct sighting. Appearance settings offer local relationship icons in chat and compact tooltips with Shift for details. The new indirect alerts, badges, compact tooltips, trade history and zone clock are off by default.

In 0.7.2, visible contacts can show their current in-game portrait. When a player is unavailable, their record uses a race, class or faction emblem. The personal summary also groups fights by zone. Combat and death evidence from pets can be attributed to their owners when the client supplies the link.

In 0.7.1, open an event in **Histoire** to review its attribution before cancelling it. Use **Notes** to write, edit and browse a player's notes. In the summary, **Mon année** opens the chronicle for the selected year. Each guild page shows its rule and any individual exceptions. Type `/gl version` to check which version Forever has loaded.

## Grudge balance

Automatic records count **−10 per death, −1 per aggression and +1 per victory**. Negative gestures add to that balance: one death, one negative gesture and two victories leave **−9**, still **caution (orange)** with nearby alerts. Victories alone never create friendship; friendly gestures do not hide outstanding negative PvP debt. Explicit Friend/Caution/Enemy classifications and manual opinions stay authoritative. Existing automatic records are recalculated without deleting notes, counters or history.

The personal **“Neutre” button is now “Automatique”**: it restores scoring from PvP encounters and gestures instead of forcing zero. Legacy records pinned by that button are repaired on load; an outstanding −9 stays orange. A genuine zero reached through manual +1/−1 opinions remains a personal choice. Notes, counters and history are preserved. Guild rules remain separate.

A **gray medallion** marks known neutral people in the journal and on their visible nameplates. Neutral contacts do not trigger popups or sounds; unknown players remain unmarked.


## 0.6.1: more meaningful rankings

**Classements** or `/gl stats` opens a book with themed navigation:

| Theme | Rankings |
| --- | --- |
| Threats | Strongest grudges, most encountered threats, recently observed threats, confirmed aggressions |
| Friends | Most encountered friends, strongest affinities, recently observed friends, shared group sessions |
| Combat | Players who killed you most, most defeated opponents |
| Guilds | Personal grudges, personal friends, deaths, victories and aggressions |

Each view states its units, scope and calculation. Active Person/Guild tabs and
themes are marked; player lists filter by Alliance, Horde or unknown faction.
Click a person to open their record; select a guild to set a guild-wide opinion.

**Encounter counts are memories, not current presence.** A new encounter starts
after more than ten minutes without observation. Lists use current relationships,
but their encounter/group totals may include earlier sessions. Recent dates come
only from real observations; notes and opinion changes do not refresh them.
Unmarked group partners do not become friends in these rankings.

Zero-value guilds are omitted for the selected metric. Guild friend/grudge lists
describe current relationships and last known memberships; combat rankings retain
the guild known at the time of each event. Existing counters are reused, without
another background watcher or database migration.

![Most encountered threats, offline preview with fictional data](docs/statistics.png)

Validation: **26 test scripts and 48 offline UI views**, including small windows,
empty lists, long names and readable fonts. Native rendering remains to be checked.

## 0.6.0: personal PvP summary and chronicle

**Bilan & récit**, `/gl bilan` and `/gl chronique` open two new pages. The summary
shows observed victories, deaths and aggressions, your nemesis and most defeated
opponent. The chronicle combines events across records with dates, places, people
and explanations.

- **Period and character filters:** all time, rolling seven/thirty days or a calendar
  year; current character, whole account or legacy records without an identified
  author. Old events are never silently assigned to the current character. Annual
  cards cover recorded events only; image export is not implemented. Most-seen
  friends are explicitly account-wide, all-time memories because individual
  encounter timestamps were not retained.
- **Counting:** a death involving several opponents counts once in the summary
  when its shared event identifier exists. Legacy events without identifiers cannot
  always be deduplicated. Corrected and excluded battleground events do not inflate
  the totals.
- **Search and layout:** combine words across names, guilds, notes, zones, races
  and classes; filter by relation, faction and notes; choose sorting and the index's
  second line. Chronicle search runs on Enter/OK instead of on every keystroke.
- **Personal notes:** browse, edit and delete with confirmation; font changes
  preserve drafts.
- **Optional party warning:** disabled by default. A nearby past aggressor with
  PvP evidence can trigger a short party message, in small groups only. Friends,
  teammates and manual enemy tags without PvP evidence do not qualify. Private
  notes are never sent. Limits: one message per minute overall, thirty minutes
  per person and more than ten minutes without observed presence before another
  warning. No delayed queue, battleground, arena or raid announcements.

The **one death = ten victories** rule is preserved and tested: two deaths require
twenty victories without clearing other debts or personal decisions. Guild sharing
and friendly bounties remain future ideas. Druid radar work stays paused. No external
service is added.

![Offline honor-board preview with synthetic records](docs/honor.png)

Validation covers 26 test scripts and 48 offline UI views. See the
[architecture review](docs/architecture.md) for measurements and large-journal limits.
Native appearance, sounds and alerts still need real-client validation.

## 0.5.12: reduce repeated observation and UI work

Polling shares identity metadata for less than half a second, with live GUID
checks and fresh reads for actions. Stable markers avoid repeated texture and
layout writes. Guild statistics are reused until relevant data changes, and
social scores process new history entries incrementally. Histories and personal
choices are preserved; no runtime dependency or background timer was added.

See the [architecture review and reproducible benchmark](docs/architecture.md)
for measurements, cache contracts and remaining large-journal limits. Offline
tests do not establish real-client FPS gains. Druid radar work is deferred and
its manual experimental behavior is unchanged.

## 0.5.11: clean up old battleground grudges

On first load, PvP events recorded in exactly Arathi Basin, Warsong Gulch or
Alterac Valley (French or English zone names) are excluded from scores and stats.
Records containing only these fights, without personal notes or opinions, leave
the active journal but remain in `battlegroundArchive` in your private SavedVariables.
Mixed records retain their history with an explicit battleground exclusion label.
Notes, gestures, personal opinions, guild rules and outdoor events are preserved.
Unknown locations are never guessed. This migration runs once, not in the background.

## 0.5.10: pause automatically in battlegrounds and arenas

Battlegrounds and arenas no longer create automatic grudges or affect existing
scores, PvP statistics, sightings, group memories or emote opinions. Nearby alerts,
relationship markers and tooltip additions pause there too. Pending combat
inferences are discarded at the boundary so they cannot be recorded after leaving.

Your journal and manual notes/classifications remain available. Existing records
and settings are preserved; outdoor tracking resumes automatically on exit.
Dungeons, raids and scenarios retain their normal behavior.

## 0.5.9: validate a full scan and distinguish real zoom changes

Zoom notifications no longer abort a trial unconditionally. The next update
checks the actual zoom and view radius; a change reports the measured mismatch.
If the initial radius was unreadable, a zoom notification still stops the trial
with a specific explanation. Reports count these notifications. This fixes an
interruption path; it does not yet validate reliable live detection.

One live 0.5.7 trial on build 70888 read the selected witness twice without manual
minimap hovering, with successful blank controls: 69 positions, 53 reads and
12 distinct texts in 2.1 seconds. This validates that witness in that trial,
**not twelve identified players or reliable continuous coverage**.

After `/reload`, select a stationary humanoid player visible on the minimap,
in cat form with Track Humanoids active, outside combat and instances. Open
`/gl debug` → **Préparer la minimap** → **Validation druide**. The window closes;
place the pointer over empty world space within three seconds and stay still.
The minimap is temporarily hidden for at most 12 seconds. `/glradar stop` cancels.
The witness need not be in the journal. Retrieve the anonymous result with
`/glradar rapport` or Diagnostic.

`/glradar validation` attempts all 225 grid positions instead of stopping at the
first witness hit as `/glradar test` does. Reports show sampled/skipped positions,
duration, cumulative synchronous work and the longest measured call, when the
native timer is available. These timings **exclude native rendering between calls**;
they are not a complete FPS or memory benchmark. The coarse grid can miss dots.

144 simulated radar cases verify the protocol, interruption/restoration, optional
timer failures and limits: no more than 229 native reads, one per rendered frame,
12 seconds and ten name-free reports. No scanner runs while idle. Before enabling
an optional automatic mode, live tests must check identities, different minimap
layouts, interruptions and resource use on several machines. See the
[validation criteria](DEVELOPMENT.txt). **The radar remains manual and experimental.**

## 0.5.7: skip samples covered by minimap controls

Moving the minimap also moves attached controls underneath the stationary cursor.
The experiment previously treated their hover as an unrelated window and stopped.
It now skips and counts those scan samples without reading their tooltips or
disabling their controls. Unrelated UI still stops the experiment; an obstructed
blank control or witness replay cannot validate a result.

113 simulated cases cover the second-sample interruption, nested controls,
obstructed samples and restoration. A later live trial verified one witness;
the broader validation procedure is described above. The radar remains manual.
Use `/reload`, then `/gl debug` → **Préparer la minimap** → **Validation druide**, with
a stationary player selected as the witness.

## 0.5.6: distinguish druid test failures

The report now distinguishes a missing target, an NPC/pet, self-targeting and
an unreadable or incomplete player identity. Geometry failures identify the
property and its measured/expected values, instead of combining seven checks
into one generic error. Size checks allow the same 0.1 UI-unit rounding tolerance
as position checks; meaningful changes still stop the test. Reports include the
addon version as well as the client build.

**The witness does not need to be in the journal.** A successful reading can have
zero known matches. Missing knowledge does not explain a test that stops before
reading any points, and the test never adds the witness to the journal.

Use `/reload` for this update. The test procedure below is unchanged; automated
checks verify the protocol, not whether the native client supplies player names.

## 0.5.5: prepare the druid experiment from the diagnostic window

The experiment called `Minimap:GetMaskTexture()`, which Forever does not expose.
The test double incorrectly supplied that method. The addon now observes native
`SetMaskTexture` calls and restores their exact asset; it never guesses a default
mask. If no mask has been observed since load, the test stops before any mutation.
After `/reload`, open `/gl debug` and click **Préparer la minimap**. This explicitly
reapplies Forever's native minimap appearance using its current rotation setting;
it does not change saved settings or reset an already observed custom skin.
Once ready, select a stationary player visible on the minimap and click **Validation druide**:
the window closes, leaving three seconds to place the pointer on empty world space.
Stay still in cat form with Track Humanoids active. Preparation alone never starts
a scan, and remains unavailable during combat or another test.
This fixes preparation, **not proof that native player detection works**.

## 0.5.3: targeted gesture requests and readable history

Kiss/spit buttons now use the selected unit as the native commands do, instead of
passing the literal character name `target`. Rejected button calls no longer add
opinions through post-hooks. Both factions use native emotes without custom-text
substitutes. **This does not restore targeted `/spit` wording removed by Blizzard**;
if Forever retains that restriction, the recipient still sees a ground spit.
See the [official 9.1.5 notes](https://worldofwarcraft.blizzard.com/en-us/news/23731242/915-content-update-notes).

History clearly states who killed whom, separates suspected participation and spaces
events with dates, places and personal reasons. Raw PvP evidence remains available
in the correction window. New events snapshot the subzone and explicitly tracked
quest when readable, without guessing the current activity or enriching old events.
Gesture history records intent, not delivery confirmation. No saved history is deleted.

20 Lua 5.1 suites and 27 simulated UI views verify logic/layout, not actual recipient
messages across factions. A UI `/reload` is sufficient when upgrading from 0.5.2.

## 0.5.2: druid detection experiment without manual minimap hover

The virtual-cursor experiment failed on the observed Forever build 70888.
An alternative, explicitly started experiment now tests native tooltip reads
by briefly moving a hidden minimap under a stationary mouse. It never moves the
mouse, selects a target, changes tracking or creates grudges.

After restarting WoW, be outside combat and instances, in cat form with
**Track Humanoids** active. Target a stationary humanoid player whose dot is
visible on the minimap. Put the pointer over empty world space, type
`/glradar test`, and remain still for up to 12 seconds. The minimap temporarily
disappears. `/glradar stop` cancels; movement or combat also stops the test.
Use `/glradar rapport` or the diagnostic window to retrieve the name-free
outcome, failure stage and counters. Do not run another minimap scanner alongside it.

A positive result requires two matching full-name reads with blank controls
before, between and after. The bounded 225-point grid can miss a dot; low frame
rates can time out. **This does not yet enable a continuous radar, distant-threat
alerts or automatic tracking in cat form.** The 135 automated experiment cases
test our protocol and restoration logic; the single live success described above
does not establish reliability across players and configurations.
There is no specific Blizzard approval for this use. See the [investigation and
primary sources](DEVELOPMENT.txt) and [in-game test instructions](GrudgeLedger/README.txt).

## 0.5.1: a recognizable kiss icon

The kiss button now uses original painted red lips blowing a pink heart, generated
with OpenAI's image tool, inside the native WoW button frame. Restart the game after
updating to load the new texture. Gesture behavior is unchanged.

## 0.5.0: chronicles, guild rankings and diagnostics

A shared death ID counts once per guild. Different guilds can be involved in the same death, so their totals are not additive. Legacy events without a shared ID are not guessed into one event.

The book now opens **Statistics** (`/gl stats`) and **Guild rankings** (`/gl guildes`). Rank player deaths, victories, negative balances, positive friendships and distinct encounters. Guild lists count personal grudges/friends and historically attributed deaths/aggressions. Click a guild to mark it for caution, as friendly, or edit its rule/notes. Personal overrides still win, inherited rules do not inflate personal grudge counts, unknown historical guilds remain unassigned and membership changes never rewrite old events.

Two **kiss/spit** buttons with native WoW frames sit above chat, below alerts. Clicking acts on the selected player using the existing emote path (+1/−1, same 30-second sentiment cooldown). Ctrl-drag moves the pair; settings hide or reset it. No automatic emotes or forced targeting.

Distinct encounters begin with this version: another encounter requires over ten minutes without an observation, with every sighting renewing the clock. Reloads preserve continuity; character clocks are separate and totals belong to this account's book. No old visits or time-spent estimates are invented.

`/gl traces` displays a private, bounded 200-entry decision log explaining shown/suppressed alerts and missing readable identities. Repeats are throttled to 30 seconds. It can be cleared or disabled. `/gl debug` exports an anonymized report with no names/notes. SavedVariables stay separate from the shipped addon; normal logout or UI reload flushes them to disk.

The standalone minimap experiment is now integrated (`/glprobe test`, `/glprobe stop`): a stationary hovered reference, automatic re-read off the map, and a blank-point control distinguish real reads from stale caches. The name-free outcome and client build survive reloads. **This is a manual capability test, not an enabled automatic radar or tracking toggle.** A negative result is conditional on the tracked point staying still; even a positive isolated trial does not validate moving-world scanning. Unit tests cover working, blocked, missing, secret and stale-cache APIs; only live client observations establish what Forever actually allows. No trace does not prove a player was absent from the world.

Remove/disable the previous temporary `GrudgeLedgerProbe` addon to avoid command conflicts. Restart WoW once after updating to load the new source files.

## Install

1. Download the **`GrudgeLedger-<version>.zip`** addon package from [Releases](https://github.com/Aizakira/GrudgeLedger/releases/latest).
2. Extract the `GrudgeLedger` folder into your Forever client's `Interface/AddOns` folder. The final path must be `Interface/AddOns/GrudgeLedger/GrudgeLedger.toc`.
3. Restart WoW and enable Grudge Ledger in the addon list.

No other addon is required. Disable Grudgebook and Worth Remembering if they are installed for the same purpose, to avoid duplicate menus, markers and alerts. GitHub's automatic **Source code** archive contains developer files; only its inner `GrudgeLedger` folder belongs in `AddOns`.

Left-click the minimap book to open the journal, right-click it for settings, or drag it around the minimap. Right-click a player portrait or chat name to start adding people. Search and slash commands are optional. The interface follows the WoW text language. French, English and Spanish (Spain and Latin America) are supported. Other locales use English. Switching languages keeps player names, guild names and personal notes as written.

For visible icons and colors, click **“Activer le repérage (icônes + couleurs)”** in settings, or run `/gl reperage` outside combat. This enables Forever's friendly-player nameplates, enemy nameplates and out-of-combat display, along with the addon's markers and name coloring. Plain floating world names are not editable nameplate labels. A friend in your party keeps their heart; only the nearby popup is suppressed. If the tooltip says Friend but the heart is missing, enable recognition outside combat. Native name-only nameplates are supported, including when Threat Plates hides its own name text. A player classified as **Ennemi** is red; **Méfiance** or a single negative opinion is orange.

| Command | Action |
| --- | --- |
| `/gl` | Open or close the journal |
| `/gl ami` / `/gl mefiance` / `/gl ennemi` | Mark your selected player as friend / caution / enemy |
| `/gl auto` (or `/gl neutre`) | Restore automatic scoring without erasing outstanding PvP debt |
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

Forever may hide combat-log information. The addon also reads its public death recap, waiting up to two seconds for delayed data. Each identified participant receives credit for the death. Without usable direct evidence, recent hostile PvP combatants actually targeting you may be recorded as participants; bystanders are excluded. Counters belong to each person's record: three participants in one death do not mean three player deaths. Inferences can be corrected and coverage is limited by the data the client exposes. Previously missed deaths are not reconstructed automatically.

Explicit Friend/Caution/Enemy buttons and manual opinions retain priority, including after an emote. Gestures alone no longer pin a relationship: `/spit` cannot keep a killer at caution when a PvP death is subsequently recorded. Duel detection still depends on the available client signals.

The existing offline suite covers fifteen test scripts, including 71 tracking scenarios. These tests simulate WoW APIs; they do not replace actual gameplay testing. This remains an early version, and bug reports are welcome.

## Your journal stays yours

Every new account starts with an **empty journal**. The addon contains no preset players, guilds or blacklists. Its account-wide database is saved by WoW in `WTF/Account/<account>/SavedVariables/GrudgeLedger.lua`, separately from the addon code. Sharing the addon folder or release ZIP does **not** share your notes. There is no automatic player-to-player database exchange or telemetry.

Never upload your `WTF` folder or SavedVariables when reporting an issue. The optional `/gl debug` report excludes player identities, guild names, notes and raw errors; you choose whether to copy and share it.

## Development and contributions

Contributions are welcome through forks and pull requests. **@Aizakira approves
changes before integration; official releases remain manual.** See the
[contribution and review policy](CONTRIBUTING.md) for the required checks and review process.

Python 3.11 and the pinned test dependency are only needed for development, not to play:

```sh
python -m pip install --target test-runtime -r requirements-test.txt
python tests/run_tests.py
```

GitHub Actions runs the same suite on Linux and Windows. See [DEVELOPMENT.txt](DEVELOPMENT.txt) for the optional offline UI renderer. To build an installable archive from the repository root:

```sh
python -m zipfile -c GrudgeLedger-0.5.12.zip GrudgeLedger
```

Issues and pull requests in French or English are welcome. For bugs, include the addon/client versions, steps to reproduce, expected and actual behavior, and a screenshot with personal information hidden if useful. Keep fixes focused and run the existing tests. Please do not submit anyone's personal journal.

## License and acknowledgments

**GNU GPL v3**, see [LICENSE](LICENSE). You may use, study, modify, fork and redistribute the project, including commercially, under that license. When distributing modified versions, preserve the notices, provide the corresponding source and keep them under GPLv3. This is not an unrestricted public-domain release; it is provided without warranty.

Menu integration and nameplate/tooltip lifecycle techniques are adapted from [Worth Remembering by Kyle (maliceftw)](https://github.com/kk-on-gh/WorthRemembering), under GPLv3. The independently implemented PvP module was informed by [Grudgebook](https://www.curseforge.com/wow/addons/grudgebook)'s described approach. Neither addon is bundled or required. See [full credits](GrudgeLedger/CREDITS.txt).

Original contributions, documentation and the included generated book and relationship artwork are shared under the same GPLv3 terms. Native WoW textures and sounds are referenced from the installed client, not redistributed. Unofficial project; not affiliated with Blizzard Entertainment or OpenAI.
