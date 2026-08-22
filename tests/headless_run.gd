## Headless smoke test: drives several full runs with a greedy bot and reports
## what happened. Not a balance measurement — the bot only extends the track in
## front of it and cannot plan a route, exactly the limitation the spec warns
## about in section 10.
##
##   godot --headless --path . --script res://tests/headless_run.gd
extends SceneTree

const RUNS := 5
const MAX_FRAMES_PER_RUN := 20000
## Bot acts at most this often, so it cannot carpet the board in one second.
const ACT_INTERVAL := 8

var main: Node
var run_index: int = 0
var frames: int = 0
var placed: int = 0
var dumped: int = 0
var cooldown: int = 0
var deaths: Dictionary = {}


func _initialize() -> void:
	# --script skips project autoloads, so stand GameState up by hand.
	_stand_up_autoloads()
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(_delta: float) -> bool:
	frames += 1
	if frames == 3:
		_begin_run()
		return false
	if frames < 3:
		return false

	if main.state == 2:  # DEAD
		_report()
		run_index += 1
		if run_index >= RUNS:
			_summary()
			return true
		_begin_run()
		return false

	if frames > MAX_FRAMES_PER_RUN:
		print("!! run %d survived %d frames" % [run_index + 1, MAX_FRAMES_PER_RUN])
		_report()
		return true

	if cooldown > 0:
		cooldown -= 1
	else:
		_bot_step()
	return false


func _begin_run() -> void:
	frames = 4
	placed = 0
	dumped = 0
	cooldown = 0
	main.start_run()


func _bot_step() -> void:
	var board: Board = main._board
	var offer: PipeOffer = main._offer
	var cart: Cart = main._cart

	var ahead := board.frontier(cart.cell(), cart.entry)
	if ahead.is_empty():
		return

	var joint: Vector2i = ahead["cell"]
	var need: int = ahead["need"]

	if not ahead["blocked"] and board.can_place(joint):
		var pick := _best_choice(offer, need)
		if pick >= 0:
			main._on_offer_chosen(pick)
			main._try_place(joint)
			placed += 1
			cooldown = ACT_INTERVAL
			return

	# Nothing on offer serves the joint. Spend one strictly behind the cart —
	# never on the joint it still needs — to bring a fresh offer up.
	for row in range(board.max_row - main.balance.place_below, cart.row):
		for col in main.balance.cols:
			var spot := Vector2i(col, row)
			if spot == joint:
				continue
			if board.get_pipe(spot) == null and board.can_place(spot):
				main._try_place(spot)
				dumped += 1
				cooldown = ACT_INTERVAL
				return



## Which shape to take, or -1 when none of them serves the joint.
##
## Climbing beats turning, and turning beats being sent back down. With three
## shapes to choose between, taking whichever fits first is a turn more often
## than not, and a route that turns every move walks itself sideways out of the
## build window — which measures the bot, not the game.
func _best_choice(offer: PipeOffer, need: int) -> int:
	var best := -1
	var best_rank := -1
	for i in offer.choices.size():
		var exit: int = PipeDefs.exit_side(offer.choices[i], need)
		if exit == PipeDefs.NO_EXIT:
			continue
		var rank := 1
		if exit == PipeDefs.Side.U:
			rank = 2
		elif exit == PipeDefs.Side.D:
			rank = 0
		if rank > best_rank:
			best_rank = rank
			best = i
	return best


func _report() -> void:
	var board: Board = main._board
	var reason: String = main._death_reason
	deaths[reason] = int(deaths.get(reason, 0)) + 1
	print("run %d | %-13s score %4d | cells %4d | row %4d | crystals %2d"
		% [run_index + 1, reason, main.score, main.cells_run, board.max_row,
			main.crystals_collected]
		+ " | fuel %5.1f | speed %.2f | placed %3d (+%3d dumped)"
			% [main.fuel, main.speed, placed, dumped]
		+ " | pipes %4d rocks %3d" % [board.pipes.size(), board.rocks.size()])


func _summary() -> void:
	print("--- %d runs ---" % RUNS)
	for reason: String in deaths:
		print("  %-13s x%d" % [reason, deaths[reason]])
	print("  best saved   : %d" % root.get_node("GameState").best)


## --script skips project autoloads, so stand them up by hand.
func _stand_up_autoloads() -> void:
	for entry in [["GameState", "res://scripts/game_state.gd"]]:
		if root.has_node(entry[0]):
			continue
		var node: Node = load(entry[1]).new()
		node.name = entry[0]
		root.add_child(node)
