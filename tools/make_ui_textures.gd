## Bakes the button faces. StyleBoxFlat cannot do a gradient, and a flat
## rectangle is exactly what made the first bar look cheap — so the fill is a
## texture: light at the top, darker at the bottom, with a hard lip along the
## base and a highlight along the top edge.
##
## The texture is greyscale; each button tints it through the stylebox's
## modulate, so one file serves every colour in every location skin.
##
##   godot --headless --path . --script res://tools/make_ui_textures.gd
extends SceneTree

const SIZE := 128
## Kept well under half the texture, or the 9-patch insets overlap on a
## 56 px key and the corners round into a circle.
const RADIUS := 18
const LIP := 11
const OUT := "res://art/ui/tab_face.png"


func _initialize() -> void:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))

	for y in SIZE:
		var shade := _shade(y)
		for x in SIZE:
			var coverage := _coverage(x, y)
			if coverage <= 0.0:
				continue
			image.set_pixel(x, y, Color(shade, shade, shade, coverage))

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/ui"))
	var error := image.save_png(OUT)
	print("tab face: %s" % ("ok" if error == OK else str(error)))
	quit()


## Vertical shading: a bright top edge, a gentle falloff through the body, then
## the lip — the part that reads as depth.
func _shade(y: int) -> float:
	if y >= SIZE - LIP:
		return 0.42
	if y <= 2:
		return 1.0
	var t := float(y) / float(SIZE - LIP)
	return lerpf(0.95, 0.66, t)


## Rounded-rect coverage with a soft edge, so the corners are not stair-stepped
## once the texture is stretched across a button.
func _coverage(x: int, y: int) -> float:
	var half := SIZE * 0.5
	var dx: float = absf(x + 0.5 - half) - (half - RADIUS)
	var dy: float = absf(y + 0.5 - half) - (half - RADIUS)
	var distance: float = 0.0
	if dx > 0.0 and dy > 0.0:
		distance = sqrt(dx * dx + dy * dy)
	else:
		distance = maxf(dx, dy)
	return clampf(RADIUS - distance + 0.5, 0.0, 1.0)
