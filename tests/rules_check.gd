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
	_stand_up_autoloads()

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
	_check_offer()
	_check_cart_waits()
	_check_placement_bounds()
	_check_replace_cost()
	_check_incoming_cell_lock()
	_check_crystal_and_combo()
	_check_death_reasons()
	_check_save_round_trip()
	_check_power_ups()
	_check_magnet()
	_check_distance_record()
	_check_daily()
	_check_skin_swap()
	_check_quests()
	_check_locations()
	_check_back_key()
	_check_story()
	_check_fuel_drain()
	_check_praise()
	_check_dealer()
	_check_continue()
	_check_station_finish()
	_check_keyboard()
	_check_ads()
	_check_translations()

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

func _check_offer() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var offer := PipeOffer.new()
	offer.start(rng, balance.offer_size, RandomDealer.new())

	_eq(offer.choices.size(), balance.offer_size, "the offer shows three shapes")
	_eq(offer.selected, 0, "with the first of them chosen to begin with")
	_eq(offer.current(), offer.choices[0], "and that is what a placement spends")

	var distinct := {}
	for type: int in offer.choices:
		distinct[type] = true
	_eq(distinct.size(), offer.choices.size(), "no shape is offered twice")

	# Choosing is free and reversible — only placing spends the turn.
	var shown := offer.choices.duplicate()
	_ok(offer.select(2), "another shape can be chosen")
	_eq(offer.current(), shown[2], "and it becomes what a placement spends")
	_eq(str(offer.choices), str(shown), "choosing does not re-deal the offer")
	_ok(offer.select(0), "and the choice can be taken back")
	_eq(offer.current(), shown[0], "with nothing spent for it")
	_ok(not offer.select(0), "choosing the same shape again is a no-op")
	_ok(not offer.select(99), "and an index off the end is refused")

	# Taking one spends the whole offer: the shapes not chosen do not carry
	# over, or the strip would become a hand rather than a decision.
	offer.select(1)
	offer.take()
	_eq(offer.choices.size(), balance.offer_size, "taking one deals a fresh offer")
	# The shapes change; where the player is looking does not. Snapping back to
	# the first window made the finger cross the strip after every placement.
	_eq(offer.selected, 1, "with the cursor left on the window it was on")

	# The upgrade widens the offer rather than lengthening a preview.
	offer.resize(balance.offer_size + 1)
	_eq(offer.choices.size(), balance.offer_size + 1,
		"the upgrade widens the offer")


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
	# Clear generated rock so the window edges are tested on their own — the
	# top of the window sits past rock_start_row, where a rock may legitimately
	# be sitting in the cell being probed.
	board.rocks.clear()
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
	# Clear the generated ones first: a crystal that happens to sit in the cell
	# being stepped into would be collected and start a new chain, which made
	# this check pass or fail on the seed.
	board.crystals.clear()
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


# --- section 11, P0: meta progression -----------------------------------
#
# Upgrades are gone. They were a number that went up once and then sat there,
# and what the depot sells now is either a decision the player makes during a
# run or something they can see. So what this checks is the till: crystals are
# spent, refused purchases change nothing, and a level makes the power-up it
# belongs to actually stronger.

func _check_power_ups() -> void:
	var state: Node = root.get_node("GameState")
	var saved_crystals: int = state.crystals
	var saved_levels: Dictionary = state.power_levels.duplicate()
	var saved_charges: Dictionary = state.power_charges.duplicate()
	state.power_levels.clear()
	state.power_charges.clear()
	state.crystals = 0

	var brake := PowerUps.find(&"halt")
	_ok(brake != null, "the brake is in the catalogue")
	_eq(PowerUps.charges(&"halt", state), brake.starting_charges,
		"a fresh save starts with a few charges")
	_eq(PowerUps.level(&"halt", state), 0, "and nothing levelled")

	_ok(not PowerUps.buy_charge(&"halt", state), "cannot buy without crystals")
	_eq(PowerUps.charges(&"halt", state), brake.starting_charges,
		"...and a refused purchase hands out nothing")

	state.crystals = PowerUps.charge_cost(&"halt", state)
	var held := PowerUps.charges(&"halt", state)
	_ok(PowerUps.buy_charge(&"halt", state), "buying with exactly enough works")
	_eq(state.crystals, 0, "the crystals are spent")
	_eq(PowerUps.charges(&"halt", state), held + 1, "and a charge arrives")

	_ok(PowerUps.spend(&"halt", state), "a charge can be spent")
	_eq(PowerUps.charges(&"halt", state), held, "which takes it away again")

	# Levels: each one makes it stronger, and they run out.
	state.crystals = 999999
	var weakest := PowerUps.value(&"halt", state)
	_ok(PowerUps.buy_upgrade(&"halt", state), "a level can be bought")
	_ok(PowerUps.value(&"halt", state) > weakest,
		"and the power-up gets stronger for it")
	while PowerUps.upgrade_cost(&"halt", state) >= 0:
		PowerUps.buy_upgrade(&"halt", state)
	_eq(PowerUps.level(&"halt", state), brake.max_level(),
		"levels stop at the cap")
	_ok(not PowerUps.buy_upgrade(&"halt", state),
		"a maxed power-up cannot be levelled again")

	# A stronger power-up costs more to restock, or levelling would be the
	# cheap way to a strong one.
	_ok(PowerUps.charge_cost(&"halt", state) > brake.charge_cost,
		"a levelled power-up costs more a charge")

	state.crystals = saved_crystals
	state.power_levels = saved_levels
	state.power_charges = saved_charges
	state.save_game()
	main._rebuild_balance()
	balance = main.balance


func _check_magnet() -> void:
	main.start_run()
	main.cells_run = 0
	var row := 40
	var centre := Vector2i(3, row)
	var beside := Vector2i(4, row)
	board.pipes[centre] = Board.PipeCell.new(PipeDefs.Type.V)
	board.max_row = row - 1

	main._magnet_reach = 0
	board.crystals[beside] = true
	main._on_cart_stepped(centre)
	_ok(board.crystals.has(beside),
		"without the magnet a crystal beside the cart is left behind")

	main._magnet_reach = 1
	main._on_cart_stepped(centre)
	_ok(not board.crystals.has(beside), "the magnet pulls in a neighbour")

	main._magnet_reach = 1
	var far := Vector2i(3, row + 3)
	board.crystals[far] = true
	main._on_cart_stepped(centre)
	_ok(board.crystals.has(far), "the magnet does not reach past its radius")
	board.crystals.erase(far)
	main._magnet_reach = 0


# --- section 11, P0: distance record --------------------------------------

func _check_distance_record() -> void:
	var state: Node = root.get_node("GameState")
	var saved_best: int = state.best
	var saved_distance: int = state.best_distance

	# Score and distance are separate records and must not shadow each other.
	state.best = 0
	state.best_distance = 0
	_ok(state.submit_score(120), "a first score is recorded")
	_ok(state.submit_distance(30), "so is a first distance")
	_eq(state.best, 120, "the score record stands alone")
	_eq(state.best_distance, 30, "and so does the distance record")

	_ok(not state.submit_distance(25), "a shorter run does not beat the distance")
	_eq(state.best_distance, 30, "the distance record holds")
	_ok(state.submit_distance(31), "one cell further does beat it")

	# A crystal-heavy run can score high without climbing: only score moves.
	_ok(state.submit_score(400), "a high-scoring run sets a score record")
	_ok(not state.submit_distance(10), "...without touching the distance record")
	_eq(state.best_distance, 31, "the furthest row is unchanged")

	var reloaded: Node = load("res://scripts/game_state.gd").new()
	reloaded.load_game()
	_eq(reloaded.best_distance, 31, "the distance record survives a reload")
	reloaded.free()

	board.show_record(31)
	_ok(board.ghost_visible, "a real distance turns the marker on")
	_eq(board.ghost_row, 31, "the line sits at that row")
	board.show_record(0)
	_ok(not board.ghost_visible, "no distance, no marker")

	state.best = saved_best
	state.best_distance = saved_distance
	state.save_game()


# --- section 11, P1: daily challenge ------------------------------------

func _check_daily() -> void:
	var state: Node = root.get_node("GameState")
	var saved_date: String = state.daily_date
	var saved_daily: int = state.daily_best

	_eq(state.daily_seed(), state.daily_seed(), "today's seed is stable")

	# The whole point: one seed, one board, for everyone.
	board.start_run(state.daily_seed(), true, 0)
	var first_rocks: Dictionary = board.rocks.duplicate()
	var first_crystals: Dictionary = board.crystals.duplicate()
	board.start_run(state.daily_seed(), true, 0)
	_eq(board.rocks.size(), first_rocks.size(), "the same seed lays the same rocks")
	_eq(board.crystals.size(), first_crystals.size(), "and the same crystals")
	var identical := true
	for cell: Vector2i in first_rocks:
		if not board.rocks.has(cell):
			identical = false
	for cell: Vector2i in first_crystals:
		if not board.crystals.has(cell):
			identical = false
	_ok(identical, "...in exactly the same cells")

	state.daily_date = ""
	state.daily_best = 0
	_eq(state.daily_result(), 0, "an unplayed day reads as zero")
	_ok(state.submit_daily(31), "a first attempt is recorded")
	_eq(state.daily_result(), 31, "and reads back")
	_ok(not state.submit_daily(12), "a worse attempt does not overwrite it")
	_eq(state.daily_result(), 31, "the better score stands")

	state.daily_date = saved_date
	state.daily_best = saved_daily
	state.save_game()


# --- location skins ------------------------------------------------------

func _check_skin_swap() -> void:
	var original := Skins.current()
	var probe := LocationSkin.new()
	probe.display_name = "Probe"
	probe.accent = Color.RED

	main.apply_skin(probe)
	_eq(Skins.current(), probe, "the skin swaps")
	_eq(board._skin, probe, "the board repaints")
	_eq(cart._skin, probe, "so does the cart")
	_eq(PipeDefs.exit_side(PipeDefs.Type.V, PipeDefs.Side.D), PipeDefs.Side.U,
		"a skin change leaves the rules alone")
	_eq(probe.shape_color(PipeDefs.Type.V), probe.accent,
		"a skin with no shape colours falls back to its accent")

	main.apply_skin(original)
	_eq(Skins.current(), original, "and swaps back")


# --- section 11, P2: rotating goals -------------------------------------

func _check_quests() -> void:
	var state: Node = root.get_node("GameState")
	var saved_date: String = state.quest_date
	var saved_quests: Array = state.quests.duplicate(true)
	var saved_crystals: int = state.crystals

	state.quest_date = ""
	state.quests = []
	Quests.ensure_today(state)
	_eq(state.quests.size(), Quests.DAILY_COUNT, "a day rolls three goals")
	_eq(state.quest_date, state.today(), "stamped with today's date")

	var ids: Array = []
	for entry: Dictionary in state.quests:
		ids.append(entry["id"])
		_ok(Quests.find(StringName(entry["id"])) != null, "each goal is a real one")
		_eq(entry["progress"], 0, "each starts at zero")
		_ok(not entry["claimed"], "and unclaimed")
	_eq(ids.size(), ids.duplicate().size(), "no duplicates in the set")
	var unique := {}
	for id: String in ids:
		unique[id] = true
	_eq(unique.size(), ids.size(), "the three goals are distinct")

	# Same date, same set — the roll must not drift between menu visits.
	var first_ids := ids.duplicate()
	Quests.ensure_today(state)
	var again: Array = []
	for entry: Dictionary in state.quests:
		again.append(entry["id"])
	_eq(again, first_ids, "re-checking the same day keeps the same goals")

	# Progress: accumulating goals sum, "in one run" goals keep the best.
	state.quests = [
		{"id": "gather", "target": 20, "progress": 0, "claimed": false},
		{"id": "chain", "target": 5, "progress": 0, "claimed": false},
	]
	Quests.report(state, {"crystals": 8, "combo": 3})
	_eq(state.quests[0]["progress"], 8, "an accumulating goal adds up")
	_eq(state.quests[1]["progress"], 3, "a one-run goal takes the run's value")

	Quests.report(state, {"crystals": 7, "combo": 2})
	_eq(state.quests[0]["progress"], 15, "and keeps adding across runs")
	_eq(state.quests[1]["progress"], 3, "a weaker run does not lower a one-run goal")

	_ok(not Quests.is_complete(state.quests[0]), "15 of 20 is not complete")
	_ok(not Quests.has_claimable(state), "nothing to claim yet")
	_eq(Quests.claim(state, "gather"), 0, "an unfinished goal pays nothing")

	var done := Quests.report(state, {"crystals": 10, "combo": 6})
	_eq(done.size(), 2, "the run that finishes both reports both")
	_ok(Quests.is_complete(state.quests[0]), "the goal is complete")
	_ok(Quests.has_claimable(state), "and waiting to be claimed")

	state.crystals = 0
	var reward: int = Quests.claim(state, "gather")
	_ok(reward > 0, "claiming pays out")
	_eq(state.crystals, reward, "the crystals land in the wallet")
	_eq(Quests.claim(state, "gather"), 0, "a goal cannot be claimed twice")
	_eq(state.crystals, reward, "and the wallet does not grow again")

	var finished := Quests.report(state, {"crystals": 50})
	_eq(finished.size(), 0, "an already finished goal is not reported again")

	# Midnight: a new date rolls a fresh set.
	state.quest_date = "1999-01-01"
	Quests.ensure_today(state)
	_eq(state.quest_date, state.today(), "a new day re-rolls")
	_eq(state.quests.size(), Quests.DAILY_COUNT, "back to three")
	_eq(state.quests[0]["progress"], 0, "with progress reset")

	state.quest_date = saved_date
	state.quests = saved_quests
	state.crystals = saved_crystals
	state.save_game()


# --- locations -----------------------------------------------------------

func _check_locations() -> void:
	var original := Skins.current()
	var all := Skins.catalogue()
	_ok(all.size() >= 2, "more than one location ships")

	var names := {}
	for skin in all:
		names[skin.display_name] = true
		_ok(not skin.display_name.is_empty(), "every location is named")
	_eq(names.size(), all.size(), "location names are unique")

	var forest := Skins.by_name("Forest")
	_ok(forest != null, "the forest location is in the catalogue")
	_ok(forest.rock_texture != null, "it brings art for obstacles")
	_ok(forest.pickup_texture != null, "and for pickups")
	_ok(forest.cart_variant_count() > 1, "and several cart looks")

	# Cycling visits every location and comes back round.
	var seen := {}
	for i in all.size():
		seen[Skins.current().display_name] = true
		Skins.set_current(Skins.next())
	_eq(seen.size(), all.size(), "cycling reaches every location")
	_eq(Skins.current(), original, "and returns to where it started")

	# A cart variant index never falls off the end.
	for variant in [0, 1, 2, 7, 99]:
		_ok(forest.cart_art(variant) != null,
			"cart variant %d resolves" % variant)

	var plain := Skins.by_name("Neon Neutral")
	_ok(plain != null, "the default location is in the catalogue")
	_eq(plain.cart_art(0), null, "a location without art draws its cart instead")
	_eq(plain.cart_variant_count(), 1, "and offers a single look")

	Skins.set_current(original)


## The back key is a way out of a run that has not started yet, and nothing
## more: once a pipe is down the run has to be finished.
func _check_back_key() -> void:
	var state: Node = root.get_node("GameState")
	var saved_best: int = state.best
	var saved_crystals: int = state.crystals
	state.best = 0
	state.crystals = 0

	main.start_run()
	main.score = 40
	main.crystals_collected = 3
	main.abandon_run()
	_eq(main.state, 0, "backing out before the first pipe returns to the menu")
	_eq(state.best, 0, "a run that never started banks no score")
	_eq(state.crystals, 0, "and no crystals")

	main.start_run()
	main.started = true
	main.score = 88
	main.abandon_run()
	_eq(main.state, 1, "once the run has started the key does nothing")
	_eq(state.best, 0, "and nothing is banked behind the player's back")

	main._show_menu()
	state.best = saved_best
	state.crystals = saved_crystals
	state.save_game()


# --- story run -----------------------------------------------------------

func _check_story() -> void:
	var state: Node = root.get_node("GameState")
	var saved_cleared: int = state.levels_cleared
	var saved_crystals: int = state.crystals

	_ok(Levels.count() >= 12, "the line has stations on it")
	# Every listed path must actually load: the list is hand-maintained, and a
	# typo in it would silently shorten the line rather than fail loudly.
	_eq(Levels.count(), Levels.PATHS.size(), "every listed station loads")
	var numbers := {}
	for level in Levels.catalogue():
		numbers[level.number] = true
		_ok(level.goal_target > 0, "station %d asks for something" % level.number)
		_ok(not level.title.is_empty(), "station %d is named" % level.number)
	_eq(numbers.size(), Levels.count(), "station numbers are unique")

	# A station's map is fixed: same seed every attempt, so it is learnable.
	var first := Levels.find(1)
	_eq(Levels.seed_for(first), Levels.seed_for(first), "a station keeps its map")
	_ok(Levels.seed_for(first) != Levels.seed_for(Levels.find(2)),
		"different stations are different maps")

	state.levels_cleared = 0
	state.crystals = 0
	_eq(Levels.current(state).number, 1, "an untouched line starts at one")
	_ok(Levels.is_unlocked(state, 1), "the first station is open")
	_ok(not Levels.is_unlocked(state, 2), "the second is not, yet")

	_ok(not Levels.is_met(first, {"distance": first.goal_target - 1}),
		"one short of the goal is not a clear")
	_ok(Levels.is_met(first, {"distance": first.goal_target}),
		"reaching it is")

	var paid := Levels.clear(state, 1)
	_eq(paid, first.reward, "clearing pays the station's reward")
	_eq(state.crystals, first.reward, "into the wallet")
	_eq(state.levels_cleared, 1, "and advances the line")
	_ok(Levels.is_unlocked(state, 2), "which opens the next station")

	_eq(Levels.clear(state, 1), 0, "replaying a cleared station pays nothing")
	_eq(state.crystals, first.reward, "so the wallet is unchanged")
	_eq(state.levels_cleared, 1, "and the line does not move backwards")

	var reloaded: Node = load("res://scripts/game_state.gd").new()
	reloaded.load_game()
	_eq(reloaded.levels_cleared, 1, "progress on the line survives a reload")
	reloaded.free()

	state.levels_cleared = saved_cleared
	state.crystals = saved_crystals
	state.save_game()


## Fuel leaves the tank two ways: per cell travelled, after a grace period,
## and per second the cart is rolling, from the first second.
func _check_fuel_drain() -> void:
	main.start_run()
	main.started = true
	var full: float = main.fuel

	# Time alone burns fuel, with no grace and without the cart moving a cell.
	main._burn_fuel(balance.fuel_per_second * 2.0)
	_ok(main.fuel < full, "idling burns fuel")
	_eq(main.fuel, full - balance.fuel_per_second * 2.0, "at the stated rate")
	_eq(main.cells_run, 0, "without counting a cell")

	# The per-cell drain still waits for the grace period.
	main.start_run()
	main.started = true
	full = main.fuel
	main.cells_run = balance.grace_cells - 1
	var cell := Vector2i(balance.cols / 2, 1)
	board.pipes[cell] = Board.PipeCell.new(PipeDefs.Type.V)
	main._on_cart_stepped(cell)
	_eq(main.fuel, full, "a cell inside the grace period is free")

	main.cells_run = balance.grace_cells + 1
	main._on_cart_stepped(cell)
	_eq(main.fuel, full - balance.fuel_per_cell, "a cell past it is not")

	# Either drain can end the run, through the same path.
	main.start_run()
	main.started = true
	main.fuel = balance.fuel_per_second * 0.5
	main._burn_fuel(balance.fuel_per_second)
	_eq(main._death_reason, main.REASON_OUT_OF_FUEL, "running dry on time ends the run")
	_eq(main.fuel, 0.0, "and the tank reads empty")

	main._show_menu()


# --- praise --------------------------------------------------------------

func _check_praise() -> void:
	var praise := Praise.new()
	praise.setup(balance)
	praise.start_run()

	_eq(praise.consider(Praise.Kind.CHAIN, 1), "", "a chain of one earns nothing")
	_eq(praise.consider(Praise.Kind.CHAIN, 2), "NICE", "two earns the smallest")
	_eq(praise.consider(Praise.Kind.CHAIN, 3), "", "and the cooldown holds the next")

	praise.tick(balance.praise_cooldown + 0.1)
	_eq(praise.consider(Praise.Kind.CHAIN, 3), "GREAT", "which passes once it expires")
	praise.tick(balance.praise_cooldown + 0.1)
	_eq(praise.consider(Praise.Kind.CHAIN, 3), "", "the same word does not come straight back")

	# A record ignores both the cooldown and the cap: it happens once a run.
	praise.start_run()
	_eq(praise.consider(Praise.Kind.CHAIN, 2), "NICE", "run starts clean")
	_eq(praise.consider(Praise.Kind.RECORD), "NEW BEST", "a record never waits")

	# The bar for a chain rises with distance.
	_eq(praise.chain_threshold(0), balance.praise_combo_base, "the bar starts low")
	_ok(praise.chain_threshold(balance.praise_combo_step * 2)
		> praise.chain_threshold(0), "and rises as the run goes on")

	praise.start_run()
	var shown := 0
	for i in balance.praise_run_cap * 3:
		praise.tick(balance.praise_cooldown + 0.1)
		if not praise.consider(Praise.Kind.CLUTCH).is_empty():
			shown += 1
	_ok(shown <= balance.praise_run_cap, "a run has a praise ceiling")


# --- dealer --------------------------------------------------------------

func _check_dealer() -> void:
	var dealer := RandomDealer.new()
	dealer.setup(balance)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242

	# Every offer is the size it was asked for and never repeats a shape.
	var seen := {}
	var clean := true
	for i in 300:
		var dealt := dealer.fill(rng, 3, {})
		var distinct := {}
		for type: int in dealt:
			distinct[type] = true
			seen[type] = true
		if dealt.size() != 3 or distinct.size() != dealt.size():
			clean = false
	_ok(clean, "every offer is the right size and holds no shape twice")
	_eq(seen.size(), PipeDefs.ALL.size(), "and every shape comes up sooner or later")

	# Uniqueness caps the offer at the number of shapes that exist.
	_eq(dealer.fill(rng, 99, {}).size(), PipeDefs.ALL.size(),
		"an offer cannot ask for more shapes than there are")
	_eq(dealer.fill(rng, 0, {}).size(), 1, "nor for none at all")

	# Deterministic from the seed: a daily has to deal every player the same
	# offers (spec section 11).
	var left := RandomNumberGenerator.new()
	var right := RandomNumberGenerator.new()
	left.seed = 77
	right.seed = 77
	_eq(str(dealer.fill(left, 3, {})), str(dealer.fill(right, 3, {})),
		"the same seed deals the same offer")

	# The rule is handed the run, not just a count, so that a later one can
	# read it without a signature change.
	var context := {"need": PipeDefs.Side.D, "buffer": 0, "fuel": 5.0,
		"fuel_max": balance.fuel_max, "runs_played": 0, "in_slump": false}
	_eq(dealer.fill(rng, 3, context).size(), 3,
		"and it takes a run context even when it ignores one")


# --- continue ------------------------------------------------------------

func _check_continue() -> void:
	var state: Node = root.get_node("GameState")
	var saved_runs: int = state.runs_played
	var saved_continue: float = state.last_continue
	var saved_distance: int = state.best_distance

	state.runs_played = 20
	state.last_continue = 0.0
	state.best_distance = 40

	main.start_run()
	main.started = true
	main.distance = 5
	_ok(not main._continue_is_worth_offering(), "a short death is not worth an offer")

	main.distance = 35
	_ok(main._continue_is_worth_offering(), "one close to the record is")

	main.distance = balance.continue_min_distance + 1
	state.best_distance = 0
	_ok(main._continue_is_worth_offering(), "so is simply a long run")

	main.continued = true
	_ok(not main._continue_is_worth_offering(), "but only once a run")
	main.continued = false

	state.last_continue = Time.get_unix_time_from_system()
	_ok(not main._continue_is_worth_offering(), "and not inside the cooldown")
	state.last_continue = 0.0

	state.runs_played = 1
	_ok(not main._continue_is_worth_offering(), "nor in the first runs at all")
	state.runs_played = 20

	# A continued run cannot set a distance record: the ghost line has to mean
	# one uninterrupted run.
	state.best_distance = 0
	main.continued = true
	main.distance = 50
	main._bank_run()
	_eq(state.best_distance, 0, "a continued run sets no distance record")

	main.continued = false
	main.distance = 50
	main._bank_run()
	_eq(state.best_distance, 50, "an uninterrupted one does")

	state.runs_played = saved_runs
	state.last_continue = saved_continue
	state.best_distance = saved_distance
	state.save_game()
	main._show_menu()


# --- desktop and web ----------------------------------------------------

## The keyboard picks a shape; it never places one. Both halves matter: a key
## that placed would spend the turn from across the screen, and a key that
## picked nothing would leave the web build with the strip as its only control.
func _check_keyboard() -> void:
	var K := KeyScheme
	_eq(K.slot_for(K.Id.QWE, KEY_Q, 3), 0, "Q is the first slot")
	_eq(K.slot_for(K.Id.QWE, KEY_E, 3), 2, "E is the third")
	_eq(K.slot_for(K.Id.ASD, KEY_S, 3), 1, "S is the second on the home row")
	_eq(K.slot_for(K.Id.ARROWS, KEY_LEFT, 3), 0, "left arrow is the first")
	_eq(K.slot_for(K.Id.ARROWS, KEY_RIGHT, 3), 2, "right arrow is the third")

	# A fourth key does nothing until an upgrade has widened the offer to it.
	_eq(K.slot_for(K.Id.QWE, KEY_R, 3), -1, "the fourth key is dead on a row of three")
	_eq(K.slot_for(K.Id.QWE, KEY_R, 4), 3, "and alive on a row of four")

	# The digits are accepted whatever the scheme: they are what a player tries
	# without being told, and refusing them to protect a setting nobody has
	# opened is a small piece of rudeness.
	_eq(K.slot_for(K.Id.ASD, KEY_2, 3), 1, "the number row works under any scheme")
	_eq(K.slot_for(K.Id.ARROWS, KEY_J, 3), -1, "an unmapped key picks nothing")
	# A save written by a version with more schemes than this one, or a
	# corrupted one, must not index off the end of the table.
	_ok(K.clamp_id(99) >= 0 and K.clamp_id(99) < K.NAMES.size(),
		"a stored scheme out of range lands on a real one")
	_ok(K.clamp_id(-4) >= 0, "and so does a negative one")
	_ok(not K.cap(99, 0).is_empty(), "an out-of-range scheme still draws a cap")

	# End to end, through the real handler and the real strip.
	main.start_run()
	# Fetched by node rather than as main._input: on a Node that name already
	# belongs to the engine's own input callback, and GDScript resolves it to
	# the method.
	var handler: InputHandler = main.get_node("InputHandler")
	handler.key_scheme = KeyScheme.Id.QWE
	handler.enabled = true
	var slots: int = main._blocks.choices().size()
	_ok(slots >= 3, "the strip offers at least three shapes")

	var laid: int = board.pipes.size()
	var before: int = main._blocks.chosen_slot()
	var target: int = 2 if before != 2 else 0
	var event := InputEventKey.new()
	event.pressed = true
	event.keycode = KeyScheme.KEYS[KeyScheme.Id.QWE][target]
	handler._key(event)
	_eq(main._blocks.chosen_slot(), target, "a key press moves the choice")

	# Held down, it is one choice and not a stream of them: the echo repeats
	# would otherwise re-point the strip sixty times a second.
	var echo := InputEventKey.new()
	echo.pressed = true
	echo.echo = true
	echo.keycode = KeyScheme.KEYS[KeyScheme.Id.QWE][before]
	handler._key(echo)
	_eq(main._blocks.chosen_slot(), target, "a repeat is not a second choice")

	# Choosing is free; only placing spends the turn.
	_eq(board.pipes.size(), laid, "choosing places nothing")
	main._show_menu()


## The ad policy, driven through a stand-in for the platform.
##
## Worth testing without a browser because the rule is a counting rule — every
## second death, never inside the platform's cooldown, and never twice for one
## death — and counting rules go wrong quietly.
func _check_ads() -> void:
	# Fetched by name, not written as `Yandex`: this file is compiled before the
	# autoloads are stood up, so naming one would fail to compile — the same
	# reason GameState is reached for the same way throughout.
	var ya: Node = root.get_node("Yandex")
	var sdk: GDScript = load("res://scripts/yandex_sdk.gd")
	var cooldown: float = sdk.INTERSTITIAL_COOLDOWN

	_ok(not ya.rewarded_is_real(), "off the platform there is no ad to watch")

	var bridge := FakeBridge.new()
	ya.install_test_bridge(bridge)

	var closes := [0]
	var on_close := func() -> void: closes[0] += 1
	ya.interstitial_closed.connect(on_close)

	ya._deaths = 0
	ya._last_interstitial = -cooldown
	ya.note_death()
	_eq(bridge.interstitials, 0, "the first death is left alone")
	_eq(closes[0], 1, "and still answers, so the card is not stranded")

	ya.note_death()
	_eq(bridge.interstitials, 1, "the second carries the ad")
	_eq(closes[0], 2, "and answers when it closes")
	_ok(not ya.get_tree().paused, "the tree is handed back afterwards")

	# Inside the cooldown the platform would refuse it anyway, so the game does
	# not ask — and the card must still appear.
	ya.note_death()
	ya.note_death()
	_eq(bridge.interstitials, 1, "a second ad inside the cooldown is not asked for")
	_eq(closes[0], 4, "but every death still answers")

	# A rewarded video watched to the end is the ad that death owed.
	ya.credit_ad_shown()
	_eq(ya._deaths, 0, "watching one resets the count")

	ya.interstitial_closed.disconnect(on_close)

	var granted := [false]
	var on_reward := func(ok: bool) -> void: granted[0] = ok
	ya.rewarded_result.connect(on_reward)
	bridge.reward = true
	ya.show_rewarded()
	_ok(granted[0], "a video watched to the end pays out")
	bridge.reward = false
	ya.show_rewarded()
	_ok(not granted[0], "a skipped one does not")
	ya.rewarded_result.disconnect(on_reward)

	# Back to the no-platform arrangement the rest of the checks expect.
	ya._bridge = null
	ya.available = false
	ya._deaths = 0
	ya._last_interstitial = -cooldown


## The Russian build is the one the platform serves by default, so the strings
## it is made of have to be there. Spot-checked rather than exhaustive: what
## this is guarding against is the catalogue failing to load at all, and the
## rules card, whose entry spans several lines and is the one shape of CSV that
## quietly comes back empty.
func _check_translations() -> void:
	var was := TranslationServer.get_locale()
	TranslationServer.set_locale("ru")
	for key: String in ["Out of fuel", "Try Again", "START", "CHOOSE",
			"Reach row %d", "First Run", "Collect %d crystals"]:
		_ok(tr(key) != key, "ru: %s is translated" % key)
	var rules := tr("HOW_TO_RULES")
	_ok(rules != "HOW_TO_RULES", "ru: the rules card has text")
	_ok(rules.count("\n") >= 4, "ru: and kept its lines")

	TranslationServer.set_locale("en")
	_eq(tr("Try Again"), "Try Again", "en: the source strings come back unchanged")
	_ok(tr("HOW_TO_RULES").begins_with("[color="), "en: the rules card too")
	TranslationServer.set_locale(was)


## A stand-in for the platform, so the ad policy can be driven without one.
## Answers immediately, which is the case the real bridge cannot promise and
## the one the counting has to be right in.
class FakeBridge extends RefCounted:
	var interstitials: int = 0
	var reward: bool = true
	var _on_rewarded: Callable
	var _on_interstitial: Callable
	var _on_load: Callable

	func register(rewarded: Callable, interstitial: Callable, load_cb: Callable) -> void:
		_on_rewarded = rewarded
		_on_interstitial = interstitial
		_on_load = load_cb

	func isReady() -> bool:
		return true

	func getLang() -> String:
		return "ru"

	func ready() -> void:
		pass

	func gameplayStart() -> void:
		pass

	func gameplayStop() -> void:
		pass

	func showInterstitial() -> void:
		interstitials += 1
		_on_interstitial.call([true])

	func showRewarded() -> void:
		_on_rewarded.call([reward])

	func save(_text: String) -> void:
		pass

	func load() -> void:
		_on_load.call([""])


## Meeting a station goal has to end the run as a win, not as a crash. This
## went wrong once already: the end-of-run branch showed the game-over card
## unconditionally, so clearing a station looked exactly like dying on it.
func _check_station_finish() -> void:
	var state: Node = root.get_node("GameState")
	var saved_cleared: int = state.levels_cleared
	var saved_crystals: int = state.crystals
	state.levels_cleared = 0
	state.crystals = 0

	main._select_level(1)
	main.start_run(2)
	main.started = true
	var level: Level = main.active_level
	_ok(level != null, "a station is loaded")

	main.distance = level.goal_target - 1
	main._board.max_row = main.distance
	main._check_station_goal()
	_eq(main.state, 1, "one short of the goal keeps the run going")

	main.distance = level.goal_target
	main._board.max_row = main.distance
	main._check_station_goal()
	_eq(main.state, 2, "meeting it ends the run")
	_ok(not main._pending_clear.is_empty(), "and files it as a clear, not a crash")
	_eq(state.levels_cleared, 1, "the line advances")
	_eq(main._death_reason, "", "with no crash reason attached")
	_ok(main._death_pause > main.DEATH_PAUSE,
		"and a longer beat than a death, for the celebration")

	# The card chosen from that state must be the cleared one.
	main._show_end_card()
	_eq((main._overlay.get_node("%RetryButton") as Button).text, "Next",
		"the cleared card offers the next station")
	_ok(not (main._overlay.get_node("%ContinueButton") as Button).visible,
		"and never offers a continue on a win")

	state.levels_cleared = saved_cleared
	state.crystals = saved_crystals
	state.save_game()
	main._show_menu()


## --script skips project autoloads, so stand them up by hand.
func _stand_up_autoloads() -> void:
	for entry in [["GameState", "res://scripts/game_state.gd"]]:
		if root.has_node(entry[0]):
			continue
		var node: Node = load(entry[1]).new()
		node.name = entry[0]
		root.add_child(node)
