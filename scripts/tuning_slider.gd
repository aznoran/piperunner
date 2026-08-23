## A slider that only moves when you mean it.
##
## The stock HSlider jumps to wherever it was touched and starts tracking
## immediately, which on a phone makes a scrollable panel of them unusable: a
## finger dragged down the list lands on a slider on the way past and drags it
## sideways by a pixel or two, and half a dozen settings quietly change while
## you were only scrolling. There is no property that turns that off — the jump
## lives in Slider's own input handler — so this draws and handles itself.
##
## The rule is: a press does nothing at all. The value only starts moving once
## the finger has travelled far enough horizontally to be unambiguous, and if
## it goes vertically first the slider takes its hands off entirely and lets
## the scroll container have the gesture. So a tap is never a change, and a
## scroll is never a change.
class_name TuningSlider
extends Control

signal value_changed(value: float)

## Travel before a gesture counts as one thing or the other. Roughly a finger's
## width of slack: below this on a phone, horizontal and vertical intent cannot
## be told apart.
const TAKEOVER := 14.0
## Track and knob geometry.
const TRACK_HEIGHT := 6.0
const KNOB_RADIUS := 13.0

var min_value: float = 0.0
var max_value: float = 1.0
var step: float = 0.01
var value: float = 0.0

## Set while a press is live and the gesture could still become a drag.
var _armed: bool = false
## Set once the gesture has committed to being a slide.
var _sliding: bool = false
## Where the finger was, and what the value was, at the moment of commitment.
var _grab_x: float = 0.0
var _grab_value: float = 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(0, KNOB_RADIUS * 2.0 + 8.0)
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(low: float, high: float, increment: float, start: float) -> void:
	min_value = low
	max_value = maxf(high, low + 0.0001)
	step = maxf(increment, 0.0001)
	set_value_silently(start)


## Moves the knob without reporting it, for a reset or an external change.
func set_value_silently(to: float) -> void:
	value = _snap(to)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventScreenTouch:
		var pressed: bool = event.pressed
		if pressed:
			# Deliberately not accepted. The gesture may yet turn out to be a
			# scroll, and swallowing the press here would stop the container
			# from ever seeing it.
			_armed = true
			_sliding = false
			_grab_x = event.position.x
			_grab_value = value
		else:
			if _sliding:
				accept_event()
			_armed = false
			_sliding = false
			queue_redraw()
		return

	if not (event is InputEventMouseMotion or event is InputEventScreenDrag):
		return
	if not _armed:
		return

	var travel: Vector2 = event.position - Vector2(_grab_x, size.y * 0.5)
	if not _sliding:
		if absf(travel.y) > TAKEOVER and absf(travel.y) > absf(travel.x):
			_armed = false  # a scroll, not a slide: hands off for good
			return
		if absf(event.position.x - _grab_x) < TAKEOVER:
			return
		# Committed. Re-anchor to here so the knob picks up from where it is
		# rather than jumping by the slack that was spent deciding.
		_sliding = true
		_grab_x = event.position.x
		_grab_value = value

	accept_event()
	var span := maxf(_track_width(), 1.0)
	var moved: float = (event.position.x - _grab_x) / span
	var was := value
	value = _snap(_grab_value + moved * (max_value - min_value))
	if value != was:
		queue_redraw()
		value_changed.emit(value)


func _snap(raw: float) -> float:
	var clamped := clampf(raw, min_value, max_value)
	return clampf(min_value + roundf((clamped - min_value) / step) * step,
		min_value, max_value)


func _track_width() -> float:
	return size.x - KNOB_RADIUS * 2.0


func _draw() -> void:
	var mid := size.y * 0.5
	var left := KNOB_RADIUS
	var span := _track_width()
	var fraction: float = (value - min_value) / maxf(max_value - min_value, 0.0001)
	var knob_x: float = left + span * fraction

	var track := Rect2(left, mid - TRACK_HEIGHT * 0.5, span, TRACK_HEIGHT)
	draw_rect(track, Color(1, 1, 1, 0.14), true)
	draw_rect(Rect2(track.position, Vector2(span * fraction, TRACK_HEIGHT)),
		Color(0.35, 0.85, 0.65, 0.85), true)

	# A brighter knob while it is being dragged: on a phone the finger covers
	# it, and the only way to see the slider has taken the gesture is the moment
	# it lets go.
	var knob := Color(0.75, 1.0, 0.9) if _sliding else Color(0.6, 0.9, 0.8)
	draw_circle(Vector2(knob_x, mid), KNOB_RADIUS, knob)
	draw_circle(Vector2(knob_x, mid), KNOB_RADIUS * 0.45, Color(0.05, 0.09, 0.12))
