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

## Cells across — the board's own seven.
##
## This is the whole trick, and getting it wrong is what made the first two
## attempts look like a diagram of the game rather than the game. A cell is
## `width / 7` here exactly as it is in a run, so the grid comes out at the
## same pitch and the pipe at the same weight. At five columns the cells were
## half again as large, the grid read as sparse, and nothing about it recalled
## the field however faithfully each piece was drawn.
const COLS := 7
## The columns the road bounces between. Narrower than the grid on purpose:
## the field is seven cells wide and the road winds up the middle of it, the
## way a played run does, instead of ruling the full width every row.
const ROAD_LEFT := 1
const ROAD_RIGHT := 5
## Cell size is chosen to fill the panel, within these.
const CELL_MIN := 56.0
const CELL_MAX := 124.0
const EDGE := 8.0
## Rows of empty field above the last station and below the first, so the road
## reads as part of a longer line rather than as something that starts and
## stops at the edges of the panel.
const RUN_OFF := 2

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

## How far a finger may travel between press and release and still count as a
## tap rather than as a drag of the map.
const DRAG_SLACK := 16.0

var _pressed_at := Vector2.ZERO
var _pressing: bool = false
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


## Where the panel should be scrolled to for the cart to be in view — the
## station the player is up to, roughly centred.
##
## The line is longer than the panel on purpose, so opening the map at the top
## would show the far end of a story nobody has reached.
func focus_offset(view_height: float) -> float:
	if not _spots.has(_here):
		return 0.0
	var centre: Vector2 = _spots[_here]
	return maxf(centre.y - view_height * 0.5, 0.0)


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

	# One station a row, so the line is as long as the story is and the panel
	# has to be dragged to see the end of it — which is the point. Plus a
	# couple of rows of open field at each end.
	_rows = total + RUN_OFF * 2

	# The scroll's size, not this control's: inside a scroll a control is sized
	# to its content, so asking itself how tall it is only echoes back whatever
	# it asked for last time.
	var room := get_parent_area_size()
	# The board's own pitch: width over seven, exactly as in a run. Everything
	# about how the field reads follows from this one number.
	_cell = clampf(room.x / float(COLS), CELL_MIN, CELL_MAX)
	custom_minimum_size = Vector2(0, _cell * float(_rows) + EDGE * 2.0)
	_origin = Vector2(maxf((room.x - _cell * float(COLS)) * 0.5, 0.0), EDGE)

	_walk(total)
	queue_redraw()


## Lays the cells down in the order the cart would meet them, and works out
## which pipe shape each one has to be from the turn it makes there.
func _walk(total: int) -> void:
	# The road, bottom to top. The cart climbs in a run, so it climbs here:
	# station one sits at the bottom and the last at the top, and progress
	# fills upward exactly as built track does.
	#
	# Each station row runs across to the far side, then the road steps up a
	# row and comes back — so every station is the corner the road turns at,
	# and between two of them is a straight stretch of pipe.
	var cells: Array[Vector2i] = []
	var column := ROAD_LEFT
	for i in total:
		var row: int = _rows - 1 - RUN_OFF - i
		var far: int = ROAD_RIGHT if column == ROAD_LEFT else ROAD_LEFT
		# Across this row, station to station.
		var stride: int = 1 if far > column else -1
		var x := column
		while x != far:
			cells.append(Vector2i(x, row))
			x += stride
		cells.append(Vector2i(far, row))
		column = far

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

		# A station is a corner: the cell the road arrives at and turns up from.
		# Those are the only cells whose two sides are not opposite each other
		# along a row, so they are found rather than counted off.
		var station := 0
		var turns: bool = (back.y != 0 or forward.y != 0) or i == 0 \
			or i == cells.size() - 1
		if turns and number < total:
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

## A station opens on a tap, and only on a tap.
##
## The map is longer than the panel and is meant to be dragged, so a press is
## never acted on and never swallowed — the scroll has to be able to take the
## gesture. Only a release close to where the press landed counts, which is the
## difference between choosing a station and scrolling past it.
func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventMouseButton):
		return
	if event.pressed:
		_pressed_at = event.position
		_pressing = true
		return
	if not _pressing:
		return
	_pressing = false
	if event.position.distance_to(_pressed_at) > DRAG_SLACK:
		return  # that was a drag; the scroll has already acted on it

	for number: int in _spots:
		if event.position.distance_to(_spots[number]) > _cell * 0.5:
			continue
		if not Levels.is_unlocked(GameState, number):
			return  # out of reach: the tap does nothing rather than misfiring
		accept_event()
		station_picked.emit(number)
		return


# --- drawing ------------------------------------------------------------

func _draw() -> void:
	if _skin == null or _route.is_empty():
		return
	_draw_ground()
	_draw_grid()
	for i in _route.size():
		_draw_pipe(i)
	for step: Dictionary in _route:
		if int(step["station"]) > 0:
			_draw_station(step)
	_draw_cart()


## The ground the field stands on.
##
## Without this the map was the board's grid drawn on flat black, and it did
## not read as the game at all: the grid is white at five per cent, which is
## plain against the background gradient and all but invisible against a dark
## panel. So the gradient comes too, in bands — the same three colours the
## background uses, in the same order.
func _draw_ground() -> void:
	var bands := 32
	var height: float = maxf(size.y, 1.0)
	var band := height / float(bands) + 1.0
	for i in bands:
		var t := float(i) / float(bands - 1)
		var shade: Color = _skin.bg_top.lerp(_skin.bg_mid, t / 0.55) if t < 0.55 \
			else _skin.bg_mid.lerp(_skin.bg_bottom, (t - 0.55) / 0.45)
		# Faded in at the very top, so the field arrives out of the panel
		# rather than starting at a ruled line under the heading.
		shade.a = clampf(t * float(bands) / 3.0, 0.0, 1.0)
		draw_rect(Rect2(0.0, height * t, size.x, band), shade)


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
	# Wider than the pipe it sits on, or the socket disappears into the track:
	# the shell is a third of a cell, so anything narrower than that reads as a
	# bulge in the road rather than as a thing in its own right.
	var radius := _cell * 0.36

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

	# Not taken: an empty socket cut into the track. The face is darker than
	# anything around it and the rim lighter, so it reads against the pipe
	# rather than blending into it — the pipe's own shell colour would be
	# invisible here, which is exactly the mistake worth not repeating.
	var rim: Color = _tint if unlocked else Color(_skin.pipe_core, 0.75)
	draw_circle(centre, radius, _skin.bg_bottom)
	draw_arc(centre, radius, 0.0, TAU, 40, rim, maxf(3.0, _cell * 0.055), true)

	if not unlocked:
		# The outline of the crystal that is not there yet — the shape of the
		# thing, empty. A cross would say "blocked", and the station is not
		# blocked, it is simply further along than the player has got.
		var glint := Color(_skin.pipe_core, 0.45)
		var reach := radius * 0.5
		var facets := PackedVector2Array([
			centre + Vector2(0.0, -reach), centre + Vector2(reach, 0.0),
			centre + Vector2(0.0, reach), centre + Vector2(-reach, 0.0),
			centre + Vector2(0.0, -reach)])
		draw_polyline(facets, glint, maxf(2.0, _cell * 0.022), true)
		return
	if number == _here:
		return  # the cart is standing here; a number under it would not be read
	_draw_centred(str(number), centre + Vector2(0.0, _cell * 0.1),
		int(_cell * 0.24), _tint)


## The cart, on the cell it is up to. The board's cart in the board's colours,
## because "you are here" is a thing the game can already say.
func _draw_cart() -> void:
	if not _spots.has(_here):
		return
	var at: Vector2 = _spots[_here]
	var glow: float = 1.0 + 0.12 * sin(_time * 3.2)
	var body := Vector2(_cell * 0.3, _cell * 0.38)

	# In the cell, not hovering over it: on the board the cart sits on the
	# track, and a marker floating above would be the one thing on this map
	# the game does not itself draw.
	draw_circle(at, _cell * 0.34 * glow, Color(_skin.pickup, 0.16))
	draw_rect(Rect2(at - body * 0.5, body), _skin.cart_body)
	var eye := body * 0.42
	draw_rect(Rect2(at - eye * 0.5, eye), _skin.bg_bottom)


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
