## Renders a live run and saves frames to disk, so the port can be eyeballed
## without a device. Pass the output directory via the SHOT_DIR environment
## variable.
##
##   godot --path . --resolution 405x720 --script res://tests/screenshot.gd
extends SceneTree

const ACT_INTERVAL := 8
## Frame numbers to capture, and what each one is meant to show.
const SHOTS := {
	20: "menu",
	70: "start-hint",
	200: "early-run",
	420: "mid-run",
	700: "late-run",
}

var main: Node
var frames: int = 0
var cooldown: int = 0
var out_dir: String = "/tmp"
var pending: String = ""
## Frame the second run began on, so the ghost can be caught while it is still
## on screen — it sits at the row the previous run died on.
var restarted_at: int = -1


func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir.is_empty():
		out_dir = "/tmp"
	_stand_up_autoloads()
	# Start from a clean record so the first run sets one and the later runs
	# have a ghost to race.
	var state: Node = root.get_node("GameState")
	state.best = 0
	state.best_route = PackedInt32Array()
	state.best_row = 0

	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	RenderingServer.frame_post_draw.connect(_on_post_draw)


func _process(_delta: float) -> bool:
	frames += 1
	if SHOTS.has(frames):
		pending = SHOTS[frames]
	if restarted_at > 0 and frames == restarted_at + 40:
		pending = "record-ghost"

	if frames == 40:
		main.start_run()
	elif frames > 90 and main.state == 1:  # PLAYING
		if cooldown > 0:
			cooldown -= 1
		else:
			_bot_step()
	elif frames > 90 and main.state == 2:  # DEAD — start another so shots land
		main.start_run()
		if restarted_at < 0:
			restarted_at = frames

	return frames > 1180


func _on_post_draw() -> void:
	if pending.is_empty():
		return
	var image := root.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, pending]
	image.save_png(path)
	print("saved %s" % path)
	pending = ""


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
			cooldown = ACT_INTERVAL
			return
	for row in range(board.max_row - main.balance.place_below, cart.row):
		for col in main.balance.cols:
			var spot := Vector2i(col, row)
			if spot == joint:
				continue
			if board.get_pipe(spot) == null and board.can_place(spot):
				main._try_place(spot)
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


## --script skips project autoloads, so stand them up by hand.
func _stand_up_autoloads() -> void:
	for entry in [["GameState", "res://scripts/game_state.gd"]]:
		if root.has_node(entry[0]):
			continue
		var node: Node = load(entry[1]).new()
		node.name = entry[0]
		root.add_child(node)
