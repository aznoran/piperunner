## The bottom strip: HOLD pocket on the left, the piece in hand in the middle,
## and the next three behind it. Spec section 09.
##
## Each shape carries its own colour (LocationSkin.shape_colors) so the piece
## in hand is recognisable without reading its outline.
class_name QueueBar
extends Control

## Slot size as a multiple of a board cell, and its hard ceiling in pixels.
const SLOT_SCALE := 1.3
const SLOT_MAX := 100.0
## Preview slots, relative to the main one.
const PREVIEW_SCALE := 0.55
const PREVIEW_GAP := 1.15
const EDGE_MARGIN := 14.0

## Rect of the HOLD slot in screen space, handed to InputHandler.
var hold_rect := Rect2()
## Screen y where the strip begins; touches below it are not board taps.
var strip_top: float = 0.0

var _skin: LocationSkin
var _upcoming: Array[int] = []
var _held: int = PipeQueue.NONE
var _slot: float = 60.0
var _font: Font
var _label_size: int = 16

var _slot_box := StyleBoxFlat.new()
var _empty_box := StyleBoxFlat.new()


func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_skin(Skins.current())
	get_viewport().size_changed.connect(_relayout)
	_relayout()


## Repaints with a new location skin.
func set_skin(skin: LocationSkin) -> void:
	_skin = skin
	_relayout()


func set_cell_size(cell_size: float) -> void:
	_slot = minf(cell_size * SLOT_SCALE, SLOT_MAX)
	_relayout()


func set_contents(upcoming: Array[int], held: int) -> void:
	_upcoming = upcoming
	_held = held
	queue_redraw()


## Anchors the strip above the system home-gesture area (spec section 13).
func _relayout() -> void:
	var viewport := get_viewport_rect().size
	var bottom_inset := SafeArea.insets(viewport).w

	var height := _slot * 1.8
	size = Vector2(viewport.x, height)
	position = Vector2(0.0, viewport.y - height - bottom_inset)

	_label_size = maxi(11, int(_slot * 0.19))
	var radius := int(_slot * 0.16)
	_slot_box.bg_color = _skin.slot_fill
	_slot_box.set_corner_radius_all(radius)
	_slot_box.set_border_width_all(maxi(2, int(_slot * 0.04)))
	_empty_box.bg_color = Color.TRANSPARENT
	_empty_box.set_corner_radius_all(radius)
	_empty_box.set_border_width_all(maxi(2, int(_slot * 0.04)))
	_empty_box.border_color = Color(_skin.warn, 0.5)

	strip_top = position.y
	hold_rect = Rect2(position + _hold_centre() - Vector2(_slot, _slot) * 0.5,
		Vector2(_slot, _slot))
	queue_redraw()


func _row_y() -> float:
	return size.y * 0.5


func _hold_centre() -> Vector2:
	return Vector2(EDGE_MARGIN + _slot * 0.5, _row_y())


## The piece in hand sits left of centre, leaving room for the previews.
func _next_centre() -> Vector2:
	return Vector2(size.x * 0.42, _row_y())


func _draw() -> void:
	var hold_centre := _hold_centre()
	if _held == PipeQueue.NONE:
		draw_style_box(_empty_box, Rect2(hold_centre - Vector2(_slot, _slot) * 0.5,
			Vector2(_slot, _slot)))
	else:
		_draw_slot(hold_centre, _slot, _held, false)
	_draw_label("HOLD", hold_centre - Vector2(0.0, _slot * 0.62),
		Color(_skin.warn, 0.7))

	if _upcoming.is_empty():
		return

	var next_centre := _next_centre()
	_draw_slot(next_centre, _slot, _upcoming[0], false)
	_draw_label("NEXT", next_centre - Vector2(0.0, _slot * 0.62),
		Color(1.0, 1.0, 1.0, 0.34))

	var preview := _slot * PREVIEW_SCALE
	var cursor := next_centre.x + _slot * 0.5 + preview * 0.75
	for i in range(1, _upcoming.size()):
		if cursor + preview * 0.5 > size.x - EDGE_MARGIN:
			break  # no room left; better to drop one than to overflow
		_draw_slot(Vector2(cursor, _row_y()), preview, _upcoming[i], true)
		cursor += preview * PREVIEW_GAP


func _draw_slot(centre: Vector2, slot_size: float, type: int, dim: bool) -> void:
	var tint: Color = _skin.shape_color(type)
	var rect := Rect2(centre - Vector2(slot_size, slot_size) * 0.5,
		Vector2(slot_size, slot_size))

	_slot_box.border_color = Color(tint, 0.45) if dim else tint
	_slot_box.bg_color = Color(tint.r, tint.g, tint.b, 0.10 if dim else 0.16)
	draw_style_box(_slot_box, rect)

	var line := Color(tint, 0.55) if dim else tint
	for side: int in PipeDefs.SIDES[type]:
		var step: Vector2i = PipeDefs.DIR[side]
		var offset := Vector2(step.x, -step.y) * slot_size * 0.36
		draw_line(centre, centre + offset, line, slot_size * 0.15)
	draw_circle(centre, slot_size * 0.075, line)


func _draw_label(text: String, centre: Vector2, color: Color) -> void:
	if _font == null:
		return
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		_label_size).x
	draw_string(_font, centre - Vector2(width * 0.5, 0.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, _label_size, color)
