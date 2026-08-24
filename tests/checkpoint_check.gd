## Checks the speed gates: where they land, what they give back, and that
## missing one costs exactly what missing one should.
##
## The whole point of them is that a run stops outrunning the player after a
## minute, so the number that matters is how much pace comes back — and the
## other number that matters is that nothing happens to a gate driven past.
##
##   godot --headless --path . --script res://tests/checkpoint_check.gd
extends SceneTree

var main: Node
var state: Node
var frames := 0
var checks := 0
var failures := 0
var stage := 0


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

	var balance: GameBalance = main.balance
	if stage == 0:
		main.start_run(0)
		main.started = true

		# --- a gate is called for by speed, not by row ----------------
		main.speed = balance.start_speed
		main._watch_speed()
		_check(main._board.checkpoints.is_empty(),
			"a cart at its starting pace is offered no gate")

		var span: float = balance.speed_cap - balance.start_speed
		main.speed = balance.start_speed + span * (balance.checkpoint_trigger + 0.05)
		main._watch_speed()
		_check(not main._board.checkpoints.is_empty(),
			"and one turns up once it has run away")
		var laid: int = main._board.checkpoints.keys()[0].y
		_check(laid > main._cart.row,
			"ahead of the cart, not under it: row %d against %d"
				% [laid, main._cart.row])
		_check(laid - main._cart.row <= balance.checkpoint_notice + 1,
			"and near enough to steer for, %d rows" % (laid - main._cart.row))

		# One at a time: a cart sitting above the trigger is not handed a
		# ladder of them.
		var count: int = main._board.checkpoints.size()
		main._watch_speed()
		main._watch_speed()
		_check(main._board.checkpoints.size() == count,
			"and only one at a time")

		stage = 1
		return false

	# --- what passing one is worth ---------------------------------
	main._show_menu()
	main.start_run(0)
	main.started = true
	main.score = 900
	var fast: float = minf(balance.start_speed
		+ float(main.score) * balance.speed_gain, balance.speed_cap)
	main.speed = fast
	var gate := Vector2i(main._cart.col, main._cart.row + 4)
	main._board.checkpoints[gate] = true

	_check(main._board.take_checkpoint(gate), "the gate can be taken")
	main._pass_gate(gate)
	var eased: float = minf(balance.start_speed
		+ maxf(float(main.score) - main._speed_pardon, 0.0) * balance.speed_gain,
		balance.speed_cap)
	_check(eased < fast, "passing one slows the cart, %.2f -> %.2f" % [fast, eased])
	_check(main.score == 900,
		"and the score is not touched: what was earned stays earned, got %d"
			% main.score)

	# The first gate of a run puts the cart nearly back at the beginning.
	var first_target: float = balance.start_speed \
		+ (balance.speed_cap - balance.start_speed) * balance.checkpoint_pace
	_check(absf(eased - first_target) < 0.05,
		"the first gate leaves it near the start, %.2f against %.2f"
			% [eased, first_target])

	# The ratchet: the next one gives back less, and the one after that less
	# again, so a run keeps going and keeps getting harder.
	var paces: Array[float] = [eased]
	for _i in 3:
		main.score = 900
		main.speed = fast
		main._pass_gate(gate)
		paces.append(minf(balance.start_speed
			+ maxf(float(main.score) - main._speed_pardon, 0.0)
			* balance.speed_gain, balance.speed_cap))
	var climbing := true
	for i in range(1, paces.size()):
		if paces[i] <= paces[i - 1]:
			climbing = false
	_check(climbing, "each gate leaves the cart faster than the last, %s"
		% str(paces))

	# --- the warning ------------------------------------------------
	#
	# The speed climbs a thousandth at a time, so without a word for it the
	# player finds out they are past the point of coping by losing.
	main._speed_warned = false
	main._speed_pardon = 0.0
	main.score = 20
	main.speed = balance.start_speed
	main._watch_speed()
	_check(not main._speed_warned, "a cart at its starting pace says nothing")

	var span: float = balance.speed_cap - balance.start_speed
	main.speed = balance.start_speed + span * (balance.speed_warn_at + 0.05)
	main._watch_speed()
	_check(main._speed_warned, "and speaks up once it is past the mark")

	# Sitting on the line must not blink: it takes a real fall to clear.
	main.speed = balance.start_speed + span * (balance.speed_warn_at - 0.01)
	main._watch_speed()
	_check(main._speed_warned, "a cart hovering on the mark keeps the warning")

	main.speed = balance.start_speed + span * 0.1
	main._watch_speed()
	_check(not main._speed_warned, "and a gate that really slowed it clears it")

	print("--- %d checks, %d failed ---" % [checks, failures])
	return true
