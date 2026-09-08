## Press-drag-release aiming. Spec section 07.
##
## Instant placement on tap does not work: roughly 200 ms passes between seeing
## a cell and touching it, and the board has moved on by then. So the finger
## picks a cell, drags to correct it, and the pipe lands where the finger was
## at the moment it lifted. A mouse is the same gesture with a shorter drag —
## press and release without moving lands on the cell under the cursor — so the
## web build needs nothing extra to place with.
##
## What it does need is a way to *choose* without giving up the mouse, and that
## is the keyboard: one key per slot, per KeyScheme. Choosing and placing are
## separate acts here, so splitting them across two hands costs the design
## nothing and saves a trip down to the strip and back on every turn.
class_name InputHandler
extends Node

signal offer_chosen(index: int)
## The pointer moved with no button down. Desktop only in practice — a finger
## cannot hover — and used to preview the shape without freezing the board.
signal hover_moved(world_position: Vector2)
signal aim_started(world_position: Vector2)
signal aim_moved(world_position: Vector2)
signal aim_released(world_position: Vector2)
signal aim_cancelled

## Gestures are ignored unless a run is in progress.
var enabled: bool = false
## Screen-space rect of each shape on offer. Touching one chooses it and
## swallows the gesture.
var offer_rects: Array[Rect2] = []
## Screen y below which touches belong to the offer strip, not the board.
var offer_strip_top: float = INF
## Which keyboard layout picks the slots, per KeyScheme. Pushed in by Main for
## the same reason OfferBar's copy is: this script has a class_name and is
## compiled before the autoloads exist, so it cannot name one.
var key_scheme: int = KeyScheme.Id.QWE

var _active_touch: int = -1


func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return

	if event is InputEventKey:
		_key(event as InputEventKey)
		return

	if event is InputEventMouseMotion and _active_touch == -1:
		var motion := event as InputEventMouseMotion
		if motion.button_mask == 0 and motion.position.y < offer_strip_top:
			hover_moved.emit(_to_world(motion.position))
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_begin(touch.index, touch.position)
		elif touch.index == _active_touch:
			_active_touch = -1
			aim_released.emit(_to_world(touch.position))
		get_viewport().set_input_as_handled()

	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if drag.index == _active_touch:
			aim_moved.emit(_to_world(drag.position))
			get_viewport().set_input_as_handled()


## One key per slot. Repeats are dropped: holding a key down is not a stream of
## choices, it is one.
func _key(event: InputEventKey) -> void:
	if not event.pressed or event.echo:
		return
	var slot := KeyScheme.slot_for(key_scheme, event.keycode,
		offer_rects.size())
	if slot < 0:
		return
	offer_chosen.emit(slot)
	get_viewport().set_input_as_handled()


func _begin(index: int, position: Vector2) -> void:
	if _active_touch != -1:
		return  # one finger at a time; extra touches are ignored

	for i in offer_rects.size():
		if offer_rects[i].has_point(position):
			offer_chosen.emit(i)
			return

	if position.y >= offer_strip_top:
		return  # offer strip, not the board

	_active_touch = index
	aim_started.emit(_to_world(position))


## Drops any gesture in flight — used when a run ends mid-drag.
func cancel() -> void:
	if _active_touch == -1:
		return
	_active_touch = -1
	aim_cancelled.emit()


func _to_world(screen_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_position
