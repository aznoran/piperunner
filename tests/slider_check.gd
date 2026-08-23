## Checks the tuning slider ignores everything except a deliberate sideways
## drag. The panel is a tall scrolling list of these, so a slider that reacts
## to a tap or to a vertical swipe silently rewrites settings while the tester
## is only scrolling past them — which is the bug this control exists to fix.
##
##   godot --headless --path . --script res://tests/slider_check.gd
extends SceneTree

var checks := 0
var failures := 0


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _slider() -> TuningSlider:
	var slider := TuningSlider.new()
	root.add_child(slider)
	slider.size = Vector2(300, 40)
	slider.setup(0.0, 100.0, 1.0, 50.0)
	return slider


func _press(slider: TuningSlider, at: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.pressed = true
	event.position = at
	slider._gui_input(event)


func _release(slider: TuningSlider, at: Vector2) -> void:
	var event := InputEventScreenTouch.new()
	event.pressed = false
	event.position = at
	slider._gui_input(event)


func _drag(slider: TuningSlider, to: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.position = to
	slider._gui_input(event)


func _initialize() -> void:
	var start := Vector2(150, 20)

	# A tap: press and release with no travel at all.
	var tap := _slider()
	_press(tap, start)
	_release(tap, start)
	_check(tap.value == 50.0, "a tap leaves the value alone, got %s" % tap.value)

	# A scroll: straight down the panel, over the slider on the way past.
	var scrolled := _slider()
	_press(scrolled, start)
	for step in [10, 30, 60, 120]:
		_drag(scrolled, start + Vector2(2, step))
	_release(scrolled, start + Vector2(2, 120))
	_check(scrolled.value == 50.0,
		"a vertical swipe leaves the value alone, got %s" % scrolled.value)

	# A deliberate slide.
	var slid := _slider()
	_press(slid, start)
	for step in [10, 25, 60]:
		_drag(slid, start + Vector2(step, 1))
	_check(slid.value > 50.0, "a sideways drag moves the value, got %s" % slid.value)

	# Once a gesture has been judged a scroll it stays one, even if the finger
	# later wanders sideways — otherwise a curved swipe still nudges the value.
	var curved := _slider()
	_press(curved, start)
	for point in [Vector2(1, 40), Vector2(20, 80), Vector2(90, 110)]:
		_drag(curved, start + point)
	_check(curved.value == 50.0,
		"a swipe that curves does not become a slide, got %s" % curved.value)

	print("--- %d checks, %d failed ---" % [checks, failures])
	quit()
