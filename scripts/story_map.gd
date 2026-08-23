## The line, drawn as a board.
##
## Story mode used to be a list of buttons, which said nothing the numbers on
## them did not already say. This is the same twelve stations laid out on a
## grid of cells with real pipe in them — the same grid, the same shapes, the
## same shell-and-core the game draws during a run. Nothing here is a diagram
## of the game; it is the game's own furniture, standing still.
##
## Which means the map needs no legend. A cell the cart has run through is
## flooded, in the colours a played pipe takes, and a cell ahead of it is not —
## so how far along the line you are reads exactly the way how far along a run
## you are reads. A station is a crystal sitting in its cell, taken or not.
##
## The route is a serpentine: one row of cells left to right, an elbow at the
## end, the next row right to left. Linear, with no branches — there is one
## line, and the only question the map answers is how much of it is behind you.
class_name StoryMap
extends Control

signal station_picked(number: int)

## Cells across. Narrower than the board's seven on purpose: the panel is
## inset, and five cells keep the pipe as chunky here as it is in a run.
const COLS := 5
## Which columns of a row carry a station: the two ends, which are exactly the
## cells where the line turns. So every station is an elbow, and the run
## between two of them is a straight stretch of pipe — which is what a row of
## this game looks like anyway.
const STATION_COLS := [0, 4]
## Cell size is chosen to fill the panel, within these.
const CELL_MIN := 74.0
const CELL_MAX := 132.0
const EDGE := 26.0

var _skin: LocationSkin
var _tint: Color = Color.WHITE
var _font: Font
var _time: float = 0.0

## The route, in order: one entry per cell, each {cell, type, station}.
## `station` is the level number, or 0 for a cell the line only passes through.
var _route: Array = []
## Where each station sits, by level number, for hit testing.
var _spots: Dictionary = {}
## The station the cart is parked at, and how far along the route that is.
var _here: int = 1
var _here_index: int = 0

var _cell: float = 96.0
var _origin := Vector2.ZERO
var _rows: int = 1
var _grid_box := StyleBoxFlat.new()


func _ready() -> void:
	_font = ThemeDB.fallback_font
	mouse_filter = Control.MOUSE_FILTER_STOP
	_grid_box.bg_color = Color.TRANSPARENT


func _process(delta: float) -> void:
	# Only the crystals and the cart move, and only while the map is up.
	if not visible:
		return
	_time += delta
	queue_redraw()


## Rebuilds the route from the progress as it now stands. Cheap enough to call
## whenever the panel opens, which is the only time it can have changed.
func refresh(skin: LocationSkin, tint: Color) -> void:
	_skin = skin
	_tint = tint
	_here = Levels.count()
	for level in Levels.catalogue():
		if not Levels.is_cleared(GameState, level.number):
			_here = level.number
			break
	_relayout()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_relayout()


# --- the route ----------------------------------------------------------

func _relayout() -> void:
	_route.clear()
	_spots.clear()
	var total := Levels.count()
	if total == 0:
		return

	_rows = int(ceil(float(total) / float(STATION_COLS.size())))

	# The scroll's size, not this control's: inside a scroll a control is sized
	# to its content, so asking itself how tall it is only echoes back whatever
	# it asked for last time.
	var room := get_parent_area_size()
	_cell = clampf(minf((room.x - EDGE * 2.0) / float(COLS),
		(room.y - EDGE * 2.0) / float(_rows)), CELL_MIN, CELL_MAX)
	custom_minimum_size = Vector2(0, _cell * float(_rows) + EDGE * 2.0)
	# Centred both ways. On a screen too narrow for the grid to fill the height
	# it should sit in the middle of the panel rather than hang from the top.
	_origin = Vector2(
		maxf((room.x - _cell * float(COLS)) * 0.5, 0.0),
		maxf((room.y - _cell * float(_rows)) * 0.5, EDGE))

	_walk(total)
	queue_redraw()


## Lays the cells down in the order the cart would meet them, and works out
## which pipe shape each one has to be from the turn it makes there.
func _walk(total: int) -> void:
	var cells: Array[Vector2i] = []
	for row in _rows:
		for i in COLS:
			# Odd rows run right to left, so the line doubles back through the
			# elbow at the end rather than jumping the width of the panel.
			var column: int = i if row % 2 == 0 else COLS - 1 - i
			cells.append(Vector2i(column, row))

	var number := 0
	for i in cells.size():
		var cell := cells[i]
		# Entry is the side facing where the cart came from, exit the side
		# facing where it goes next. The two ends of the line have only one
		# neighbour each, so they run straight through.
		var back: Vector2i = cells[i - 1] - cell if i > 0 else Vector2i.ZERO
		var forward: Vector2i = cells[i + 1] - cell if i + 1 < cells.size() \
			else Vector2i.ZERO
		if back == Vector2i.ZERO:
			back = -forward
		if forward == Vector2i.ZERO:
			forward = -back

		var station := 0
		if STATION_COLS.has(cell.x) and number < total:
			number += 1
			station = number
			_spots[station] = _centre(cell)
			if station == _here:
				_here_index = i

		_route.append({
			"cell": cell,
			"type": _shape(_side(back), _side(forward)),
			"station": station,
		})


## The side of a cell a step points at. The board's y runs up and the screen's
## runs down, and this is the one place the two have to be reconciled.
func _side(step: Vector2i) -> int:
	if step.x < 0:
		return PipeDefs.Side.L
	if step.x > 0:
		return PipeDefs.Side.R
	return PipeDefs.Side.D if step.y > 0 else PipeDefs.Side.U


## The pipe that joins those two sides: straight when they are opposite, an
## elbow when they are not. The same seven shapes the player is handed.
func _shape(from: int, to: int) -> int:
	for type: int in PipeDefs.ALL:
		var sides: Array = PipeDefs.SIDES[type]
		if sides.size() == 2 and sides.has(from) and sides.has(to):
			return type
	return PipeDefs.Type.X


func _centre(cell: Vector2i) -> Vector2:
	return _origin + Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5) * _cell


# --- input --------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventMouseButton):
		return
	if not event.pressed:
		return
	for number: int in _spots:
		var centre: Vector2 = _spots[number]
		if event.position.distance_to(centre) > _cell * 0.55:
			continue
		if not Levels.is_unlocked(GameState, number):
			return  # a locked station swallows the tap rather than passing it on
		accept_event()
		station_picked.emit(number)
		return


# --- drawing ------------------------------------------------------------

func _draw() -> void:
	if _skin == null or _route.is_empty():
		return
	_draw_grid()
	for i in _route.size():
		_draw_pipe(i)
	for step: Dictionary in _route:
		if int(step["station"]) > 0:
			_draw_station(step)
	_draw_cart()
	_draw_orders()


## The placement grid, exactly as the board draws it: an outline per cell, at
## the same inset and the same corner radius.
func _draw_grid() -> void:
	_grid_box.set_border_width_all(maxi(1, int(_cell * 0.015)))
	_grid_box.border_color = _skin.grid
	_grid_box.set_corner_radius_all(int(_cell * 0.16))
	for row in _rows:
		for column in COLS:
			var centre := _centre(Vector2i(column, row))
			var side := _cell * 0.84
			draw_style_box(_grid_box,
				Rect2(centre - Vector2(side, side) * 0.5, Vector2(side, side)))


## One pipe, drawn the way Board draws one: a shell out to each open side, a
## cap over the joint, then the core laid over the top of it.
func _draw_pipe(index: int) -> void:
	var step: Dictionary = _route[index]
	var centre: Vector2 = _centre(step["cell"])
	var type: int = int(step["type"])
	# Up to the station the cart is parked at, but not through it: that level
	# has not been cleared, so its pipe has not been run. Flooding it would put
	# green out the far side of a station the player has not beaten yet.
	var flooded: bool = index < _here_index
	var shell: Color = _skin.pipe_shell_used if flooded else _skin.pipe_shell
	var core: Color = _skin.pipe_core_used if flooded else _skin.pipe_core

	var shell_width := _cell * 0.34
	var core_width := _cell * 0.09
	var reach := _cell * 0.5

	for side: int in PipeDefs.SIDES[type]:
		draw_line(centre, centre + _offset(side, reach), shell, shell_width)
	draw_circle(centre, shell_width * 0.5, shell)

	for side: int in PipeDefs.SIDES[type]:
		draw_line(centre, centre + _offset(side, reach), core, core_width)


func _offset(side: int, reach: float) -> Vector2:
	var step: Vector2i = PipeDefs.DIR[side]
	return Vector2(step.x, -step.y) * reach


## A station: the crystal from the board, sitting in its cell. Taken once the
## level is cleared, an empty socket before that, barred while out of reach.
func _draw_station(step: Dictionary) -> void:
	var number: int = int(step["station"])
	var centre: Vector2 = _centre(step["cell"])
	var cleared: bool = Levels.is_cleared(GameState, number)
	var unlocked: bool = Levels.is_unlocked(GameState, number)
	var radius := _cell * 0.28

	if cleared:
		# Taken. The same shaft of light and the same breathing the board gives
		# a crystal, so a cleared station reads from across the room.
		var pulse: float = 1.0 + 0.1 * sin(_time * 4.5 + float(number))
		var beam := _skin.pickup
		beam.a = _skin.pickup_beam_alpha * 2.0
		draw_rect(Rect2(centre.x - _cell * 0.07, centre.y - _cell * 2.2,
			_cell * 0.14, _cell * 2.2), beam)
		draw_circle(centre, radius * pulse, Color(_skin.pickup, 0.9))
		draw_circle(centre, radius * 0.45 * pulse, _skin.pickup_core)
		return

	# Not taken: an empty socket over the pipe, so the cell reads as a place
	# something goes rather than as a wider piece of track.
	var rim: Color = _tint if unlocked else Color(_skin.pipe_shell, 0.7)
	draw_circle(centre, radius, Color(_skin.bg_bottom, 0.94))
	draw_arc(centre, radius, 0.0, TAU, 40, rim, maxf(3.0, _cell * 0.045), true)

	if not unlocked:
		var bar := Vector2(radius * 0.8, maxf(3.0, radius * 0.22))
		draw_rect(Rect2(centre - bar * 0.5, bar), Color(_skin.pipe_shell, 0.9))
		return
	_draw_centred(str(number), centre + Vector2(0.0, _cell * 0.1),
		int(_cell * 0.24), _tint)


## The cart, on the cell it is up to. The board's cart in the board's colours,
## because "you are here" is a thing the game can already say.
func _draw_cart() -> void:
	if not _spots.has(_here):
		return
	var centre: Vector2 = _spots[_here]
	var lift: float = sin(_time * 2.4) * _cell * 0.03
	var at := centre + Vector2(0.0, -_cell * 0.58 + lift)
	var body := Vector2(_cell * 0.28, _cell * 0.22)

	draw_circle(at, _cell * 0.24, Color(_skin.pickup, 0.18))
	draw_rect(Rect2(at - body * 0.5, body), _skin.cart_body)
	draw_rect(Rect2(at - body * 0.5, body), Color(_skin.bg_bottom, 0.9), false,
		maxf(2.0, _cell * 0.03))


## What the station the cart is parked at asks for, written under it.
##
## Only that one. Twelve captions would be a list again, and the only station
## whose terms the player needs before they tap is the one they are about to
## play.
func _draw_orders() -> void:
	if _font == null or not _spots.has(_here):
		return
	var level := Levels.find(_here)
	if level == null:
		return
	var centre: Vector2 = _spots[_here]
	_draw_centred(level.title, centre + Vector2(0.0, _cell * 0.5),
		int(_cell * 0.17), _tint)
	_draw_centred(level.goal_short(), centre + Vector2(0.0, _cell * 0.7),
		int(_cell * 0.14), Color(1.0, 1.0, 1.0, 0.55))


## Centred on `at`, but kept inside the panel: the stations that need a caption
## most are the ones at the ends of a row, where a centred line would hang off
## the edge.
func _draw_centred(text: String, at: Vector2, size_px: int,
		colour: Color) -> void:
	if _font == null:
		return
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1.0,
		size_px).x
	var left := clampf(at.x - width * 0.5, 4.0, maxf(size.x - width - 4.0, 4.0))
	draw_string(_font, Vector2(left, at.y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, size_px, colour)
