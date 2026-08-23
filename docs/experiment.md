# A/B/C test: how the player gets their next pipe

Three ways of handing the player a shape, measured against each other. The
question is whether choosing the shape — and whether being allowed to *keep*
the shapes you did not choose — is worth more than the forced queue the game
shipped with.

## The three variants

| | Strip | Taking a shape | Class |
|---|---|---|---|
| **A** baseline | one piece in hand, preview behind it, a HOLD pocket | queue advances, a new shape joins the back | `QueueSource` |
| **B** offer | three shapes, all equal | **all three** are replaced | `OfferSource` |
| **C** held offer | three shapes, all equal | **only the one taken** is replaced | `HeldOfferSource` |

A is the mechanic as it shipped, assistance and all. B and C are the branch's
offer, and differ from each other by one method.

### What "held" means in C

In B the offer is spent whole: nothing on the strip outlives the turn it was
dealt on. In C a window refills only when the player takes from *that* window;
the other two keep their shapes, turn after turn, until the player finally
takes from them.

That buys the player a stash they did not pay for — an awkward shape can sit in
its window until the joint that wants it comes round, which is A's pocket
generalised to three slots and made free. It costs them a strip that goes
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
Experiment.make_source() ─→ BlockSource ─┬─ QueueSource      (A) ─→ QueueBar
                                         ├─ OfferSource      (B) ─┬→ OfferBar
                                         └─ HeldOfferSource  (C) ─┘
```

Each variant also names the dealing rule it was designed around
(`make_dealer()`): A leans on `AssistDealer`, because a forced draw without a
thumb on the scale is a death sentence with no decision in it; B and C use
`RandomDealer`, because weighting three options only makes the choice quieter.

A variant owns its own strip, which is why `attach()` takes both bars: it shows
the one its mechanic is built around and hides the other. Input needs no
variant knowledge at all — the strip publishes tap targets as an array of
rects, and A's array happens to hold exactly one, the pocket.

## Assignment

`Experiment` (autoload) resolves the group from Remote Config key
`gameplay_variant`, one of `A`, `B`, `C`.

Three rules keep the data honest, and each is enforced in code:

- **Assign once.** The first answer is written to `user://experiment.cfg` and
  is the answer from then on. A player who switched variants mid-test belongs
  to neither group.
- **Offline keeps its group.** The A fallback is only for a player who has
  never been assigned. Falling back to A for an offline C player would file
  their sessions under A and poison the baseline.
- **Debug overrides are marked.** Forcing a variant from the bench does not
  persist and does not count as an assignment; every event it produces carries
  `debug_override: true`.

Firebase buckets by installation ID, so a player stays in their group across
sessions without the game rolling anything itself.

**Until Remote Config is live, every device falls back to A.** B and C are
reachable only from the debug bench.

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

**Done and testable now:** all three variants, the assignment logic with its
fallback and persistence, every event above, the user property, and the debug
bench. The GDScript side runs on desktop with no SDK at all — events print to
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
3. In Remote Config, add `gameplay_variant` with default `A`, and a rollout
   splitting **34 / 33 / 33** across A / B / C.
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

`tests/variants_check.gd` asserts the three are actually three different
mechanics — that B replaces the whole offer and C keeps the untaken windows.
It checks behaviour rather than wiring, because the B/C difference is one line
deep and exactly the kind of thing a refactor removes by accident.

```
godot --headless --path . --script res://tests/variants_check.gd
```
