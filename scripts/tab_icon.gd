## A bar-tab icon, drawn rather than imported: it scales to any density and
## takes the location skin's colour without a second asset.
class_name TabIcon
extends Control

enum Kind { DEPOT, TODAY, PLAY, GOALS, SETUP, PAUSE, BACK, MODES }

@export var kind: Kind = Kind.PLAY

var color: Color = Color.WHITE:
	set(value):
		color = value
		queue_redraw()


func _draw() -> void:
	var unit: float = minf(size.x, size.y)
	var stroke: float = maxf(1.5, unit * 0.09)
	var centre := size * 0.5

	match kind:
		Kind.DEPOT:
			_draw_depot(unit, stroke, centre)
		Kind.TODAY:
			_draw_today(unit, stroke, centre)
		Kind.PLAY:
			_draw_play(unit, centre)
		Kind.GOALS:
			_draw_goals(unit, stroke, centre)
		Kind.SETUP:
			_draw_setup(unit, stroke, centre)
		Kind.PAUSE:
			_draw_pause(unit, centre)
		Kind.BACK:
			_draw_back(unit, stroke, centre)
		Kind.MODES:
			_draw_modes(unit, stroke, centre)


## Sliders — the shorthand for "adjust your loadout" that a player already
## knows, rather than a literal crate.
func _draw_depot(unit: float, stroke: float, centre: Vector2) -> void:
	var half := unit * 0.4
	var gap := unit * 0.3
	var knobs := [-0.22, 0.28, -0.05]
	for i in 3:
		var y: float = centre.y + (i - 1) * gap
		draw_line(Vector2(centre.x - half, y), Vector2(centre.x + half, y), color, stroke)
		var knob := Vector2(centre.x + half * knobs[i], y)
		draw_circle(knob, unit * 0.115, color)


func _draw_today(unit: float, stroke: float, centre: Vector2) -> void:
	var half := unit * 0.38
	var box := Rect2(centre - Vector2(half, half * 0.92), Vector2(half * 2.0, half * 1.84))
	draw_rect(box, color, false, stroke)
	draw_line(Vector2(box.position.x, box.position.y + half * 0.62),
		Vector2(box.end.x, box.position.y + half * 0.62), color, stroke)
	for dx in [-0.45, 0.45]:
		var x: float = centre.x + half * dx
		draw_line(Vector2(x, box.position.y - unit * 0.12),
			Vector2(x, box.position.y + unit * 0.06), color, stroke)


func _draw_play(unit: float, centre: Vector2) -> void:
	var reach := unit * 0.36
	draw_colored_polygon([
		centre + Vector2(-reach * 0.72, -reach),
		centre + Vector2(reach, 0.0),
		centre + Vector2(-reach * 0.72, reach),
	], color)


func _draw_goals(unit: float, stroke: float, centre: Vector2) -> void:
	var top := centre.y - unit * 0.42
	var bottom := centre.y + unit * 0.42
	var pole := centre.x - unit * 0.3
	draw_line(Vector2(pole, top), Vector2(pole, bottom), color, stroke)
	draw_colored_polygon([
		Vector2(pole, top),
		Vector2(pole + unit * 0.58, top + unit * 0.16),
		Vector2(pole, top + unit * 0.34),
	], color)


func _draw_pause(unit: float, centre: Vector2) -> void:
	var bar := unit * 0.16
	var high := unit * 0.62
	for side in [-1.0, 1.0]:
		draw_rect(Rect2(centre.x + side * unit * 0.19 - bar * 0.5, centre.y - high * 0.5,
			bar, high), color)


## Cards in a row: the shape of a mode picker.
func _draw_modes(unit: float, stroke: float, centre: Vector2) -> void:
	var card := Vector2(unit * 0.26, unit * 0.56)
	for offset in [-1.0, 0.0, 1.0]:
		var height: float = card.y * (0.74 if absf(offset) > 0.5 else 1.0)
		var origin := Vector2(centre.x + offset * unit * 0.33 - card.x * 0.5,
			centre.y - height * 0.5)
		draw_rect(Rect2(origin, Vector2(card.x, height)), color, false, stroke)


func _draw_back(unit: float, stroke: float, centre: Vector2) -> void:
	var reach := unit * 0.26
	var tip := Vector2(centre.x - reach * 0.7, centre.y)
	draw_line(tip, Vector2(centre.x + reach, centre.y), color, stroke)
	draw_line(tip, tip + Vector2(reach * 0.8, -reach * 0.8), color, stroke)
	draw_line(tip, tip + Vector2(reach * 0.8, reach * 0.8), color, stroke)


func _draw_setup(unit: float, stroke: float, centre: Vector2) -> void:
	draw_arc(centre, unit * 0.2, 0.0, TAU, 24, color, stroke)
	for i in 8:
		var angle: float = TAU * i / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(centre + direction * unit * 0.3, centre + direction * unit * 0.44,
			color, stroke)
