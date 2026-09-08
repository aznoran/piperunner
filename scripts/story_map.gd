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
## The columns the road may use. One cell of field is kept either side so the
## line never runs along the edge of the world.
const ROAD_LEFT := 1
const ROAD_RIGHT := 5
## How often a climb turns aside instead of going straight up. This is the
## whole character of the line: at zero it is a ladder, at one it staggers.
const SIDESTEP_CHANCE := 0.44
## Rocks strewn on the field away from the road, as a fraction of free cells.
## Enough to look quarried, not enough to read as a maze.
const RUBBLE := 0.1
## Fixed, so the line is the same line every time the panel opens. A story map
## that reshuffled itself would not be a place.
const MAP_SEED := 20260824
## Cell size is chosen to fill the panel, within these.
const CELL_MIN := 56.0
const CELL_MAX := 124.0
const EDGE := 8.0
## Cells of road beyond the first and last stations. The line is longer than
## the story — it comes up out of somewhere and carries on somewhere — and it
## says so by leaving the panel at full strength rather than by dimming. A road
## that fades out ends; one that is cut off by the edge of the screen carries
## on past it, which is the truer thing and the better-looking one.
const LEAD := 7
## Rows of road drawn past the top and bottom of the grid itself, so the line
## is cut by the edge of the panel rather than stopping at the last cell.
const OVERRUN := 3

var _skin: LocationSkin
var _tint: Color = Color.WHITE
## The save the map is reading progress out of.
var _state: Node
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
## Where along the road the stations begin and end. Outside them the line is
## fading in or out, and is drawn as such.
var _first_station: int = 0
var _last_station: int = 0

## How far a finger may travel between press and release and still count as a
## tap rather than as a drag of the map.
const DRAG_SLACK := 16.0

## Rock cells, the cells the road uses, and which route index carries which
## station. All rebuilt together, all keyed the same way the board keys them.
var _rocks: Dictionary = {}
var _on_road: Dictionary = {}
var _stations: Dictionary = {}

## How much of the flick survives each frame at sixty of them a second.
const GLIDE_DECAY := 0.92

var _pressed_at := Vector2.ZERO
var _pressing: bool = false
## How far the finger has travelled since it came down, and what is left of the
## flick it ended with.
var _travel: float = 0.0
var _glide: float = 0.0
var _cell: float = 96.0
var _origin := Vector2.ZERO
var _rows: int = 1
var _grid_box := StyleBoxFlat.new()
## Rebuilt whenever the skin changes, which is the only thing it depends on.
var _ground: GradientTexture2D
var _rock_box := StyleBoxFlat.new()


func _ready() -> void:
	_font = Fonts.face()
	# The map moves itself rather than leaving it to the scroll. A
	# ScrollContainer only drags on touch where the platform reports a
	# touchscreen, which is true on the phone and false everywhere the thing
	# can be tested — so the behaviour that shipped was the behaviour nobody
	# could check. Owning the gesture makes it the same on both.
	mouse_filter = Control.MOUSE_FILTER_STOP
	_grid_box.bg_color = Color.TRANSPARENT


func _process(delta: float) -> void:
	# Only the crystals and the cart move, and only while the map is up.
	if not visible:
		return
	_time += delta
	if not _pressing and absf(_glide) > 0.5:
		# Coasting. Stops early if it has run into the end of the line, so a
		# hard flick does not leave the map straining against the edge.
		if is_zero_approx(_pan(_glide)):
			_glide = 0.0
		else:
			_glide *= pow(GLIDE_DECAY, delta * 60.0)
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
##
## The save is handed in rather than reached for by its autoload name. Three
## scripts in this project have now been caught doing the latter, and it fails
## the same way every time: a headless harness loads the script before the
## autoloads exist and the whole compile falls over, somewhere far from here.
func refresh(skin: LocationSkin, tint: Color, state: Node) -> void:
	if _skin != skin:
		_ground = null
	_skin = skin
	_tint = tint
	_state = state
	_here = Levels.count()
	for level in Levels.catalogue():
		if not Levels.is_cleared(_state, level.number):
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
	_rocks.clear()
	_on_road.clear()
	_stations.clear()
	var total := Levels.count()
	if total == 0:
		return

	# Two rows a station, so the road has room to wander between them, plus the
	# rows the line needs to run off at either end. It comes out longer than
	# the panel, which is the point — it is dragged through.
	_rows = total * 2 + LEAD * 2

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


## Lays the road down in the order the cart would meet it, and works out which
## pipe each cell has to be from the turn it makes there.
##
## The road is generated rather than ruled. A serpentine — across, turn, back —
## is the obvious thing and it looked like a diagram: no line anybody actually
## built goes like that. This one climbs, and at every row it may step aside
## first, one or two cells, before carrying on up.
##
## What makes it read as a route rather than as a wiggle is that the sidesteps
## are given a reason: the cell it would have climbed into gets a rock. So
## every kink in the line is the line going round something, and the field
## behind it tells the story of why the road is shaped as it is.
func _walk(total: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = MAP_SEED

	var cells: Array[Vector2i] = []
	var column: int = (ROAD_LEFT + ROAD_RIGHT) / 2
	# The whole height, edge to edge: the fading ends are road too.
	# Off the ends of the grid, so the road is cut short by the panel rather
	# than ending on the last row anybody can see.
	var row: int = _rows - 1 + OVERRUN
	var floor_row: int = -OVERRUN

	while row >= floor_row:
		cells.append(Vector2i(column, row))
		if row == floor_row:
			break

		if rng.randf() < SIDESTEP_CHANCE:
			# Turn aside. Which way is forced at the edges of the road's band,
			# and free in the middle.
			var toward: int = 1
			if column >= ROAD_RIGHT:
				toward = -1
			elif column > ROAD_LEFT:
				toward = 1 if rng.randf() < 0.5 else -1
			# What it swerved to avoid.
			_rocks[Vector2i(column, row - 1)] = true
			for _i in rng.randi_range(1, 2):
				var next: int = column + toward
				if next < ROAD_LEFT or next > ROAD_RIGHT:
					break
				column = next
				cells.append(Vector2i(column, row))
		row -= 1

	# Stations spread evenly along the middle of the road — not into the ends,
	# which are the stretches that run off the panel and out of sight.
	var first: int = mini(LEAD, cells.size() - 1)
	var last: int = maxi(cells.size() - 1 - LEAD, first)
	_first_station = first
	_last_station = last
	for j in total:
		var at: int = first + int(round(float(j) * float(last - first)
			/ float(maxi(total - 1, 1))))
		var station: int = j + 1
		_spots[station] = _centre(cells[at])
		if station == _here:
			_here_index = at
		_stations[at] = station

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

		_route.append({
			"cell": cell,
			"type": _shape(_side(back), _side(forward)),
			"station": int(_stations.get(i, 0)),
		})
		_on_road[cell] = true

	_strew(rng)


## Rubble across the rest of the field, so the road is crossing somewhere
## rather than floating on graph paper. Nothing lands on the road itself, and
## nothing directly above a station, where it would crowd the crystal.
func _strew(rng: RandomNumberGenerator) -> void:
	for row in _rows:
		for column in COLS:
			var cell := Vector2i(column, row)
			if _on_road.has(cell) or _rocks.has(cell):
				continue
			if rng.randf() < RUBBLE:
				_rocks[cell] = true
	for cell: Vector2i in _on_road:
		_rocks.erase(cell)


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

## The map is dragged with a finger, and a station opens on a tap.
##
## Both live here because they are the same gesture until they are not: a
## press could still become either, and only the travel between press and
## release tells them apart. Past the slack it was a drag and no station opens,
## however precisely the finger came down on one.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			_pressed_at = event.position
			_pressing = true
			_travel = 0.0
			_glide = 0.0
			accept_event()
			return
		if not _pressing:
			return
		_pressing = false
		accept_event()
		if _travel > DRAG_SLACK:
			return  # that was a drag, and it has already moved the panel
		_glide = 0.0
		_pick_at(event.position)
		return

	if not _pressing:
		return
	var moved := 0.0
	if event is InputEventScreenDrag:
		moved = (event as InputEventScreenDrag).relative.y
	elif event is InputEventMouseMotion:
		moved = (event as InputEventMouseMotion).relative.y
	else:
		return
	_travel += absf(moved)
	_pan(-moved)
	# Kept so the map carries on a little after the finger lifts, the way a
	# list does. Without it a long line takes a dozen swipes to cross.
	_glide = -moved
	accept_event()


func _pick_at(position: Vector2) -> void:
	for number: int in _spots:
		if position.distance_to(_spots[number]) > _cell * 0.5:
			continue
		if not Levels.is_unlocked(_state, number):
			return  # out of reach: the tap does nothing rather than misfiring
		station_picked.emit(number)
		return


## Moves the panel by `amount`, and reports how much of it was actually used —
## nothing, once the line has been dragged to either end.
func _pan(amount: float) -> float:
	var scroll := _scroll()
	if scroll == null:
		return 0.0
	var before := scroll.scroll_vertical
	scroll.scroll_vertical = int(round(float(before) + amount))
	return float(scroll.scroll_vertical - before)


func _scroll() -> ScrollContainer:
	var parent := get_parent()
	return parent as ScrollContainer


# --- drawing ------------------------------------------------------------

func _draw() -> void:
	if _skin == null or _state == null or _route.is_empty():
		return
	_draw_ground()
	_draw_grid()
	_draw_rocks()
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
	if _ground == null:
		_build_ground()
	draw_texture_rect(_ground, Rect2(Vector2.ZERO, size), false)


## The background as one gradient rather than as a stack of rectangles.
##
## Painting it in bands looked right in a screenshot and wrong on a phone:
## every seam between two bands showed as a faint rule across the field, and
## thirty-two of them read as corduroy. A gradient texture has no seams to
## show.
##
## The first stop is transparent so the field arrives out of the panel instead
## of starting at a hard line under the heading.
func _build_ground() -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.06, 0.55, 1.0])
	gradient.colors = PackedColorArray([
		Color(_skin.bg_top, 0.0), _skin.bg_top, _skin.bg_mid, _skin.bg_bottom])
	var ramp := GradientTexture2D.new()
	ramp.gradient = gradient
	ramp.fill_from = Vector2(0.0, 0.0)
	ramp.fill_to = Vector2(0.0, 1.0)
	ramp.width = 4
	ramp.height = 256
	_ground = ramp


## The placement grid, exactly as the board draws it: an outline per cell, at
## the same inset and the same corner radius.
func _draw_grid() -> void:
	_grid_box.set_border_width_all(maxi(1, int(_cell * 0.015)))
	_grid_box.border_color = _skin.grid
	_grid_box.set_corner_radius_all(int(_cell * 0.16))
	for row in _rows:
		for column in COLS:
			var cell := Vector2i(column, row)
			if _rocks.has(cell):
				continue  # a rock is not a cell anything can be built on
			var centre := _centre(cell)
			var side := _cell * 0.84
			draw_style_box(_grid_box,
				Rect2(centre - Vector2(side, side) * 0.5, Vector2(side, side)))


## The rocks, in the board's own fill and edge. Drawn under the road, since the
## road was laid past them rather than over them.
func _draw_rocks() -> void:
	_rock_box.bg_color = _skin.rock_fill
	_rock_box.border_color = _skin.rock_edge
	_rock_box.set_border_width_all(maxi(1, int(_cell * 0.03)))
	_rock_box.set_corner_radius_all(int(_cell * 0.16))
	for cell: Vector2i in _rocks:
		var centre := _centre(cell)
		var side := _cell * 0.94
		draw_style_box(_rock_box,
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
	var cleared: bool = Levels.is_cleared(_state, number)
	var unlocked: bool = Levels.is_unlocked(_state, number)
	# Wider than the pipe it sits on, or the socket disappears into the track:
	# the shell is a third of a cell, so anything narrower than that reads as a
	# bulge in the road rather than as a thing in its own right.
	var radius := _cell * 0.36

	if cleared:
		# Taken. The same breathing the board gives a crystal — and, like the
		# board, no shaft of light above it: a column over every cleared
		# station turned the map into a bar chart.
		var pulse: float = 1.0 + 0.1 * sin(_time * 4.5 + float(number))
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
