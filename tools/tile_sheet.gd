## Builds a labelled contact sheet of a tile folder, so the right tile indices
## can be picked by eye instead of guessed from a packed sheet.
##
##   godot --headless --path . --script res://tools/tile_sheet.gd
extends SceneTree

const SOURCE := "/private/tmp/claude-501/-Users-antonsavchenko-gamegodot/493fe8c7-1bf7-4d36-9791-7a96883f1355/scratchpad/assets/pixel_platformer/Tiles"
const OUT := "/private/tmp/claude-501/-Users-antonsavchenko-gamegodot/493fe8c7-1bf7-4d36-9791-7a96883f1355/scratchpad/contact.png"
const TILE := 18
const SCALE := 3
const COLS := 20
const ROWS := 9


func _initialize() -> void:
	var cell := TILE * SCALE
	var sheet := Image.create(COLS * cell, ROWS * cell, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.12, 1.0))

	for row in ROWS:
		for col in COLS:
			var index := row * COLS + col
			var path := "%s/tile_%04d.png" % [SOURCE, index]
			if not FileAccess.file_exists(path):
				continue
			var tile := Image.load_from_file(path)
			if tile == null:
				continue
			tile.resize(cell, cell, Image.INTERPOLATE_NEAREST)
			sheet.blend_rect(tile, Rect2i(0, 0, cell, cell),
				Vector2i(col * cell, row * cell))

	sheet.save_png(OUT)
	print("contact sheet: %s (%dx%d, tile %d = row*%d + col)"
		% [OUT, sheet.get_width(), sheet.get_height(), 0, COLS])
	quit()
