## Autoload. Everything that outlives a run: best score, crystal currency,
## settings. Saved with ConfigFile under user:// (spec section 12).
extends Node

const SAVE_PATH := "user://piperunner.cfg"

signal best_changed(value: int)
## Cloud progress arrived and replaced what was read off disk. Anything showing
## a number the player owns has to look again.
signal progress_reloaded()

var best: int = 0
## Furthest row ever reached. Distance and score are different things — a run
## can score well on crystals without climbing far — so the board's finish
## line tracks this one, not `best`.
var best_distance: int = 0
## Crystals banked across runs — the currency for meta upgrades (spec 11, P0).
var crystals: int = 0
var haptics_enabled: bool = true
## Which keyboard layout picks shapes off the strip — an index into
## KeyScheme.NAMES. Only ever consulted where there is a keyboard, so it costs
## the phone builds nothing to carry.
var key_scheme: int = KeyScheme.Id.QWE
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
	Yandex.cloud_loaded.connect(_on_cloud_loaded)
	Yandex.load_cloud()


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
	key_scheme = KeyScheme.clamp_id(config.get_value("settings", "key_scheme",
		KeyScheme.Id.QWE))
	location = config.get_value("settings", "location", "")
	cart_variant = config.get_value("settings", "cart_variant", 0)


## Writes to disk and queues the same picture to the player's cloud slot, so
## progress follows them off this browser. The cloud write is coalesced inside
## Yandex; this is called on every banked run and the platform rate-limits it.
func save_game() -> void:
	_write_disk()
	Yandex.save_cloud(to_dict())


func _write_disk() -> void:
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
	config.set_value("settings", "key_scheme", key_scheme)
	config.set_value("settings", "location", location)
	config.set_value("settings", "cart_variant", cart_variant)
	config.save(SAVE_PATH)


## Everything worth carrying between one browser and the next, flattened into
## one dictionary — the cloud stores JSON, which has no opinion about the
## ConfigFile's two sections. Settings travel with progress on purpose: a
## player who turned the vibration off did not mean "on this device only".
func to_dict() -> Dictionary:
	return {
		"best": best, "best_distance": best_distance, "crystals": crystals,
		"upgrades": upgrades, "power_levels": power_levels,
		"power_charges": power_charges, "recent_runs": recent_runs,
		"daily_date": daily_date, "daily_best": daily_best,
		"quest_date": quest_date, "quests": quests,
		"levels_cleared": levels_cleared, "runs_played": runs_played,
		"slump_streak": slump_streak, "last_continue": last_continue,
		"haptics": haptics_enabled, "location": location,
		"cart_variant": cart_variant, "key_scheme": key_scheme,
	}


## Cloud progress wins, but only when it is actually ahead.
##
## The two copies are not versioned and cannot be merged field by field without
## inventing a rule per field, so the question is which single copy to keep.
## Runs played is the honest measure of which browser saw more of this player,
## and the best score breaks the tie: a fresh browser reading a real account
## must not be handed a wiped save, and a player who got further while the
## cloud was unreachable must not lose the run.
func _on_cloud_loaded(data: Dictionary) -> void:
	if data.is_empty():
		return
	var theirs_runs := int(data.get("runs_played", 0))
	var theirs_best := int(data.get("best", 0))
	if theirs_runs < runs_played or (theirs_runs == runs_played and theirs_best <= best):
		Yandex.save_cloud(to_dict())  # ours is the fuller copy — push, do not pull
		return
	_apply_dict(data)
	_write_disk()
	best_changed.emit(best)
	progress_reloaded.emit()


func _apply_dict(data: Dictionary) -> void:
	best = int(data.get("best", best))
	best_distance = int(data.get("best_distance", best_distance))
	crystals = int(data.get("crystals", crystals))
	upgrades = data.get("upgrades", upgrades)
	power_levels = data.get("power_levels", power_levels)
	power_charges = data.get("power_charges", power_charges)
	recent_runs = data.get("recent_runs", recent_runs)
	daily_date = str(data.get("daily_date", daily_date))
	daily_best = int(data.get("daily_best", daily_best))
	quest_date = str(data.get("quest_date", quest_date))
	quests = data.get("quests", quests)
	levels_cleared = int(data.get("levels_cleared", levels_cleared))
	runs_played = int(data.get("runs_played", runs_played))
	slump_streak = int(data.get("slump_streak", slump_streak))
	last_continue = float(data.get("last_continue", last_continue))
	haptics_enabled = bool(data.get("haptics", haptics_enabled))
	location = str(data.get("location", location))
	cart_variant = int(data.get("cart_variant", cart_variant))
	key_scheme = KeyScheme.clamp_id(int(data.get("key_scheme", key_scheme)))


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
	# Only the phone builds carry the switch that turns this off (see
	# MainMenu._hide_haptics_off_phone), so only they may buzz. A browser on an
	# Android phone would honour navigator.vibrate, and a game that buzzes with
	# no way to stop it is a complaint, not a feature.
	if not OS.has_feature("mobile"):
		return
	if not haptics_enabled:
		return
	Input.vibrate_handheld(milliseconds, 1.0)
