## Autoload. Everything that outlives a run: best score, crystal currency,
## settings. Saved with ConfigFile under user:// (spec section 12).
extends Node

const SAVE_PATH := "user://piperunner.cfg"

signal best_changed(value: int)

var best: int = 0
## Furthest row ever reached. Distance and score are different things — a run
## can score well on crystals without climbing far — so the board's finish
## line tracks this one, not `best`.
var best_distance: int = 0
## Crystals banked across runs — the currency for meta upgrades (spec 11, P0).
var crystals: int = 0
var haptics_enabled: bool = true
## Date string of the last daily challenge played, and the score on it.
var daily_date: String = ""
var daily_best: int = 0
## Date the current quest set was rolled for, and the set itself: one entry per
## quest with id, target, progress and whether the reward has been taken.
var quest_date: String = ""
var quests: Array = []

## Purchased upgrades, keyed by id. Empty until the meta layer lands.
var upgrades: Dictionary = {}


func _ready() -> void:
	load_game()


func load_game() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	best = config.get_value("progress", "best", 0)
	best_distance = config.get_value("progress", "best_distance", 0)
	crystals = config.get_value("progress", "crystals", 0)
	upgrades = config.get_value("progress", "upgrades", {})
	daily_date = config.get_value("progress", "daily_date", "")
	daily_best = config.get_value("progress", "daily_best", 0)
	quest_date = config.get_value("progress", "quest_date", "")
	quests = config.get_value("progress", "quests", [])
	haptics_enabled = config.get_value("settings", "haptics", true)


func save_game() -> void:
	var config := ConfigFile.new()
	config.set_value("progress", "best", best)
	config.set_value("progress", "best_distance", best_distance)
	config.set_value("progress", "crystals", crystals)
	config.set_value("progress", "upgrades", upgrades)
	config.set_value("progress", "daily_date", daily_date)
	config.set_value("progress", "daily_best", daily_best)
	config.set_value("progress", "quest_date", quest_date)
	config.set_value("progress", "quests", quests)
	config.set_value("settings", "haptics", haptics_enabled)
	config.save(SAVE_PATH)


## Returns true when this run beat the score record.
func submit_score(score: int) -> bool:
	if score <= best:
		save_game()
		return false
	best = score
	best_changed.emit(best)
	save_game()
	return true


## Returns true when this run climbed further than any before it.
func submit_distance(distance: int) -> bool:
	if distance <= best_distance:
		save_game()
		return false
	best_distance = distance
	save_game()
	return true


## Today's date, the key for the daily challenge.
func today() -> String:
	return Time.get_date_string_from_system()


## Seed for today's challenge. Everyone playing on the same date gets the same
## map (spec section 11, P1) — which is why generation never touches the global
## RNG.
func daily_seed() -> int:
	return ("piperunner-" + today()).hash()


## Best score on today's challenge, 0 if it has not been played yet.
func daily_result() -> int:
	return daily_best if daily_date == today() else 0


## Returns true when this beat today's result.
func submit_daily(score: int) -> bool:
	if daily_date != today():
		daily_date = today()
		daily_best = 0
	if score <= daily_best:
		save_game()
		return false
	daily_best = score
	save_game()
	return true


func bank_crystals(count: int) -> void:
	crystals += count


## Single funnel for haptics so a settings toggle can kill them all
## (spec section 13).
func vibrate(milliseconds: int) -> void:
	if not haptics_enabled:
		return
	Input.vibrate_handheld(milliseconds)
