## Autoload. Everything that outlives a run: best score, crystal currency,
## settings. Saved with ConfigFile under user:// (spec section 12).
extends Node

const SAVE_PATH := "user://piperunner.cfg"

signal best_changed(value: int)

var best: int = 0
## Crystals banked across runs — the currency for meta upgrades (spec 11, P0).
var crystals: int = 0
var haptics_enabled: bool = true

## Purchased upgrades, keyed by id. Empty until the meta layer lands.
var upgrades: Dictionary = {}


func _ready() -> void:
	load_game()


func load_game() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return
	best = config.get_value("progress", "best", 0)
	crystals = config.get_value("progress", "crystals", 0)
	upgrades = config.get_value("progress", "upgrades", {})
	haptics_enabled = config.get_value("settings", "haptics", true)


func save_game() -> void:
	var config := ConfigFile.new()
	config.set_value("progress", "best", best)
	config.set_value("progress", "crystals", crystals)
	config.set_value("progress", "upgrades", upgrades)
	config.set_value("settings", "haptics", haptics_enabled)
	config.save(SAVE_PATH)


## Returns true when this run beat the record.
func submit_score(score: int) -> bool:
	if score <= best:
		save_game()
		return false
	best = score
	best_changed.emit(best)
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
