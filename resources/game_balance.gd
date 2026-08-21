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
@export var fuel_crystal: float = 34.0
## Extra fuel per crystal, scaled by combo and capped.
@export var fuel_combo_bonus: float = 2.0
@export var fuel_combo_bonus_cap: float = 14.0
## Penalty for dropping a pipe on top of an unused one.
@export var fuel_replace: float = 7.0
## Cells travelled before fuel starts draining.
@export var grace_cells: int = 16

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

@export_group("Queue")
## How many upcoming pipes the player can see (spec: four are shown ahead).
@export var queue_preview: int = 4

@export_group("Feel")
@export var haptics_place_ms: int = 35
@export var haptics_crystal_ms: int = 80
@export var haptics_death_ms: int = 250
