## Every tunable number lives here so balance can change without a rebuild.
## Spec section 10: "Все константы вынести в один ресурс GameBalance.tres".
class_name GameBalance
extends Resource

@export_group("Board")
## Spec section 03: 7 columns. Drop to 6 if players complain about misses —
## cells get 17% bigger.
@export var cols: int = 7
## Starting vertical pipes the cart is parked on.
@export var runway: int = 3
## Track drawn behind the cart, already run through. Purely scenery — it sits
## below the placement window, so it can never be built on — but it stops the
## rail from ending in mid-air under the cart.
@export var approach: int = 14
## Rows generated ahead of the cart.
@export var generate_ahead: int = 18

@export_group("Speed")
## Cells per second at the start of a run.
@export var start_speed: float = 0.68
## Speed added per point scored.
@export var speed_gain: float = 0.0032
@export var speed_cap: float = 2.3

@export_group("Fuel")
@export var fuel_max: float = 100.0
## Burned per cell travelled, once the grace period is over.
@export var fuel_per_cell: float = 3.6
## Burned per second the cart is rolling, from the first second — no grace.
## Without it the gauge sits full for the whole of a short run and the player
## never learns that fuel is a mechanic at all.
@export var fuel_per_second: float = 0.6
@export var fuel_crystal: float = 34.0
## Extra fuel per crystal, scaled by combo and capped.
@export var fuel_combo_bonus: float = 2.0
@export var fuel_combo_bonus_cap: float = 14.0
## Penalty for dropping a pipe on top of an unused one.
@export var fuel_replace: float = 7.0
## Cells travelled before fuel starts draining.
@export var grace_cells: int = 16

@export_group("Checkpoints")
## Gates on the track that give the speed back. The cart accelerates with the
## score and eventually outruns a human; a checkpoint is where that is undone.
##
## They are routed through, exactly as crystals are — driven past, they do
## nothing, and that is the player's own fault. Which is what makes them a
## decision rather than a gift: the track has to be steered into one, and
## steering costs cells and fuel.
@export var checkpoints_on: bool = true
## Rows between one gate and the next. Roughly how far a player gets without
## trouble, so the gate arrives about when the speed starts to bite.
@export var checkpoint_gap: int = 30
## How far ahead of trouble the first one lands. Placed where this player
## usually dies, less this, so the gate is reached with time to spare rather
## than exactly as the run falls apart.
@export var checkpoint_lead: int = 10
## Never closer to the start than this, however short their runs have been —
## a gate in the first few rows would be met before the speed is a problem.
@export var checkpoint_first_min: int = 18
## How many cells wide a gate is.
##
## One cell in a board seven wide is nearly always off the route, so taking it
## meant a detour, and a detour costs cells and fuel — which showed up as the
## long runs getting shorter while the short ones got longer. A gate a few
## cells across is cheap to steer into and still possible to miss, which is the
## bargain it is supposed to be: recommended, not automatic.
@export var checkpoint_width: int = 3
## How much of the speed gained so far a gate hands back, 0..1. At 1.0 the
## cart returns to its starting pace and the run restarts in all but name; at
## 0 the gate is scenery.
@export_range(0.0, 1.0, 0.05) var checkpoint_relief: float = 0.55

@export_group("Scoring")
## Points per crystal = crystal_points * min(combo, crystal_combo_cap).
@export var crystal_points: int = 10
@export var crystal_combo_cap: int = 5

@export_group("Placement")
## How far into the next cell the cart must be before that cell locks, 0..1.
## 0.5 means the cell is off limits once the cart is visibly inside it; 1.0
## restores the prototype, where you could still slot a pipe in on the last
## tick before arrival.
@export_range(0.0, 1.0, 0.05) var place_lockout_progress: float = 0.5
## Spec section 08: the litter zone. Rows outside
## [max_row - place_below, max_row + place_above] are off limits.
@export var place_above: int = 22
@export var place_below: int = 6

@export_group("Generation")
## No rocks before this row.
@export var rock_start_row: int = 16
@export var rock_density_base: float = 0.05
@export var rock_density_gain: float = 0.0012
@export var rock_density_cap: float = 0.14
## Rings of cells either side of the cart's path that a crystal is picked up
## from. It used to be an upgrade; it is now simply how the cart works, because
## a cart that only takes what it drives exactly through reads as fussy rather
## than as demanding.
@export var magnet_reach: int = 1
## A crystal every crystal_gap_min..crystal_gap_max rows.
@export var crystal_gap_min: int = 2
@export var crystal_gap_max: int = 4

@export_group("Camera")
## Where the cart sits vertically, as a fraction of screen height.
@export var camera_anchor: float = 0.72
## Spec section 06: cam_y += (target - cam_y) * min(delta * follow, 1).
@export var camera_follow: float = 9.0
## Safety release so the cart can never leave the frame while a finger is down.
@export var camera_freeze_timeout: float = 1.6
## Seconds the camera takes to ease to a stop when a finger lands, and to ease
## back up when it lifts. Stopping dead reads as a stutter on a quick tap.
@export var camera_freeze_ramp: float = 0.18

@export_group("Offer")
## How many shapes the player chooses between each turn. Capped by the number
## of shapes that exist, since an offer never repeats one.
## How many shapes variant B and C put on the strip to choose between.
@export var offer_size: int = 3
@export_group("Dealer")
## How hard the dealing rules may lean on a player in trouble, by experience.
## Zero switches assistance off entirely and leaves the even draw of spec
## section 04.
@export var assist_max_new: float = 0.90
@export var assist_max_early: float = 0.65
@export var assist_max_veteran: float = 0.40
## Added while the player is in a slump, removed on a decent run.
@export var assist_slump_bonus: float = 0.20
## Runs before assistance steps down a tier.
@export var assist_runs_new: int = 3
@export var assist_runs_early: int = 10
## Multipliers applied to a shape's base weight at full assistance.
@export var assist_fit_gain: float = 3.0
@export var assist_miss_penalty: float = 0.6
## Below this fraction of a tank, or this many cells of built track ahead,
## the player counts as under pressure.
@export var assist_fuel_floor: float = 0.30
@export var assist_buffer_floor: int = 3

## How often the offer is guaranteed a shape that resumes the climb while the
## cart is travelling sideways, 0..1.
##
## This is parity rather than assistance, and the arithmetic says so.
##
## A crossroads goes straight through — entry D leaves by U, entry L leaves by
## R. So for a cart already climbing, *two* of the seven shapes keep it
## climbing: the vertical and the crossroads. For a cart turned sideways,
## exactly *one* gets it back to climbing: the elbow that turns up. In an offer
## of three drawn from seven that is
##
##     climbing on            2 of 7 -> 71.4% of offers hold one
##     resuming after a turn  1 of 7 -> 42.9%
##
## a gap of nearly thirty points, paid every time the player turns. It is not
## something anyone could see in the rules, and it is exactly what a turn feels
## like when it strands you.
##
## At 0.50 the sideways case lands back on 71.4% — the same odds as climbing
## on, no better. That is the default for a reason: anything above it is no
## longer evening things out but tilting them, and at 1.0 every turn would be
## handed its way out and the game would play itself.
##
## It only fires while the cart is already sideways, and it puts a shape on the
## strip rather than choosing the cell. Zero restores the raw 42.9%.
@export_range(0.0, 1.0, 0.05) var turn_relief: float = 0.5

@export_group("Praise")
## Seconds between praise messages. Praise devalues faster than anything else
## in the game, so this is the main defence.
@export var praise_cooldown: float = 1.2
## Most messages a single run may show.
@export var praise_run_cap: int = 12
## Chain length that earns the smallest praise at distance 0.
@export var praise_combo_base: int = 2
## Every this many cells, the chain bar rises by one — what was worth praising
## at the start is routine later.
@export var praise_combo_step: int = 25
## Pipes placed without an overwrite before the run is called clean.
@export var praise_clean_run: int = 12

@export_group("Continue")
## A death is worth offering a continue on when it lands near the record, near
## a station's goal, or after a long run.
@export var continue_record_ratio: float = 0.65
@export var continue_goal_ratio: float = 0.70
@export var continue_min_distance: int = 18
## Seconds between offers, and the first run that may see one.
@export var continue_cooldown: float = 240.0
@export var continue_first_run: int = 3
## What a continue restores.
@export var continue_fuel_ratio: float = 0.60
@export var continue_rollback: int = 2

@export_group("Feel")
@export var haptics_place_ms: int = 35
@export var haptics_crystal_ms: int = 80
@export var haptics_death_ms: int = 250
