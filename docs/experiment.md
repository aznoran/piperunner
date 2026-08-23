# The offer, and the question left open about it

Two ways of handing the player a shape. Only one of them is served.

## The two variants

| | Strip | Taking a shape | Class |
|---|---|---|---|
| **B** offer | three shapes, all equal | **all three** are replaced | `OfferSource` |
| **C** held offer | three shapes, all equal | **only the one taken** is replaced | `HeldOfferSource` |

They differ by one method, and B is what players get.

## What happened to A

There used to be a third: the forced queue the game shipped with — a piece in
hand, a four-deep preview behind it, a pocket for an awkward shape. It is gone.

Across five playing styles it was nobody's best, and at casual play *every one*
of its runs ended with the track running out rather than with an empty tank,
which means the fuel economy, the crystals and the continue offer never got to
matter at all. `docs/variant-analysis.md` has the numbers; the `experiment-abc`
branch has the code, and nothing here depends on it.

### What "held" means in C

In B the offer is spent whole: nothing on the strip outlives the turn it was
dealt on. In C a window refills only when the player takes from *that* window;
the other two keep their shapes, turn after turn, until the player finally
takes from them.

That buys the player a stash they did not pay for — an awkward shape can sit in
its window until the joint that wants it comes round. It costs them a strip
that goes
stale: take repeatedly from one window and the other two quietly become dead
weight, and the choice narrows to one live shape and two already rejected.

Which effect dominates is the thing being measured, so everything else about B
and C is identical — same strip, same dealer, same number of windows. The one
overridden method is `spend()`, and `HeldOfferSource` carries the comment
explaining it.

A refilled window never repeats a shape still on the strip. Three identical
windows is not a choice, and letting the strip collapse to one would make C
look worse for a reason that has nothing to do with holding.

## Architecture

`BlockSource` is the `BlockSelectionStrategy` of the brief. Main talks to it
and never to a concrete variant, so there is no `if variant ==` anywhere in the
game loop — the only place a letter turns into behaviour is
`Experiment.make_source()`.

```
Experiment.make_source() ─→ BlockSource ─┬─ OfferSource      (B) ─┬→ OfferBar
                                         └─ HeldOfferSource  (C) ─┘
```

Each variant also names the dealing rule it was designed around
(`make_dealer()`): `OfferDealer` for B, which insures the rare dead offer and
guarantees a way up under pressure, and `HeldOfferDealer` for C, which watches
what is *staying* on the strip and works to how many of the four sides it can
answer. Input needs no variant knowledge at all — the strip publishes tap
targets as an array of rects.

## The switch

**C is built, tested and not served.** Two Remote Config keys, not one:

| Key | Meaning | Default |
|---|---|---|
| `held_windows_enabled` | the switch. Off, and everybody gets B | `false` |
| `gameplay_variant` | the split, `B` or `C`. Read only while the switch is on | `B` |

Two keys because they answer different questions. The split is an experiment
setting, fiddled with while a test is being planned; the switch is a decision
about what players get. Collapsed into one value, a mistyped rollout percentage
starts serving an untested mechanic with no quick way back.

The switch **overrides a saved group** — the one place the assign-once rule
below is deliberately broken, because that is what a kill switch is for. The
saved letter is kept rather than erased, so turning it back on restores the
groups instead of reshuffling them. `tests/switch_check.gd` asserts that a
saved `C` cannot reach a player while the switch is off.

## Assignment

`Experiment` (autoload) resolves the group from Remote Config key
`gameplay_variant`, `B` or `C`, once the switch is on.

Three rules keep the data honest, and each is enforced in code:

- **Assign once.** The first answer is written to `user://experiment.cfg` and
  is the answer from then on. A player who switched variants mid-test belongs
  to neither group.
- **Offline keeps its group.** Once the switch is on and a player has been
  assigned, a session with no network uses the saved letter. Falling back to B
  for an offline C player would file their runs under the baseline and poison
  it. Before the switch is on there is no group to keep, so B it is.
- **Debug overrides are marked.** Forcing a variant from the bench does not
  persist and does not count as an assignment; every event it produces carries
  `debug_override: true`.

Firebase buckets by installation ID, so a player stays in their group across
sessions without the game rolling anything itself.

**Until the switch is turned on, every device plays B.** C is reachable only
from the debug bench, which marks everything it produces `debug_override`.

## Events

Every event carries `variant`. The group also goes on as the user property
`variant`, which is the only thing Firebase's own retention report can be split
by — D1/D7 are computed from sessions the SDK logs itself, and those carry no
parameters of ours. Retention and `session_count` need no instrumentation
beyond that property.

| Event | Parameters |
|---|---|
| `play_session_start` | — |
| `play_session_end` | `duration_s` |
| `run_completed` | `distance`, `score`, `duration_s`, `reason` |
| `run_abandoned` | `distance`, `duration_s`, `stage` |
| `block_taken` | `shape`, `slot`, `slot_count`, `was_held`, `distance` |
| `retry` | `streak` |

`session_start` is a **reserved** Firebase event name — the SDK logs its own and
rejects ours — hence the `play_` prefix on the pair. Firebase's automatic
sessions keep counting alongside them, already split by variant through the
user property.

`block_taken` is where the variants separate. `slot` and `slot_count` say which
of how many windows the shape came from; `was_held` answers C's question —
whether the player took a freshly dealt shape or one they had been sitting on.
The event is sent *before* the deal, so it describes the strip the player was
looking at when they chose.

`run_abandoned`'s `stage` is `before_first_pipe` for backing out of the menu,
or `backgrounded` for the app going to the background mid-run — which on a
phone is how most runs actually end.

Events logged before the group is known are buffered and flushed once it
resolves, so a new player's first session is not filed under the fallback.

## What is done, and what is not

**Done and testable now:** both variants, the switch, the assignment logic with
its fallback and persistence, every event above, the user property, and the
debug bench. The GDScript side runs on desktop with no SDK at all — events print to
the console in a debug build.

**Not done:** the native SDKs are not built or linked. They cannot be, until
there is a Firebase project: `GoogleService-Info.plist` for iOS and
`google-services.json` for Android. The plugin sources are written and sit in
`native/`, against the contract in `scripts/firebase_bridge.gd`, but they are
**uncompiled** — treat them as a starting point that has never seen a compiler,
not as tested code.

### To finish it

1. Create the Firebase project; register the iOS and Android apps under
   `com.antonsavchenko.piperunner`.
2. Add `GoogleService-Info.plist` to the exported Xcode project, and
   `google-services.json` to the Android export.
3. In Remote Config, add `held_windows_enabled` with default `false`, and
   `gameplay_variant` with default `B`. Leave the switch off until there is
   enough traffic for the test to conclude — `docs/testing-plan.md` has the
   arithmetic, and the short version is that a retention verdict needs
   thousands of installs, not hundreds. When it is time, it is two arms and a
   50/50 split, not three.
4. Build the plugins from `native/` and drop them into the export
   (`ios/plugins/` and `android/plugins/`).
5. Register `variant` as a custom user property in the Firebase console, and
   the custom event parameters above, or they will not appear in reports.

The Firebase SDKs add no splash screen of their own — that requirement is met
by not using any SDK that draws one, and there is nothing to switch off.

## Trying the variants without Firebase

`DEV` in the top-left corner of the title screen, debug builds only. The
**Gameplay variant** row forces A, B or C. Switching only takes effect between
runs: a player whose strip changed mid-run is not a clean data point for either
variant, and the code enforces that rather than trusting the tester.

## Tests

`tests/variants_check.gd` asserts the two are actually two different mechanics
— that B replaces the whole offer and C keeps the untaken windows. It checks
behaviour rather than wiring, because the difference is one line deep and
exactly the kind of thing a refactor removes by accident.

`tests/switch_check.gd` asserts C cannot reach a player while the switch is
off, including the case that matters most: a group saved from an earlier
session.

```
godot --headless --path . --script res://tests/variants_check.gd
```
