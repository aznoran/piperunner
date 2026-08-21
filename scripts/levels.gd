## The story run: a linear chain of stations, each an ordinary run on a fixed
## map with a finish condition.
##
## Progress is a single number — how many are cleared — because the chain is
## linear. That keeps the save file honest and makes "what is next" a lookup
## rather than a search.
class_name Levels
extends RefCounted

const FOLDER := "res://resources/levels"

static var _catalogue: Array[Level] = []


static func catalogue() -> Array[Level]:
	if not _catalogue.is_empty():
		return _catalogue
	var names := DirAccess.get_files_at(FOLDER)
	names.sort()
	for name: String in names:
		if not name.ends_with(".tres"):
			continue
		var level: Level = load("%s/%s" % [FOLDER, name])
		if level != null:
			_catalogue.append(level)
	_catalogue.sort_custom(func(a: Level, b: Level) -> bool: return a.number < b.number)
	return _catalogue


static func count() -> int:
	return catalogue().size()


static func find(number: int) -> Level:
	for level in catalogue():
		if level.number == number:
			return level
	return null


## The station the player is on: the first one not yet cleared, or the last
## one once the chain is finished.
static func current(state: Node) -> Level:
	var next: int = mini(state.levels_cleared + 1, count())
	return find(maxi(next, 1))


static func is_cleared(state: Node, number: int) -> bool:
	return number <= state.levels_cleared


static func is_unlocked(state: Node, number: int) -> bool:
	return number <= state.levels_cleared + 1


static func all_cleared(state: Node) -> bool:
	return state.levels_cleared >= count()


## Records a clear and pays out, once. Replaying a cleared station is allowed
## but pays nothing — otherwise the easiest one becomes a crystal faucet.
static func clear(state: Node, number: int) -> int:
	var level := find(number)
	if level == null or number <= state.levels_cleared:
		return 0
	state.levels_cleared = number
	state.crystals += level.reward
	state.save_game()
	return level.reward


## Seed for a station's map. Fixed, so a level is the same board every attempt
## — you are learning one map, not rerolling until it is easy.
static func seed_for(level: Level) -> int:
	return ("piperunner-level-%d-%d" % [level.number, level.seed_salt]).hash()


## How far a finished or in-progress run has got against the goal.
static func progress(level: Level, metrics: Dictionary) -> int:
	return int(metrics.get(String(level.goal_metric), 0))


static func is_met(level: Level, metrics: Dictionary) -> bool:
	return progress(level, metrics) >= level.goal_target
