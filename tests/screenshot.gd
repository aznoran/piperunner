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


func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir.is_empty():
		out_dir = "/tmp"
	_stand_up_autoloads()
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	RenderingServer.frame_post_draw.connect(_on_post_draw)


func _process(_delta: float) -> bool:
	frames += 1
	if SHOTS.has(frames):
		pending = SHOTS[frames]

	if frames == 40:
		main.start_run()
	elif frames > 90 and main.state == 1:  # PLAYING
		if cooldown > 0:
			cooldown -= 1
		else:
			_bot_step()
	elif frames > 90 and main.state == 2:  # DEAD — start another so shots land
		main.start_run()

	return frames > 720


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
	var queue: PipeQueue = main._queue
	var cart: Cart = main._cart

	var ahead := board.frontier(cart.cell(), cart.entry)
	if ahead.is_empty():
		return
	var joint: Vector2i = ahead["cell"]
	var need: int = ahead["need"]

	if (not ahead["blocked"]
			and PipeDefs.SIDES[queue.current()].has(need)
			and board.can_place(joint)):
		main._try_place(joint)
		cooldown = ACT_INTERVAL
		return
	if queue.held == PipeQueue.NONE:
		main._on_hold_tapped()
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


## --script skips project autoloads, so stand them up by hand.
func _stand_up_autoloads() -> void:
	for entry in [["GameState", "res://scripts/game_state.gd"]]:
		if root.has_node(entry[0]):
			continue
		var node: Node = load(entry[1]).new()
		node.name = entry[0]
		root.add_child(node)
