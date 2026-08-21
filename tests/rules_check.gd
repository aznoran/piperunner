## Rule checks against the acceptance list in spec section 14, driven without a
## window. Frames are stepped by hand so the results are deterministic.
##
##   godot --headless --path . --script res://tests/rules_check.gd
extends SceneTree

const STEP := 1.0 / 60.0

var main: Node
var board: Board
var cart: Cart
var balance: GameBalance

var checks: int = 0
var failures: int = 0


func _initialize() -> void:
	if not root.has_node("GameState"):
		var state: Node = load("res://scripts/game_state.gd").new()
		state.name = "GameState"
		root.add_child(state)

	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


## Checks run on the first frame: _ready() has not fired yet inside
## _initialize(), so the scene's @onready references would still be null.
func _process(_delta: float) -> bool:
	# Drive the run loop by hand instead of letting the engine tick it.
	main.set_process(false)

	board = main._board
	cart = main._cart
	balance = main.balance

	_check_pipe_table()
	_check_queue_and_hold()
	_check_cart_waits()
	_check_placement_bounds()
	_check_replace_cost()
	_check_incoming_cell_lock()
	_check_crystal_and_combo()
	_check_death_reasons()
	_check_save_round_trip()

	print("--- %d checks, %d failed ---" % [checks, failures])
	quit(1 if failures > 0 else 0)
	return true


func _ok(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		print("FAIL: %s" % label)


func _eq(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected:
		failures += 1
		print("FAIL: %s — got %s, expected %s" % [label, actual, expected])


# --- section 04 ---------------------------------------------------------

func _check_pipe_table() -> void:
	var S := PipeDefs.Side
	var T := PipeDefs.Type
	_eq(PipeDefs.exit_side(T.V, S.D), S.U, "vertical entered from below exits up")
	_eq(PipeDefs.exit_side(T.V, S.U), S.D, "vertical entered from above exits down")
	_eq(PipeDefs.exit_side(T.V, S.L), PipeDefs.NO_EXIT, "vertical refuses the side")
	_eq(PipeDefs.exit_side(T.H, S.L), S.R, "horizontal runs through")
	_eq(PipeDefs.exit_side(T.UR, S.D), PipeDefs.NO_EXIT, "UR refuses from below")
	_eq(PipeDefs.exit_side(T.UR, S.U), S.R, "UR turns up-to-right")
	_eq(PipeDefs.exit_side(T.UR, S.R), S.U, "UR turns right-to-up")
	_eq(PipeDefs.exit_side(T.DL, S.D), S.L, "DL turns down-to-left")
	_eq(PipeDefs.exit_side(T.X, S.D), S.U, "crossroads goes straight through")
	_eq(PipeDefs.exit_side(T.X, S.L), S.R, "crossroads goes straight across")

	# Every side a pipe declares must be a usable entry, and never a dead end.
	var sound := true
	for type: int in PipeDefs.SIDES:
		for side: int in PipeDefs.SIDES[type]:
			var exit: int = PipeDefs.exit_side(type, side)
			if exit == PipeDefs.NO_EXIT or exit == side:
				sound = false
	_ok(sound, "every open side leads somewhere else")


# --- section 09 ---------------------------------------------------------

func _check_queue_and_hold() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var queue := PipeQueue.new()
	queue.start(rng, balance.queue_preview)

	_eq(queue.upcoming.size(), balance.queue_preview, "queue shows four ahead")
	_eq(queue.held, PipeQueue.NONE, "hold starts empty")

	var before := queue.upcoming.duplicate()
	queue.swap_hold()
	_eq(queue.held, before[0], "empty hold pockets the piece in hand")
	_eq(queue.current(), before[1], "pocketing advances the queue once")

	var tail := queue.upcoming.duplicate()
	var in_hand := queue.current()
	queue.swap_hold()
	_eq(queue.held, in_hand, "swap puts the hand piece in the pocket")
	_eq(queue.current(), before[0], "swap hands back what was pocketed")
	_eq(queue.upcoming[1], tail[1], "swapping does not scroll the queue")
	_eq(queue.upcoming[2], tail[2], "swapping does not scroll the queue further")

	# Two swaps in a row must land back where we started, not deal a new piece.
	queue.swap_hold()
	_eq(queue.current(), in_hand, "swapping twice is a no-op, not a reroll")


# --- section 02 ---------------------------------------------------------

func _check_cart_waits() -> void:
	main.start_run()
	var start_cell := cart.cell()
	for i in 120:
		main._run_frame(STEP)
	_ok(not main.started, "cart has not started before the first pipe")
	_eq(cart.cell(), start_cell, "cart has not moved")
	_eq(main.fuel, balance.fuel_max, "no fuel burned while parked")
	_eq(main.cells_run, 0, "no cells counted while parked")


# --- section 08 ---------------------------------------------------------

func _check_placement_bounds() -> void:
	main.start_run()
	board.max_row = 0
	var start_col: int = balance.cols / 2

	_ok(not board.can_place(Vector2i(-1, 2)), "no placing left of the board")
	_ok(not board.can_place(Vector2i(balance.cols, 2)), "no placing right of the board")
	_ok(not board.can_place(Vector2i(start_col, 0)), "no placing on flooded pipe")
	_ok(not board.can_place(cart.cell()), "no placing under the cart")
	_ok(board.can_place(Vector2i(0, balance.place_above)),
		"top of the placement window is reachable")
	_ok(not board.can_place(Vector2i(0, balance.place_above + 1)),
		"one row above the window is refused")
	_ok(board.can_place(Vector2i(0, -balance.place_below)),
		"bottom of the litter zone is reachable")
	_ok(not board.can_place(Vector2i(0, -balance.place_below - 1)),
		"one row below the litter zone is refused")

	var rock := Vector2i(0, 40)
	board.rocks[rock] = true
	_ok(not board.can_place(rock), "no placing into rock")
	board.rocks.erase(rock)


# --- section 08, overwrite ----------------------------------------------

func _check_replace_cost() -> void:
	main.start_run()
	var spot := Vector2i(0, 5)
	var fuel_before: float = main.fuel

	main._try_place(spot)
	_eq(main.fuel, fuel_before, "first pipe on an empty cell is free")
	_ok(board.get_pipe(spot) != null, "pipe landed")
	_ok(main.started, "placing a pipe starts the run")

	main._try_place(spot)
	_eq(main.fuel, fuel_before - balance.fuel_replace,
		"overwriting an unused pipe costs fuel")


## A cell the cart is already visibly inside must not accept a pipe, so nothing
## can be swapped out from under it on the last tick.
func _check_incoming_cell_lock() -> void:
	main.start_run()
	var threshold: float = balance.place_lockout_progress
	var ahead := Vector2i(balance.cols / 2, 1)

	cart.t = threshold * 0.5
	board.set_cart_incoming(cart.incoming_cell(threshold))
	_eq(cart.incoming_cell(threshold), Board.NO_CELL,
		"nothing is locked while the cart is still mostly behind")
	_ok(board.can_place(ahead), "the cell ahead is buildable until the cart enters")

	cart.t = minf(threshold + 0.1, 0.99)
	board.set_cart_incoming(cart.incoming_cell(threshold))
	_eq(cart.incoming_cell(threshold), ahead, "the cell being entered is identified")
	_ok(not board.can_place(ahead), "the cell the cart has entered is locked")

	cart.t = 0.0
	board.set_cart_incoming(cart.incoming_cell(threshold))
	_ok(board.can_place(ahead), "the lock lifts once the cart moves on")


# --- section 10 ---------------------------------------------------------

func _check_crystal_and_combo() -> void:
	main.start_run()
	main.cells_run = 0
	var row := 30
	var crystal := Vector2i(2, row)
	board.crystals[crystal] = true
	board.pipes[crystal] = Board.PipeCell.new(PipeDefs.Type.V)
	board.max_row = row - 1

	var fuel_before: float = main.fuel - 20.0
	main.fuel = fuel_before
	main._on_cart_stepped(crystal)

	_eq(main.combo, 1, "running over a crystal starts the chain")
	_eq(main.crystals_collected, 1, "crystal counted for the meta currency")
	_ok(main.fuel > fuel_before, "crystal refuels the tank")
	_ok(not board.crystals.has(crystal), "crystal is consumed")
	_eq(main.score, (row - (row - 1)) + balance.crystal_points * 1,
		"crystal pays distance plus chain points")

	# Climbing past a crystal that is still sitting there breaks the chain.
	var missed := Vector2i(5, row + 1)
	board.crystals[missed] = true
	board.pipes[Vector2i(2, row + 2)] = Board.PipeCell.new(PipeDefs.Type.V)
	main._on_cart_stepped(Vector2i(2, row + 2))
	_eq(main.combo, 0, "leaving a crystal behind resets the chain")


# --- section 14, three distinct deaths ----------------------------------

func _check_death_reasons() -> void:
	# Derailed: the cart rolls into a cell with no pipe.
	main.start_run()
	main.started = true
	var col: int = balance.cols / 2
	board.pipes[Vector2i(col, 1)] = Board.PipeCell.new(PipeDefs.Type.V)
	board.pipes.erase(Vector2i(col, 2))  # tear up the runway ahead of the cart
	cart.place_at(col, 1, PipeDefs.Side.D)
	cart.advance(1.0, 1.0)
	_eq(main._death_reason, Cart.REASON_DERAILED, "running out of pipe derails")

	# Off the edge: a horizontal pipe pointing out of column 0.
	main.start_run()
	main.started = true
	board.pipes[Vector2i(0, 4)] = Board.PipeCell.new(PipeDefs.Type.H)
	cart.place_at(0, 4, PipeDefs.Side.R)
	cart.advance(1.0, 1.0)
	_eq(main._death_reason, Cart.REASON_OFF_EDGE, "leaving column 0 ends the run")

	# Out of fuel: past the grace period with an almost empty tank.
	main.start_run()
	main.started = true
	main.cells_run = balance.grace_cells + 1
	main.fuel = balance.fuel_per_cell * 0.5
	var cell := Vector2i(col, 2)
	board.pipes[cell] = Board.PipeCell.new(PipeDefs.Type.V)
	main._on_cart_stepped(cell)
	_eq(main._death_reason, main.REASON_OUT_OF_FUEL, "an empty tank ends the run")
	_eq(main.fuel, 0.0, "fuel does not go negative")


# --- section 12, persistence --------------------------------------------

func _check_save_round_trip() -> void:
	var state: Node = root.get_node("GameState")
	var original: int = state.best
	state.best = 0
	state.submit_score(4242)
	_eq(state.best, 4242, "a new high score is recorded")

	var reloaded: Node = load("res://scripts/game_state.gd").new()
	reloaded.load_game()
	_eq(reloaded.best, 4242, "best score survives a reload")
	reloaded.free()

	state.best = original
	state.save_game()
