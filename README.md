# Pipe Runner

Godot 4 port of the `docs/pipe-runner-v6.html` prototype. Spec: `docs/spec.html`.
GDScript, portrait, mobile renderer — per spec sections 01 and 13.

## Layout

```
scenes/     Main, Board, Cart, HUD, OfferBar, GameOver
scripts/    game logic (see below)
resources/  GameBalance.tres — every tunable number, editable without a rebuild
resources/i18n/  strings.csv — the ru/en catalogue
web/        index.html — the custom shell for the web export
tools/      serve_web.py and the asset generators
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
| `input_handler.gd` | press-drag-release aiming (spec 07), and the keys that pick |
| `key_scheme.gd` | which keys pick which slot, and what they are called |
| `game_state.gd` | autoload: best score and its ghost route, currency, daily result, settings |
| `upgrades.gd` | meta progression: catalogue, levels, prices (spec 11, P0) |
| `quests.gd` | the day's three goals: rolling, tracking, paying out (spec 11, P2) |
| `skins.gd` | which LocationSkin is in effect |
| `yandex_sdk.gd` | autoload: the platform bridge and the whole ad policy |
| `fonts.gd` | chains a Cyrillic fallback onto the game's face |
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
godot --headless --path . --script res://tests/rules_check.gd    # 281 rule checks
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

## Building for the web (Yandex Games)

```sh
godot --headless --path . --export-release "Web" build/web/index.html
python3 tools/serve_web.py 4187          # http://127.0.0.1:4187
(cd build/web && zip -r -9 ../piperunner-web.zip .)   # what the console takes
```

`python3 -m http.server` is not enough: it serves `.wasm` as
`application/octet-stream` and the streaming compiler refuses it, leaving a
blank canvas and one console line. `tools/serve_web.py` sets the MIME types and
nothing else — in particular it does **not** send the cross-origin isolation
headers, because the platform does not either, and a build that only works
isolated would pass locally and fail there.

For the same reason the preset has `variant/thread_support=false`: threads need
`SharedArrayBuffer`, which needs those headers.

`web/index.html` is the custom shell. It carries the platform's requirements —
no context menu, no text selection, no page scroll, arrow keys swallowed so the
page does not scroll under a player using them — and the `window.YaBridge` shim
the game talks to.

**The shell sizes the canvas, not the engine** (`canvas_resize_policy=0`, and
`fitCanvas` in the shell). Neither of the engine's own policies fits a portrait
game on a desktop:

- *Project* pins the canvas to the project's 720×1280 and then divides by the
  pixel ratio, so on a retina display the game sat in a 360×640 box in the
  middle of a 1710×825 window — most of the screen was surround.
- *Adaptive* fills the window, and the layout derives one cell from the
  viewport width, so a wide window gives six enormous cells and three rows.

`fitCanvas` takes the largest 9:16 box the window holds and sets the style size
and the framebuffer together — the second at the display's real density, or the
game renders soft. On the same window that is 464×825 backed by 928×1650.

What is left over is painted rather than left black: the game's own night sky,
the faint vertical shafts the menu draws over its board, and a vignette. A
portrait game on a wide desktop always has a surround; the only question is
whether it looks like one.

The SDK is loaded with a five-second deadline. If it stalls or fails, the game
starts anyway — no ads, no cloud saves, still playable.

### What the platform gets

| Requirement | Where |
| --- | --- |
| `LoadingAPI.ready` once the menu is drawn | `Main._announce_ready` |
| `GameplayAPI.start` / `.stop` around live play | `Main.start_run`, `_die`, `_show_menu` |
| Fullscreen ad, no oftener than 60 s | `Yandex.show_interstitial` |
| Rewarded video, opt-in, for the continue | `Main._request_continue` |
| Silence and stillness behind an ad | `Yandex._enter_ad` / `_leave_ad` |
| Progress on the player's account | `GameState.to_dict`, `Yandex.save_cloud` |
| Russian | `resources/i18n/strings.csv` |

Ads are on a counting rule: a fullscreen ad on every second death, never inside
the platform's cooldown, and never on a death whose continue was already paid
for with a rewarded video. `Yandex.note_death` owns it, and `rules_check` drives
it against a stand-in bridge — the counting is the part that goes wrong quietly.

The continue is the same one the phone builds have; on the platform it is
gated behind the video, and off it, it is simply granted, so the flow past that
point is one flow. Which deaths are worth offering it on has not changed —
`GameBalance.continue_*`, unchanged from the phone tuning.

## Controls

A finger presses, drags and releases: the shape lands where the finger lifted.
A mouse is the same gesture with a shorter drag, so the web build places with a
click and previews on hover.

Choosing which shape to place is separate from placing it — choosing is free
and repeatable, placing spends the turn — so on a keyboard the two split across
two hands. One key per slot, `Q W E`, `A S D`, the arrows or the digits,
switched under **SETUP → Pick shape with**. The digits work whatever is chosen.
The strip prints the live scheme onto the slots, which is the only explanation
that reliably arrives; the phone builds draw no caps and show no setting.

`KeyScheme` holds the tables, `GameState.key_scheme` remembers the choice, and
both `InputHandler` and `OfferBar` are handed it rather than reading it — they
carry a `class_name`, so they are compiled before the autoloads exist. Same
reason `Skins` is a plain class.

## Languages

Russian and English, as a CSV that Godot imports into two `.translation` files
(`resources/i18n/strings.csv`). Keys are the English source text, so Control
nodes translate themselves and only code-built strings need `tr()`.

The locale comes from the platform (`environment.i18n.lang`), which knows which
catalogue the player opened the game from; off the platform Godot's own default
— the system locale — is left alone.

Chakra Petch has no Cyrillic, so Russian drew as boxes. `Fonts.install_fallbacks`
chains Godot's bundled font onto it: the game keeps its face for everything it
can draw and falls through for the rest. It goes the other way too — the
bundled font has no arrows, which is what the keyboard hints are drawn with —
so everything that draws text by hand asks `Fonts.face()` rather than reaching
for `ThemeDB.fallback_font`.

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
- **On-device acceptance** (spec 13) — the iOS preset exports an Xcode project
  (`build/ios/`), but the four acceptance items that need a run on real
  hardware are still open.
- The daily challenge is local only. A shared leaderboard needs a backend —
  the platform has one (`ysdk.getLeaderboards`) and nothing is wired to it yet.
- No sticky banner. The platform's `adv.showBannerAdv` would pay, but it draws
  over the canvas and the board runs to the bottom edge; it needs a layout
  decision, not just the call.
- No audio, so the mute the platform requires on focus loss is a no-op that is
  in place for when there is.
