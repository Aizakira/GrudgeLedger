# Architecture and performance

Review for 0.5.12, 12 November 2026. This describes the implementation and its
limits, not a guarantee of live-client performance.

## Runtime and ownership

The addon runs in WoW's Lua environment. Keep runtime code in Lua and use native
UI frames and events. A Rust rewrite would not run as a normal WoW addon and
would not fix API availability or detection restrictions. Python is used only
for development checks and packaging; users install only `GrudgeLedger/`.

There are nine Lua modules, no third-party runtime library and no external
service. Keep the existing separation instead of adding a framework:

| Module | Responsibility |
| --- | --- |
| `Core.lua` | Identity, relationships, persistence, migrations, counters and statistics |
| `Tracker.lua` | PvP observations, bounded combat inference and group events |
| `Social.lua` | Targeted gestures and opinion changes |
| `Menu.lua` | Native context-menu integration |
| `Display.lua` | Nameplate markers, tooltips and encounter alerts |
| `UI.lua` | Journal, settings, statistics and manual corrections |
| `QuickGestures.lua` | Floating gesture buttons |
| `MinimapProbe.lua`, `DruidRadar.lua` | Isolated, manual experiments; unchanged in this review |

Gameplay observations flow through Core mutation functions before notifying
subscribers with `CHANGED`. UI actions use those same functions. Core owns
relationship precedence and history corrections; display code must not implement
a second scoring system. Confirmed and inferred events stay distinguishable.

Source files belong in `Interface/AddOns/GrudgeLedger`; the game's SavedVariables
belong in `WTF`. Tests, previews and benchmarks use fictional records. Neither
packaging nor deployment should copy journals into the addon or repository.

## Changes in 0.5.12

- **Shared identity metadata.** Polling may reuse name, class, race, faction and
  guild metadata for less than 0.5 seconds. The live GUID, player identity and
  unit existence are checked on each call. Target/nameplate tokens can be reused
  by the game, so they are not cache keys. Default `GL.Identity(unit)` reads fresh;
  explicit polling callers opt in with the second argument. Health and combat
  state are never cached. Missing/protected/invalid clocks fall back to fresh reads.
  At most 256 observations are retained; the session cache resets on DB init.
- **Nameplate writes only on change.** Marker size, anchor, frame level and
  texture are applied when changed. Name colors are still read to detect another
  addon's updates. Recycled plates, settings and ThreatPlates levels remain live.
- **Guild totals on demand.** History is scanned once, then totals are reused
  until a relevant Core mutation. Creation, identity merging, guild changes,
  opinions, notes, events and corrections invalidate them. Returned rows are
  copies, so sorting or editing results cannot corrupt the shared totals.
- **Incremental social totals.** New opinions process the appended history tail.
  Normalization, identity merging, replacement or truncation rebuild the subtotal.
  PvP counters are read fresh. These caches are session-only; authoritative
  histories, correction evidence and the SavedVariables schema are preserved.

Tracker polling remains at 4 Hz and display polling at 2 Hz. No new background
timer was added. Hidden journal windows do not rebuild their lists. The radar
still runs only after a manual experiment and removes its update driver on stop.

## Measured evidence

`python tests/benchmark.py` loads the real TOC with `tests/addon_mock.lua`. It
creates synthetic records, advances a simulated clock at 60 updates/second and
counts calls. Timing uses warmed medians (seven repetitions for UI operations,
three for polling), with garbage collection outside the timed operation.

Before: commit `67feeda` (0.5.11). After: 0.5.12 candidate on the same Windows
machine, Python 3.11 and Lupa Lua 5.1. Measurements below are offline examples;
timings fluctuate and are not CI pass/fail thresholds.

| Workload | Before | After |
| --- | ---: | ---: |
| 80 known plates, name metadata reads / 10 simulated seconds | 4,640 | 1,600 |
| Same workload, texture writes after warm-up | 1,600 | 0 |
| Same workload, all addon anchor writes | 1,610 | 10 |
| Same workload, synchronous mocked execution | 136.9 ms | 99.9 ms |
| Unchanged guild statistics repaint, 1,000 people / 10,000 events | 27.0 ms | 0.053 ms |

The remaining anchor writes above are unrelated to stable markers. The identity
function is still called just as often; the reduction is in metadata retrieval.
Guild statistics timing above is a warm repaint, **not** a cold rebuild.

A separate run of the checked-in benchmark measured cold guild rebuilds at
2.3 / 25.6 / 292.2 ms for 100 / 1,000 / 10,000 people, with ten events each.
At 10,000 people the main journal refresh was about 26 ms. These remain scaling
limits: guild rebuilding is O(people + history), and list sorting is O(n log n).

Synthetic retained Lua data for 10,000 people / 100,000 events was about 68 MiB,
versus 65 MiB before. Incremental subtotals trade a small per-record allocation
for less repeated work. This is not total addon memory: it excludes native
textures/frames and the real client's allocator. Histories remain unbounded
intentionally; silently deleting old memories is not an optimization.

**No result here measures real WoW FPS, engine/GPU rendering, or client API cost.**
Use a comparable in-game scene, several journal sizes and sessions with/without
the addon before claiming a live FPS improvement. No game controls or personal
SavedVariables are touched by the benchmark.

## Maintenance contracts and next limits

1. Treat returned identities and stored records as read-only outside Core. Use
   existing mutation functions; invalidate derived guild totals on new mutation
   paths. A future edit of an old social event must also discard its subtotal.
2. Keep API boundary checks (`Clean`/`Safe`) and uncertainty labels. Caching must
   never turn missing information into a confirmed player or combat event.
3. Keep features event-driven where possible, bounded when polling is needed,
   and UI work lazy. Do not introduce a global scan every frame.
4. Add meaningful behavior/operation-count checks to the existing Lua suite.
   Shared mocks make tests repeatable, not authoritative about native API support.
5. If large real journals cause pauses, first measure the triggering operation.
   Then consider incremental guild aggregation or explicit user-controlled
   archival; do not add either preemptively. Profile before splitting Core/UI or
   adding persistent indexes and migration burden.

`tests/performance_test.lua` checks cache bounds, expiry, recycled unit tokens,
fresh actions, unavailable data, guild mutation/correction/merge invalidation,
copy isolation and large social-history updates. Existing integration tests load
the TOC and exercise menu -> database -> markers -> alerts -> journal together.
The complete suite currently has 22 scripts; CI runs it on Windows and Linux,
with 27 offline UI views on Windows. Native appearance, sounds, targeting and
protected APIs still need a real-client smoke test.

Changes go through a branch and pull request. Passing CI does not merge a PR or
publish a release. The owner's contribution review remains required by the
repository's contribution policy.
