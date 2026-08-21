## Paints the location's sky, rebuilt whenever the skin changes.
extends TextureRect


func _ready() -> void:
	set_skin(Skins.current())


## Repaints with a new location skin.
func set_skin(skin: LocationSkin) -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	gradient.colors = PackedColorArray([skin.bg_top, skin.bg_mid, skin.bg_bottom])

	var ramp := GradientTexture2D.new()
	ramp.gradient = gradient
	ramp.width = 4
	ramp.height = 1024
	ramp.fill_to = Vector2(0.0, 1.0)
	texture = ramp
