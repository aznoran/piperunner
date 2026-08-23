## Checks the power-ups do what they promise, and cost nothing when they do
## not.
##
## A charge is bought with crystals, so being charged for a power-up that found
## nothing to do is the kind of thing a player remembers and nobody would
## report as a bug — they would just stop buying them.
##
##   godot --headless --path . --script res://tests/power_check.gd
extends SceneTree

var main: Node
var state: Node
var frames := 0
var checks := 0
var failures := 0
var stage := 0
var before_cells := 0


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _initialize() -> void:
	for entry in [["GameState", "res://scripts/game_state.gd"],
			["Analytics", "res://scripts/analytics.gd"],
			["Experiment", "res://scripts/experiment.gd"],
			["PlayLog", "res://scripts/play_log.gd"]]:
		if not root.has_node(entry[0]):
			var node: Node = load(entry[1]).new()
			node.name = entry[0]
			root.add_child(node)
	state = root.get_node("GameState")
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames < 20:
		return false

	if stage == 0:
		state.power_charges = {"autolay": 2, "halt": 2}
		state.power_levels = {}
		main.start_run(0)
		stage = 1
		return false

	if stage == 1:
		# --- the tracklayer ------------------------------------------
		var wanted := int(round(PowerUps.value(&"autolay", state)))
		_check(wanted >= 5, "the tracklayer starts at five cells, got %d" % wanted)
		before_cells = main._board.pipes.size()
		var fired: bool = main.use_power(&"autolay")
		_check(fired, "the tracklayer fires with track to lay")
		var laid: int = main._board.pipes.size() - before_cells
		_check(laid > 0 and laid <= wanted,
			"it lays up to what it promises, laid %d of %d" % [laid, wanted])
		_check(PowerUps.charges(&"autolay", state) == 1,
			"and costs exactly one charge, %d left"
				% PowerUps.charges(&"autolay", state))

		# --- the brake -----------------------------------------------
		var held: float = PowerUps.value(&"halt", state)
		_check(held >= 3.0, "the brake starts at three seconds, got %.1f" % held)
		_check(main.use_power(&"halt"), "the brake fires on a rolling cart")
		_check(main._braked > 0.0, "and the cart is held")
		_check(PowerUps.charges(&"halt", state) == 1, "for one charge")

		# Firing it again while it is already on finds nothing to do, and so
		# must not be paid for.
		_check(not main.use_power(&"halt"),
			"a brake on top of a brake does nothing")
		_check(PowerUps.charges(&"halt", state) == 1,
			"and is not charged for, %d left"
				% PowerUps.charges(&"halt", state))

		# --- an empty power-up ---------------------------------------
		state.power_charges["autolay"] = 0
		_check(not main.use_power(&"autolay"), "an empty power-up does not fire")

		# --- levelling ------------------------------------------------
		state.crystals = 10000
		var was: float = PowerUps.value(&"halt", state)
		_check(PowerUps.buy_upgrade(&"halt", state), "a level can be bought")
		_check(PowerUps.value(&"halt", state) > was,
			"and the power-up gets stronger, %.2f -> %.2f"
				% [was, PowerUps.value(&"halt", state)])

		print("--- %d checks, %d failed ---" % [checks, failures])
		return true
	return false
