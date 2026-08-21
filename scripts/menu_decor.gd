## Background tracks for the title screen.
##
## The menu camera looks higher up than the game one, so the player sees less
## of the world ahead, not more — the screen was one lone rail on an empty
## grid. These are disused lines running past the cart: dimmer, off to the
## sides, never interactive, and gone the moment a run starts.
class_name MenuDecor
extends Node2D

## Alpha the tracks settle at. Low enough to stay scenery.
const RESTING_ALPHA := 0.5

var _skin: LocationSkin
var _cell: float = 100.0
var _cols: int = 7
## Column, start row, length — laid out by hand so the shapes read as routes
## somebody once built rather than as noise.
const LINES := [
	[0, -6, 15], [1, 4, 7], [5, -4, 11], [6, 3, 9],
]
## Corners, as column and row, to break the verticals into elbows.
const ELBOWS := [[0, 5], [1, 9], [5, 4], [6, 10]]


func setup(skin: LocationSkin, cell_size: float, columns: int) -> void:
	_skin = skin
	_cell = cell_size
	_cols = columns
	queue_redraw()


func _draw() -> void:
	if _skin == null:
		return
	var shell := Color(_skin.pipe_shell, 0.55)
	var core := Color(_skin.pipe_core, 0.4)

	for line: Array in LINES:
		var col: int = line[0]
		var from: int = line[1]
		var length: int = line[2]
		var x: float = col * _cell + _cell * 0.5
		var top: float = -(from + length) * _cell
		var bottom: float = -from * _cell
		draw_line(Vector2(x, top), Vector2(x, bottom), shell, _cell * 0.3)
		draw_line(Vector2(x, top), Vector2(x, bottom), core, _cell * 0.08)

	for elbow: Array in ELBOWS:
		var col: int = elbow[0]
		var row: int = elbow[1]
		var centre := Vector2(col * _cell + _cell * 0.5, -row * _cell)
		var reach: float = _cell * 0.5 * (1.0 if col < _cols / 2 else -1.0)
		draw_line(centre, centre + Vector2(reach, 0.0), shell, _cell * 0.3)
		draw_line(centre, centre + Vector2(reach, 0.0), core, _cell * 0.08)
		draw_circle(centre, _cell * 0.15, shell)
