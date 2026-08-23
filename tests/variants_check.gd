## Checks the three experiment variants are actually three different mechanics.
##
## The comparison is only worth running if A, B and C behave differently, and
## the difference between B and C is one line deep — exactly the kind of thing
## that gets refactored away by accident. So this asserts the behaviour rather
## than the wiring: take a shape and see what the strip does about it.
##
##   godot --headless --path . --script res://tests/variants_check.gd
extends SceneTree

var main: Node
var experiment: Node
var frames := 0
var variant := 0
var stage := 0
var before: Array = []
var failures := 0
var checks := 0


func _initialize() -> void:
	for entry in [["GameState", "res://scripts/game_state.gd"],
			["Analytics", "res://scripts/analytics.gd"],
			["Experiment", "res://scripts/experiment.gd"]]:
		if not root.has_node(entry[0]):
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
	experiment = root.get_node("Experiment")
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 15:
		return false

	var source: BlockSource = main._blocks
	if stage == 0:
		# Back to the menu first: a variant may only change between runs, so
		# overriding mid-run is deliberately ignored.
		main._show_menu()
		experiment.override(variant)
		# Switching variants rebuilds the source, and rebuilding must not put
		# the strip on screen: the menu's own buttons live down there, and a
		# run has not started.
		_check(not main.get_node("Ui/OfferBar").visible,
			"no strip shows in the menu after switching to %s"
				% BlockSource.NAMES[variant])
		main.start_run(0)
		_check(main._blocks.strip().visible,
			"the live strip shows once a run begins")
		source = main._blocks
		_check(source.variant() == variant,
			"variant %d builds its own source" % variant)
		before = source.choices().duplicate()
		stage = 1
		return false

	# Spend repeatedly rather than once. A single deal is not evidence: B is
	# free to deal the same shape back into the same window by chance, so the
	# question is what holds over many turns — C must *never* disturb an
	# untaken window, and B must disturb one sooner or later.
	var rounds := 12
	var always_kept := true
	var ever_changed := false
	for _round in rounds:
		before = source.choices().duplicate()
		# Take from the middle window where there is one, so that "only the
		# taken window refilled" can be told apart from "nothing refilled".
		var slot: int = 1 if before.size() > 1 else 0
		source.point_at(slot)
		source.spend(main._deal_context())
		var after: Array = source.choices()
		for i in mini(before.size(), after.size()):
			if i == slot:
				continue
			if before[i] == after[i]:
				continue
			always_kept = false
			ever_changed = true

	match variant:
		BlockSource.Variant.B:
			_check(before.size() == 3, "B offers three shapes")
			_check(ever_changed,
				"B replaces the whole offer, not only the window taken from")
		BlockSource.Variant.C:
			_check(before.size() == 3, "C offers three shapes")
			_check(always_kept,
				"C never disturbs a window the player did not take from")
			_check(not source.chosen_was_held(),
				"a freshly refilled window is not held")

	variant += 1
	stage = 0
	frames = 0
	if variant < BlockSource.NAMES.size():
		return false

	print("--- %d checks, %d failed ---" % [checks, failures])
	return true
