## Checks C cannot reach a player while the switch is off.
##
## This is the one piece of the experiment where a mistake ships an untested
## mechanic to everybody, so it is asserted rather than trusted. The cases that
## matter are the ones where something *else* says C: a group saved from an
## earlier session, and a build with no Remote Config at all.
##
##   godot --headless --path . --script res://tests/switch_check.gd
extends SceneTree

var checks := 0
var failures := 0


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", what)


var experiment: Node


func _initialize() -> void:
	# Analytics has to exist before Experiment publishes to it.
	if not root.has_node("Analytics"):
		var analytics: Node = load("res://scripts/analytics.gd").new()
		analytics.name = "Analytics"
		root.add_child(analytics)

	# A group saved by an earlier session, written before the probe is stood
	# up so that its _ready finds it.
	var saved := ConfigFile.new()
	saved.set_value("experiment", "variant", "C")
	saved.save(Experiment.SAVE_PATH)

	experiment = load("res://scripts/experiment.gd").new()
	experiment.name = "SwitchProbe"
	root.add_child(experiment)


## A node added during _initialize has not run _ready yet, so every assertion
## about what the probe decided has to wait a frame.
func _process(_delta: float) -> bool:
	_check(Experiment.FALLBACK == BlockSource.Variant.B,
		"the fallback is B, not C")
	_check(BlockSource.NAMES.size() == 2,
		"two variants ship, got %d" % BlockSource.NAMES.size())
	_check(not BlockSource.NAMES.has("A"), "A is gone from the pool")

	# With no config to turn it on, the switch is off by definition, so this
	# player plays B however their save file reads.
	_check(not experiment.held_windows_enabled,
		"the switch is off without a config that turns it on")
	_check(experiment.variant == BlockSource.Variant.B,
		"a saved C does not reach the player while the switch is off, got %s"
			% BlockSource.NAMES[experiment.variant])
	_check(experiment.make_source() is OfferSource,
		"B builds the plain offer")

	# The saved letter survives, so flipping the switch back on restores the
	# groups instead of reshuffling everyone.
	var reread := ConfigFile.new()
	reread.load(Experiment.SAVE_PATH)
	_check(String(reread.get_value("experiment", "variant", "")) == "C",
		"the saved group is kept, not erased")

	# And the mapping the switch guards.
	experiment.variant = BlockSource.Variant.C
	_check(experiment.make_source() is HeldOfferSource,
		"C builds the held offer")

	DirAccess.remove_absolute(Experiment.SAVE_PATH)
	print("--- %d checks, %d failed ---" % [checks, failures])
	return true
