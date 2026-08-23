## The power-up catalogue, what the player owns of each, and what it is worth.
##
## Levels and charges both live in GameState, keyed by id, so the save stays
## readable and a power-up can be retuned without migrating anything. The
## paths are listed rather than scanned: DirAccess finds nothing in an exported
## build, where the files are .remap stubs, and a shop that is empty on a phone
## and full on a desktop is the worst kind of bug to be told about.
class_name PowerUps
extends RefCounted

## Order here is the order they appear, in the shop and on the run screen.
const CATALOGUE_PATHS := [
	"res://resources/powerups/autolay.tres",
	"res://resources/powerups/halt.tres",
]

static var _catalogue: Array[PowerUp] = []


static func catalogue() -> Array[PowerUp]:
	if _catalogue.is_empty():
		for path: String in CATALOGUE_PATHS:
			var power: PowerUp = load(path)
			if power != null:
				_catalogue.append(power)
	return _catalogue


static func find(id: StringName) -> PowerUp:
	for power in catalogue():
		if power.id == id:
			return power
	return null


# --- what the player owns ------------------------------------------------

## Charges in hand. A save that has never seen this power-up starts with the
## handful it ships with, so the first run can show what it does.
static func charges(id: StringName, state: Node) -> int:
	var held: Dictionary = state.power_charges
	if held.has(String(id)):
		return int(held[String(id)])
	var power := find(id)
	return power.starting_charges if power != null else 0


static func level(id: StringName, state: Node) -> int:
	return int(state.power_levels.get(String(id), 0))


## What it does at the level owned — cells, or seconds.
static func value(id: StringName, state: Node) -> float:
	var power := find(id)
	if power == null:
		return 0.0
	return power.value_at(level(id, state))


## Spends one. Returns false when there is nothing to spend, which is the
## caller's cue to do nothing at all rather than to fire an empty power-up.
static func spend(id: StringName, state: Node) -> bool:
	var held := charges(id, state)
	if held <= 0:
		return false
	state.power_charges[String(id)] = held - 1
	state.save_game()
	return true


static func grant(id: StringName, state: Node, count: int = 1) -> void:
	state.power_charges[String(id)] = charges(id, state) + count
	state.save_game()


# --- the shop ------------------------------------------------------------

## Crystals for one more charge, or -1 when there is no such power-up.
static func charge_cost(id: StringName, state: Node) -> int:
	var power := find(id)
	if power == null:
		return -1
	# Levelling makes each charge stronger, so it makes each charge dearer.
	# Otherwise the cheapest way to a strong power-up would be to level it and
	# never pay for the strength.
	return power.charge_cost + power.charge_cost * level(id, state) / 2


static func upgrade_cost(id: StringName, state: Node) -> int:
	var power := find(id)
	if power == null:
		return -1
	return power.cost_at(level(id, state))


static func buy_charge(id: StringName, state: Node) -> bool:
	var price := charge_cost(id, state)
	if price < 0 or state.crystals < price:
		return false
	state.crystals -= price
	grant(id, state)
	return true


static func buy_upgrade(id: StringName, state: Node) -> bool:
	var price := upgrade_cost(id, state)
	if price < 0 or state.crystals < price:
		return false
	state.crystals -= price
	state.power_levels[String(id)] = level(id, state) + 1
	state.save_game()
	return true
