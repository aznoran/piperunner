## The bottom strip: the shapes on offer, one of which the player takes.
##
## Every slot is the same size and every slot is a live target. There is no
## hierarchy to read here the way there was with a queue — no piece in hand, no
## preview trailing off to the right — only a choice to make, so the only thing
## the strip has to say is which shape the next placement spends.
##
## Each shape carries its own colour (LocationSkin.shape_colors) so the chosen
## one is recognisable without reading its outline.
class_name OfferBar
extends Control

## Slot size as a multiple of a board cell, and its hard ceiling in pixels.
const SLOT_SCALE := 1.3
const SLOT_MAX := 100.0
## Gap between slots, as a fraction of one slot.
const SLOT_GAP := 0.34
const EDGE_MARGIN := 14.0

## Screen-space rect of each slot, handed to InputHandler.
var slot_rects: Array[Rect2] = []
## Screen y where the strip begins; touches below it are not board taps.
var strip_top: float = 0.0

var _skin: LocationSkin
var _choices: Array[int] = []
var _selected: int = 0
## True for a window whose shape was carried over from an earlier turn — the
## held state of variant C. Empty, or all false, for the variants where every
## window is dealt fresh each turn.
var _held: Array[bool] = []
## What a slot would like to be, and what it ends up as once the row has been
## made to fit the screen.
var _slot: float = 60.0
var _drawn_slot: float = 60.0
var _centres: Array[Vector2] = []
var _font: Font
var _label_size: int = 16

var _slot_box := StyleBoxFlat.new()
var _marker_box := StyleBoxFlat.new()


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


## The shapes to show, which one is chosen, and which ones are being held from
## an earlier turn. The slot count can change between calls — an upgrade widens
## the offer — so the geometry is rebuilt here and not only when the viewport
## changes.
func set_contents(choices: Array[int], selected: int,
		held: Array[bool] = []) -> void:
	_choices = choices
	_selected = selected
	_held = held
	_relayout()


## Anchors the strip above the system home-gesture area (spec section 13).
func _relayout() -> void:
	if _skin == null or not is_inside_tree():
		return
	var viewport := get_viewport_rect().size
	var bottom_inset := SafeArea.insets(viewport).w

	var height := _slot * 1.8
	size = Vector2(viewport.x, height)
	position = Vector2(0.0, viewport.y - height - bottom_inset)
	strip_top = position.y

	# Corners and caption follow the size the slots end up at, not the size they
	# asked for, or a shrunken row draws with the radius of a full-width one.
	_rebuild_slots()
	_label_size = maxi(11, int(_drawn_slot * 0.19))
	_slot_box.set_corner_radius_all(int(_drawn_slot * 0.16))
	_marker_box.set_corner_radius_all(maxi(2, int(_drawn_slot * 0.05)))
	queue_redraw()


func _row_y() -> float:
	return size.y * 0.5


## Lays the slots out in one centred row, shrinking them rather than letting
## the row run off the edge — four options on a narrow phone is exactly the
## case the upgrade creates.
func _rebuild_slots() -> void:
	_centres.clear()
	slot_rects.clear()
	var count := _choices.size()
	if count == 0:
		return

	var room: float = size.x - EDGE_MARGIN * 2.0
	var span: float = float(count) + SLOT_GAP * float(count - 1)
	_drawn_slot = minf(_slot, room / span)

	var stride: float = _drawn_slot * (1.0 + SLOT_GAP)
	var left: float = (size.x - _drawn_slot * span) * 0.5
	var y := _row_y()
	for i in count:
		var centre := Vector2(left + _drawn_slot * 0.5 + stride * float(i), y)
		_centres.append(centre)
		slot_rects.append(Rect2(
			position + centre - Vector2(_drawn_slot, _drawn_slot) * 0.5,
			Vector2(_drawn_slot, _drawn_slot)))


func _draw() -> void:
	if _choices.is_empty() or _centres.size() != _choices.size():
		return
	for i in _choices.size():
		_draw_slot(_centres[i], _drawn_slot, _choices[i], i == _selected,
			i < _held.size() and _held[i])
	_draw_label("CHOOSE", Vector2(size.x * 0.5, _row_y() - _drawn_slot * 0.66),
		Color(1.0, 1.0, 1.0, 0.34))


func _draw_slot(centre: Vector2, slot_size: float, type: int,
		chosen: bool, held: bool) -> void:
	var tint: Color = _skin.shape_color(type)
	var rect := Rect2(centre - Vector2(slot_size, slot_size) * 0.5,
		Vector2(slot_size, slot_size))

	_slot_box.border_color = tint if chosen else Color(tint, 0.4)
	_slot_box.bg_color = Color(tint.r, tint.g, tint.b, 0.18 if chosen else 0.07)
	_slot_box.set_border_width_all(
		maxi(2, int(slot_size * (0.06 if chosen else 0.035))))
	draw_style_box(_slot_box, rect)

	var line := tint if chosen else Color(tint, 0.5)
	for side: int in PipeDefs.SIDES[type]:
		var step: Vector2i = PipeDefs.DIR[side]
		var offset := Vector2(step.x, -step.y) * slot_size * 0.36
		draw_line(centre, centre + offset, line, slot_size * 0.15)
	draw_circle(centre, slot_size * 0.075, line)

	if held:
		_draw_hold_pip(centre, slot_size, tint)

	if not chosen:
		return
	# An underline as well as the brighter frame: two tints of one colour are
	# not enough, on a phone, to read at a glance which shape the next tap
	# spends — and getting that wrong costs a turn.
	var bar := Vector2(slot_size * 0.5, maxf(3.0, slot_size * 0.07))
	_marker_box.bg_color = tint
	draw_style_box(_marker_box,
		Rect2(centre + Vector2(-bar.x * 0.5, slot_size * 0.62), bar))


## A held window keeps its shape until the player takes from it, and has to say
## so — otherwise the strip looks like it re-deals and simply failed to. One
## small pip in the corner, dim enough to stay out of the way of the shape.
func _draw_hold_pip(centre: Vector2, slot_size: float, tint: Color) -> void:
	var corner := centre + Vector2(slot_size, -slot_size) * 0.34
	draw_circle(corner, maxf(2.0, slot_size * 0.055), Color(tint, 0.85))


func _draw_label(text: String, centre: Vector2, color: Color) -> void:
	if _font == null:
		return
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		_label_size).x
	draw_string(_font, centre - Vector2(width * 0.5, 0.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, _label_size, color)
