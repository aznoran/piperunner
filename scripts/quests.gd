## The day's three goals: rolling them, tracking them, paying them out.
## Spec section 11, P2.
##
## The roll is seeded from the date, so the set is stable for the whole day no
## matter how many times the menu is opened — and identical for every player,
## same as the daily run.
class_name Quests
extends RefCounted

const CATALOGUE_PATHS := [
	"res://resources/quests/gather.tres",
	"res://resources/quests/distance.tres",
	"res://resources/quests/litter.tres",
	"res://resources/quests/points.tres",
	"res://resources/quests/chain.tres",
	"res://resources/quests/survive.tres",
]

## How many are active at once.
const DAILY_COUNT := 3

static var _catalogue: Array[Quest] = []


static func catalogue() -> Array[Quest]:
	if _catalogue.is_empty():
		for path: String in CATALOGUE_PATHS:
			var quest: Quest = load(path)
			if quest != null:
				_catalogue.append(quest)
	return _catalogue


static func find(id: StringName) -> Quest:
	for quest in catalogue():
		if quest.id == id:
			return quest
	return null


## Rolls a fresh set if the day has turned over. Safe to call any time.
static func ensure_today(state: Node) -> void:
	var today: String = state.today()
	if state.quest_date == today and not state.quests.is_empty():
		return
	state.quest_date = today
	state.quests = _roll(today)
	state.save_game()


## Three distinct quests with one target each, drawn from a date-seeded stream.
static func _roll(date: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = ("piperunner-quests-" + date).hash()

	var pool := catalogue().duplicate()
	var picked: Array = []
	for i in mini(DAILY_COUNT, pool.size()):
		var quest: Quest = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var target: int = quest.targets[rng.randi_range(0, quest.targets.size() - 1)]
		picked.append({
			"id": String(quest.id),
			"target": target,
			"progress": 0,
			"claimed": false,
		})
	return picked


## Folds a finished run into the day's progress. `metrics` maps metric name to
## the value this run produced. Returns the quests that just became complete.
static func report(state: Node, metrics: Dictionary) -> Array:
	ensure_today(state)
	var newly_done: Array = []

	for entry: Dictionary in state.quests:
		var quest := find(StringName(entry["id"]))
		if quest == null or entry["claimed"]:
			continue
		var was_done: bool = int(entry["progress"]) >= int(entry["target"])
		var value: int = int(metrics.get(String(quest.metric), 0))

		if quest.single_run:
			# "in one run": keep the best attempt rather than the running total.
			entry["progress"] = maxi(int(entry["progress"]), value)
		else:
			entry["progress"] = int(entry["progress"]) + value

		if not was_done and int(entry["progress"]) >= int(entry["target"]):
			newly_done.append(entry)

	state.save_game()
	return newly_done


static func is_complete(entry: Dictionary) -> bool:
	return int(entry["progress"]) >= int(entry["target"])


## Pays out a finished quest. Returns the crystals granted, or 0 if it was not
## claimable.
static func claim(state: Node, id: String) -> int:
	for entry: Dictionary in state.quests:
		if entry["id"] != id or entry["claimed"] or not is_complete(entry):
			continue
		var quest := find(StringName(id))
		if quest == null:
			return 0
		entry["claimed"] = true
		state.crystals += quest.reward
		state.save_game()
		return quest.reward
	return 0


## How many of today's quests are done, and how many there are.
static func tally(state: Node) -> Vector2i:
	ensure_today(state)
	var done := 0
	for entry: Dictionary in state.quests:
		if is_complete(entry):
			done += 1
	return Vector2i(done, state.quests.size())


## True when something is finished and waiting to be collected.
static func has_claimable(state: Node) -> bool:
	for entry: Dictionary in state.quests:
		if is_complete(entry) and not entry["claimed"]:
			return true
	return false
