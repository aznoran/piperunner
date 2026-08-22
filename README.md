# Pipe Runner

Godot 4 port of the `docs/pipe-runner-v6.html` prototype. Spec: `docs/spec.html`.
GDScript, portrait, mobile renderer — per spec sections 01 and 13.

## Layout

```
scenes/     Main, Board, Cart, HUD, OfferBar, GameOver
scripts/    game logic (see below)
resources/  GameBalance.tres — every tunable number, editable without a rebuild
tests/      headless checks
docs/       the spec and the reference prototype
```

| Script | Role |
| --- | --- |
| `main.gd` | run state machine, score, fuel, camera, wiring |
| `board.gd` | pipe dictionary, generation, placement rules, rendering |
| `cart.gd` | position, entry side, fractional motion |
| `pipe_defs.gd` | pipe geometry and the exit-side rule (spec 04) |
| `pipe_offer.gd` | the shapes on offer and choosing between them |
| `pipe_dealer.gd` | what fills an offer: the rule seam |
| `random_dealer.gd` | the rule in force — distinct shapes, drawn evenly |
| `input_handler.gd` | press-drag-release aiming (spec 07) |
| `game_state.gd` | autoload: best score and its ghost route, currency, daily result, settings |
| `upgrades.gd` | meta progression: catalogue, levels, prices (spec 11, P0) |
| `quests.gd` | the day's three goals: rolling, tracking, paying out (spec 11, P2) |
| `skins.gd` | which LocationSkin is in effect |
| `safe_area.gd` | notch insets, clamped and mobile-only |
| `board_layer.gd` | splits Board's drawing into a slow and a fast layer |
| `main_menu.gd`, `game_over.gd`, `hud.gd`, `offer_bar.gd`, `fx.gd`, `screen_fx.gd`, `background.gd` | presentation |

## Locations

A location is a look, not a ruleset. `resources/location_skin.gd` holds every
colour the game draws procedurally — board, track, pickups, the cart, feedback
— and `resources/skins/NeonNeutral.tres` is the one that ships. Add a `.tres`,
hand it to `Main.apply_skin()`, and the same rules, generation and events play
out in a different palette. Nothing else needs to change.

`Skins` is a plain global class rather than an autoload, so scripts that read a
skin compile standalone for the headless tools.

Two locations ship. **Neon Neutral** is drawn entirely from colour. **Forest**
adds sprites: a skin may set `rock_texture`, `pickup_texture` and a list of
`cart_variants`, and anything left null falls back to the drawn shape — so a
location can be pure colour, pure art, or a mix. `pixel_art` switches texture
filtering to nearest so pixel tiles do not turn to mush at cell size.

Forest art is Kenney's [Pixel Platformer](https://kenney.nl/assets/pixel-platformer),
CC0. Which tiles were taken and what for is recorded in
`art/skins/forest/CREDITS.txt`.

The menu chrome repaints from the skin at runtime (`MainMenu.paint`), because
the scene file can only hold one hard-coded palette.

## Dealing pipes

The player is not handed a pipe, they are handed a choice: three shapes on the
strip, tap one, place it. Placing spends the whole offer — the two not taken go
with it — so nothing on screen belongs to a later turn and there is no preview
to plan against. Choosing costs nothing and can be undone until the pipe lands.

Which shapes go into an offer is a rule object, `PipeDealer`. The one in force
is `RandomDealer`: distinct shapes, drawn evenly, ignoring everything about the
run. To add a rule, subclass `PipeDealer`, override `fill()`, and change the one
line in `main.gd` that names the rule. Every deal is handed a context dictionary
— the joint the cart is heading for, track ahead, fuel, runs played, whether the
player is in a slump — so a rule that starts caring about the run needs no change
to the signature or to any call site. Spec section 04's drop weights stay in
`PipeDefs` for a rule that wants them.

## Meta progression

Crystals collected during a run are banked on death and spent in the menu shop.
The four upgrades live in `resources/upgrades/` as one `.tres` each — id, name,
blurb, per-level costs, and what a level is worth — so retuning or adding one
touches no code. They are folded into a **copy** of `GameBalance.tres` before
each run, leaving the tuning sheet on disk as the untouched baseline.

## Running

Requires a **standard** (non-.NET) Godot 4.7 build — spec section 13. It lives
at `/Applications/Godot.app`; `Godot_mono.app` is the .NET build and is not what
this project exports with.

```sh
alias godot=/Applications/Godot.app/Contents/MacOS/Godot

godot --path . --resolution 450x800                              # play
godot --headless --path . --script res://tests/rules_check.gd    # 242 rule checks
godot --headless --path . --script res://tests/headless_run.gd   # bot plays 5 runs
godot --path . --resolution 720x1280 --script res://tests/perf_check.gd
```

`tests/screenshot.gd` renders a run and writes PNGs to `$SHOT_DIR`;
`tests/screenshot_ui.gd` does the same for the menu panels.

## Building for iOS

The `iOS` preset in `export_presets.cfg` exports an Xcode project rather than an
IPA (`export_project_only=true`), so signing happens in Xcode, not here.

```sh
godot --headless --path . --export-release "iOS"
open build/ios/PipeRunner.xcodeproj
```

Needs the matching export templates installed — the editor's *Manage Export
Templates* fetches them, and nothing exports without them.

**The simulator does not work on an Apple Silicon Mac.** Godot 4.7.2's iOS
templates ship a simulator `libgodot.a` built for x86_64 only, while the
xcframework's `Info.plist` advertises `arm64` alongside it — both in the debug
and the release template. Xcode links the one slice it finds, then fails on
`Undefined symbols for architecture arm64: _main`. Forcing `-arch x86_64` links
and builds, but an arm64 simulator refuses to install the result. Test on a
device until the templates carry an arm64 simulator slice.

## Rendering notes

Board drawing is split in two. The terrain layer (grid, rocks, pipes) culls to
the visible rows and only redraws when the board or that row window changes —
roughly twice a second. The live layer (crystals, ghost, frontier ring) redraws
every frame. That keeps a 400-pipe board at ~590 draw calls and about 0.1 ms of
script time per frame.

## Daily goals

Three goals a day, rolled from a date-seeded stream so the set is stable all
day and identical for every player — the same trick as the daily run. They pay
crystals into the same wallet the shop spends from.

Each goal is a `.tres` in `resources/quests/`: a metric, a spread of candidate
targets and a payout. Goals phrased "in one run" set `single_run`, which keeps
the best single attempt instead of summing across the day.

## Not yet built

- **Biomes** (spec 11, P1) — deliberately skipped; locations are handled by the
  skin system above, which carries no gameplay change.
- **Continue for an ad** (spec 11, P2) — deferred; it does nothing useful
  until an ad SDK is wired in.
- **On-device acceptance** (spec 13) — the iOS preset exports an Xcode project
  (`build/ios/`), but the four acceptance items that need a run on real
  hardware are still open.
- The daily challenge is local only. A shared leaderboard needs a backend.
- No audio.
