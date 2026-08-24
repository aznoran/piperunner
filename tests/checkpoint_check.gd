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
		# --- placement follows this player, not an average one --------
		state.recent_runs = []
		main.start_run(0)
		_check(main._board.next_checkpoint_row >= balance.checkpoint_first_min,
			"with no history the first gate uses the designed gap, got %d"
				% main._board.next_checkpoint_row)

		state.recent_runs = [60, 64, 56, 60]
		main._show_menu()
		main.start_run(0)
		var reach: int = state.usual_reach()
		_check(reach == 60, "the usual reach is their own average, got %d" % reach)
		_check(main._board.next_checkpoint_row == reach - balance.checkpoint_lead,
			"and the first gate lands that far short of it, got %d"
				% main._board.next_checkpoint_row)

		# A player who dies early still gets the gate no sooner than the floor,
		# since a gate met before the speed bites is a gate wasted.
		state.recent_runs = [8, 10, 9]
		main._show_menu()
		main.start_run(0)
		_check(main._board.next_checkpoint_row == balance.checkpoint_first_min,
			"a short run's gate is held at the floor, got %d"
				% main._board.next_checkpoint_row)

		stage = 1
		return false

	# --- what passing one is worth ---------------------------------
	state.recent_runs = []
	main._show_menu()
	main.start_run(0)
	main.started = true
	main.score = 900
	var fast: float = minf(balance.start_speed
		+ float(main.score) * balance.speed_gain, balance.speed_cap)
	_check(fast > balance.start_speed * 1.5,
		"the cart has wound up by nine hundred points, %.2f" % fast)

	main.speed = fast
	var gate := Vector2i(main._cart.col, main._cart.row + 4)
	main._board.checkpoints[gate] = true

	# Driven past: the gate is still there and the pace is untouched.
	main._pull_crystals(Vector2i(gate.x + 1, gate.y))
	_check(main._speed_pardon == 0.0,
		"a gate nobody drove through gives nothing back")

	# Driven through.
	_check(main._board.take_checkpoint(gate), "the gate can be taken")
	main._pass_gate(gate)
	var eased: float = minf(balance.start_speed
		+ maxf(float(main.score) - main._speed_pardon, 0.0) * balance.speed_gain,
		balance.speed_cap)
	_check(eased < fast, "passing one slows the cart, %.2f -> %.2f" % [fast, eased])
	_check(eased >= balance.start_speed,
		"but never below the pace it started at, %.2f" % eased)
	_check(main.score == 900,
		"and the score is not touched: what was earned stays earned, got %d"
			% main.score)

	# It leaves the cart at the pace the sheet names, whatever it arrived at.
	var target: float = balance.start_speed \
		+ (balance.speed_cap - balance.start_speed) * balance.checkpoint_pace
	_check(absf(eased - target) < 0.05,
		"it leaves the cart at the pace it says, %.2f against %.2f"
			% [eased, target])

	# And a cart already slower than that keeps what it has: a gate gives pace
	# back and never takes it.
	main._speed_pardon = 0.0
	main.score = 20
	main.speed = balance.start_speed + 20.0 * balance.speed_gain
	var crawling: float = main.speed
	main._pass_gate(gate)
	var after: float = minf(balance.start_speed
		+ maxf(float(main.score) - main._speed_pardon, 0.0) * balance.speed_gain,
		balance.speed_cap)
	_check(absf(after - crawling) < 0.001,
		"a slow cart is left alone, %.2f -> %.2f" % [crawling, after])

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
