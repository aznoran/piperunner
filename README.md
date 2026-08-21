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
| `game_state.gd` | autoload: best score, currency, settings, haptics |
| `safe_area.gd` | notch insets, clamped and mobile-only |
| `board_layer.gd` | splits Board's drawing into a slow and a fast layer |
| `fx.gd`, `screen_fx.gd`, `hud.gd`, `queue_bar.gd`, `game_over.gd`, `palette.gd` | presentation |

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

`tests/screenshot.gd` renders a run and writes PNGs to `$SHOT_DIR`.

## Rendering notes

Board drawing is split in two. The terrain layer (grid, rocks, pipes) culls to
the visible rows and only redraws when the board or that row window changes —
roughly twice a second. The live layer (crystals, ghost, frontier ring) redraws
every frame. That keeps a 400-pipe board at ~590 draw calls and about 0.1 ms of
script time per frame.

## Not yet built

Everything in spec section 11 — meta upgrades, record ghost, biomes, daily
challenge, continue-for-ad, quests — plus the export presets in section 13.
