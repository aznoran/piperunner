## Draws the app icon from the game's own palette, so there is no hand-made
## asset to keep in sync with the skin.
##
##   godot --headless --path . --script res://tools/make_icon.gd
extends SceneTree

const SIZE := 1024


func _initialize() -> void:
	var skin: LocationSkin = load(Skins.DEFAULT_SKIN)
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)

	# Background: the same top-to-bottom ramp the game plays over.
	for y in SIZE:
		var mix := float(y) / float(SIZE)
		var row: Color = (skin.bg_top.lerp(skin.bg_mid, mix / 0.55) if mix < 0.55
			else skin.bg_mid.lerp(skin.bg_bottom, (mix - 0.55) / 0.45))
		image.fill_rect(Rect2i(0, y, SIZE, 1), row)

	# A crossroads pipe: shell, then the bright core, exactly as on the board.
	var shell := int(SIZE * 0.30)
	var core := int(SIZE * 0.10)
	var centre := SIZE / 2

	image.fill_rect(Rect2i(centre - shell / 2, 0, shell, SIZE), skin.pipe_shell)
	image.fill_rect(Rect2i(0, centre - shell / 2, SIZE, shell), skin.pipe_shell)
	image.fill_rect(Rect2i(centre - core / 2, 0, core, SIZE), skin.pipe_core_used)
	image.fill_rect(Rect2i(0, centre - core / 2, SIZE, core), skin.pipe_core_used)

	# The cart, parked in the middle.
	var cart := int(SIZE * 0.17)
	var window := int(cart * 0.38)
	image.fill_rect(Rect2i(centre - cart / 2, centre - cart / 2, cart, cart),
		skin.cart_body)
	image.fill_rect(Rect2i(centre - window / 2, centre - window / 2, window, window),
		skin.cart_window)

	var error := image.save_png("res://art/icon.png")
	print("icon written: %s" % ("ok" if error == OK else str(error)))
	quit()
