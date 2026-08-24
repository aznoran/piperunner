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
## Display name of the chosen location skin. Empty means the default.
var location: String = ""
## Which of the location's cart looks the player picked.
var cart_variant: int = 0
## Date string of the last daily challenge played, and the score on it.
var daily_date: String = ""
var daily_best: int = 0
## Date the current quest set was rolled for, and the set itself: one entry per
## quest with id, target, progress and whether the reward has been taken.
var quest_date: String = ""
var quests: Array = []
## Stations of the story run cleared so far. The chain is linear, so one
## number says everything about where the player is.
var levels_cleared: int = 0
## Runs finished, ever. Drives how much the dealer may help.
var runs_played: int = 0
## Consecutive runs that fell well short of the player's own record.
var slump_streak: int = 0
## Unix time of the last continue offer, so they cannot stack up.
var last_continue: float = 0.0

## Purchased upgrades, keyed by id. Empty until the meta layer lands.
var upgrades: Dictionary = {}
## Power-ups: how strong each is, and how many are in hand. Two dictionaries
## rather than one because they are bought separately and mean different
## things — a level is kept and a charge is spent.
var power_levels: Dictionary = {}
var power_charges: Dictionary = {}
## The last handful of distances, newest last. Kept so the game can put a
## checkpoint where *this* player tends to come unstuck rather than where the
## average one does — the two are rarely the same number.
var recent_runs: Array = []


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
	power_levels = config.get_value("progress", "power_levels", {})
	power_charges = config.get_value("progress", "power_charges", {})
	recent_runs = config.get_value("progress", "recent_runs", [])
	daily_date = config.get_value("progress", "daily_date", "")
	daily_best = config.get_value("progress", "daily_best", 0)
	quest_date = config.get_value("progress", "quest_date", "")
	quests = config.get_value("progress", "quests", [])
	levels_cleared = config.get_value("progress", "levels_cleared", 0)
	runs_played = config.get_value("progress", "runs_played", 0)
	slump_streak = config.get_value("progress", "slump_streak", 0)
	last_continue = config.get_value("progress", "last_continue", 0.0)
	haptics_enabled = config.get_value("settings", "haptics", true)
	location = config.get_value("settings", "location", "")
	cart_variant = config.get_value("settings", "cart_variant", 0)


func save_game() -> void:
	var config := ConfigFile.new()
	config.set_value("progress", "best", best)
	config.set_value("progress", "best_distance", best_distance)
	config.set_value("progress", "crystals", crystals)
	config.set_value("progress", "upgrades", upgrades)
	config.set_value("progress", "power_levels", power_levels)
	config.set_value("progress", "power_charges", power_charges)
	config.set_value("progress", "recent_runs", recent_runs)
	config.set_value("progress", "daily_date", daily_date)
	config.set_value("progress", "daily_best", daily_best)
	config.set_value("progress", "quest_date", quest_date)
	config.set_value("progress", "quests", quests)
	config.set_value("progress", "levels_cleared", levels_cleared)
	config.set_value("progress", "runs_played", runs_played)
	config.set_value("progress", "slump_streak", slump_streak)
	config.set_value("progress", "last_continue", last_continue)
	config.set_value("settings", "haptics", haptics_enabled)
	config.set_value("settings", "location", location)
	config.set_value("settings", "cart_variant", cart_variant)
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


## Files a finished run for the dealer's benefit: a run that fell well short of
## the player's own record counts towards a slump, a decent one clears it.
## Runs remembered for the checkpoint placement. Long enough to be steady,
## short enough to follow a player who is getting better.
const RECENT_RUNS := 8


## How far this player usually gets, from their own last few runs.
##
## Zero until there are a few to go on, which is the caller's cue to use the
## designed default instead of a number made of one lucky attempt.
func usual_reach() -> int:
	if recent_runs.size() < 3:
		return 0
	var total := 0
	for distance: int in recent_runs:
		total += distance
	return int(round(float(total) / float(recent_runs.size())))


func note_run(distance: int) -> void:
	recent_runs.append(distance)
	while recent_runs.size() > RECENT_RUNS:
		recent_runs.pop_front()
	runs_played += 1
	if best_distance > 0 and distance < best_distance * 0.6:
		slump_streak += 1
	elif best_distance == 0 or distance >= best_distance * 0.8:
		slump_streak = 0
	save_game()


func in_slump() -> bool:
	return slump_streak >= 3


func bank_crystals(count: int) -> void:
	crystals += count


## Single funnel for haptics so a settings toggle can kill them all
## (spec section 13). Amplitude is requested explicitly: the default leaves it
## to the platform, which on iOS can come out too faint to notice.
func vibrate(milliseconds: int) -> void:
	if not haptics_enabled:
		return
	Input.vibrate_handheld(milliseconds, 1.0)
