## Captures the menu panels, which the gameplay screenshot run never opens.
##
##   godot --path . --resolution 450x800 --script res://tests/screenshot_ui.gd
extends SceneTree

const SHOTS := {
	30: "menu-shop",
	70: "menu-settings",
	110: "menu-howto",
}

var main: Node
var frames: int = 0
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
	# Untyped on purpose: naming MainMenu here would pull main_menu.gd into
	# this script's compile, before the GameState autoload it reads exists.
	var menu: Node = main._menu

	if frames == 10:
		# Enough crystals that the shop shows both affordable and out-of-reach
		# rows rather than a wall of greyed-out buttons.
		root.get_node("GameState").crystals = 210
		menu._toggle(menu._upgrades_panel)
	elif frames == 50:
		menu._toggle(menu._settings_panel)
	elif frames == 90:
		menu._toggle(menu._how_panel)

	if SHOTS.has(frames):
		pending = SHOTS[frames]
	return frames > 130


func _on_post_draw() -> void:
	if pending.is_empty():
		return
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, pending])
	print("saved %s" % pending)
	pending = ""


## --script skips project autoloads, so stand them up by hand.
func _stand_up_autoloads() -> void:
	for entry in [["GameState", "res://scripts/game_state.gd"]]:
		if root.has_node(entry[0]):
			continue
		var node: Node = load(entry[1]).new()
		node.name = entry[0]
		root.add_child(node)
