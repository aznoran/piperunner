## Renders a handful of candidate tiles side by side at a readable size.
extends SceneTree

const ROOT := "/private/tmp/claude-501/-Users-antonsavchenko-gamegodot/493fe8c7-1bf7-4d36-9791-7a96883f1355/scratchpad/assets/pixel_platformer"
const OUT := "/private/tmp/claude-501/-Users-antonsavchenko-gamegodot/493fe8c7-1bf7-4d36-9791-7a96883f1355/scratchpad/picks.png"
const SCALE := 6

# folder, index
const PICKS := [
	["Tiles", 47], ["Tiles", 48], ["Tiles", 8], ["Tiles", 30],
	["Tiles", 31], ["Tiles", 32], ["Tiles", 26],
	["Characters", 18], ["Characters", 19], ["Characters", 20],
	["Characters", 21], ["Characters", 22],
]


func _initialize() -> void:
	var cell := 24 * SCALE
	var sheet := Image.create(cell * PICKS.size(), cell, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.1, 0.1, 0.12, 1.0))

	for i in PICKS.size():
		var path := "%s/%s/tile_%04d.png" % [ROOT, PICKS[i][0], PICKS[i][1]]
		if not FileAccess.file_exists(path):
			print("missing %s" % path)
			continue
		var tile := Image.load_from_file(path)
		tile.resize(cell, cell, Image.INTERPOLATE_NEAREST)
		sheet.blend_rect(tile, Rect2i(0, 0, cell, cell), Vector2i(i * cell, 0))

	sheet.save_png(OUT)
	print("picks: %s" % str(PICKS))
	quit()
