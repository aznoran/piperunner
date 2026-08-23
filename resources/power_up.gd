## A power-up: something the player spends mid-run, not something that quietly
## makes every run easier.
##
## This replaces the old upgrades, and the difference is the point. An upgrade
## was a number that went up once and then sat there — a bigger tank made every
## run longer and no run more interesting, and the player stopped noticing it
## by the third attempt. A power-up is a decision: you have three of them, the
## cart is about to derail, and you either spend one now or find out whether
## you needed to.
##
## Two things are bought separately, and they are not the same thing:
##
##   charges   how many you have. Spent, and bought again.
##   level     how strong each one is. Bought once, and kept.
##
## Levelling is what the old shop was for, and it survives here because it is
## attached to something the player chooses to use. Five cells of track laid
## for you is a rescue; six is a better one, and you will know which you have
## because you were watching when it fired.
class_name PowerUp
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
## What it does, in the player's terms rather than the code's.
@export var description: String = ""
## Short label for the button on the run screen, where there is room for very
## little.
@export var short_name: String = ""

## What one charge costs, in crystals.
@export var charge_cost: int = 20
## Charges the player starts a fresh save with, so the first run can show what
## these are without a shop trip.
@export var starting_charges: int = 2

## The effect at level one, and what each level after adds. Cells for the one
## that lays track, seconds for the one that stops the cart.
@export var base_value: float = 5.0
@export var step: float = 1.0
## What each level up costs. The length of this is how many levels there are.
@export var costs: PackedInt32Array = PackedInt32Array()
## The unit `value_at` is in, for the shop row.
@export var unit: String = ""


## Levels above the first. A power-up with no costs listed is bought once and
## never improved, which is a legitimate thing for one to be.
func max_level() -> int:
	return costs.size()


func cost_at(level: int) -> int:
	if level < 0 or level >= costs.size():
		return -1
	return costs[level]


## The effect at a given level. Level zero is the power-up as first owned.
func value_at(level: int) -> float:
	return base_value + step * float(level)
