# Pipe Runner

Godot 4 port of the `docs/pipe-runner-v6.html` prototype. Spec: `docs/spec.html`.
GDScript, portrait, mobile renderer — per spec sections 01 and 13.

## Layout

```
scenes/     Main, Board, Cart, HUD, QueueBar, GameOver
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
| `pipe_queue.gd` | forced queue and the HOLD pocket (spec 09) |
| `input_handler.gd` | press-drag-release aiming (spec 07) |
| `game_state.gd` | autoload: best score and its ghost route, currency, daily result, settings |
| `upgrades.gd` | meta progression: catalogue, levels, prices (spec 11, P0) |
| `skins.gd` | which LocationSkin is in effect |
| `safe_area.gd` | notch insets, clamped and mobile-only |
| `board_layer.gd` | splits Board's drawing into a slow and a fast layer |
| `main_menu.gd`, `game_over.gd`, `hud.gd`, `queue_bar.gd`, `fx.gd`, `screen_fx.gd`, `background.gd` | presentation |

## Locations

A location is a look, not a ruleset. `resources/location_skin.gd` holds every
colour the game draws procedurally — board, track, pickups, the cart, feedback
— and `resources/skins/NeonNeutral.tres` is the one that ships. Add a `.tres`,
hand it to `Main.apply_skin()`, and the same rules, generation and events play
out in a different palette. Nothing else needs to change.

`Skins` is a plain global class rather than an autoload, so scripts that read a
skin compile standalone for the headless tools.

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
godot --headless --path . --script res://tests/rules_check.gd    # 49 rule checks
godot --headless --path . --script res://tests/headless_run.gd   # bot plays 5 runs
godot --path . --resolution 720x1280 --script res://tests/perf_check.gd
```

`tests/screenshot.gd` renders a run and writes PNGs to `$SHOT_DIR`;
`tests/screenshot_ui.gd` does the same for the menu panels.

## Rendering notes

Board drawing is split in two. The terrain layer (grid, rocks, pipes) culls to
the visible rows and only redraws when the board or that row window changes —
roughly twice a second. The live layer (crystals, ghost, frontier ring) redraws
every frame. That keeps a 400-pipe board at ~590 draw calls and about 0.1 ms of
script time per frame.

## Not yet built

- **Biomes** (spec 11, P1) — deliberately skipped; locations are handled by the
  skin system above, which carries no gameplay change.
- **Continue for an ad**, **rotating quests** (spec 11, P2).
- **Export presets** (spec 13) — no `export_presets.cfg` yet, so the four
  acceptance items that need a device build are still open.
- The daily challenge is local only. A shared leaderboard needs a backend.
- No audio.
