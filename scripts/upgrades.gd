## Meta progression: the catalogue, what the player owns, and what it is worth.
## Spec section 11, P0.
##
## Levels live in GameState.upgrades keyed by id, so the save file stays
## readable and an upgrade can be retuned without migrating anything.
class_name Upgrades
extends RefCounted

## Order here is the order in the shop.
const CATALOGUE_PATHS := [
	"res://resources/upgrades/tank.tres",
	"res://resources/upgrades/preview.tres",
	"res://resources/upgrades/runway.tres",
	"res://resources/upgrades/magnet.tres",
]

static var _catalogue: Array[Upgrade] = []


static func catalogue() -> Array[Upgrade]:
	if _catalogue.is_empty():
		for path: String in CATALOGUE_PATHS:
			var upgrade: Upgrade = load(path)
			if upgrade != null:
				_catalogue.append(upgrade)
	return _catalogue


static func find(id: StringName) -> Upgrade:
	for upgrade in catalogue():
		if upgrade.id == id:
			return upgrade
	return null


static func level(id: StringName, state: Node) -> int:
	return int(state.upgrades.get(String(id), 0))


## Total effect of everything bought so far, for use on the balance sheet.
static func bonus(id: StringName, state: Node) -> float:
	var upgrade := find(id)
	if upgrade == null:
		return 0.0
	return upgrade.step * level(id, state)


## Crystals needed for the next level, or -1 when maxed.
static func next_cost(id: StringName, state: Node) -> int:
	var upgrade := find(id)
	if upgrade == null:
		return -1
	return upgrade.cost_at(level(id, state))


static func can_afford(id: StringName, state: Node) -> bool:
	var cost := next_cost(id, state)
	return cost >= 0 and state.crystals >= cost


## Spends the crystals and banks the level. Returns false if it was not
## affordable or already maxed.
static func buy(id: StringName, state: Node) -> bool:
	if not can_afford(id, state):
		return false
	state.crystals -= next_cost(id, state)
	state.upgrades[String(id)] = level(id, state) + 1
	state.save_game()
	return true
