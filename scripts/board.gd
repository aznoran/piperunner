## The playfield: pipe dictionary, lazy world generation, placement rules and
## rendering. Spec sections 03, 08 and 10.
##
## Board space: col grows right (0..cols-1), row grows UP. World space is
## Godot's, so world.y = -row * cell_size.
class_name Board
extends Node2D

## Outcome of place().
enum Placement { REJECTED, PLACED, REPLACED }

## Stand-in for "no cell", far outside anything the player can reach.
const NO_CELL := Vector2i(-9999, -9999)

## One occupied cell.
class PipeCell:
	var type: int
	## True once the cart has run through it. Flooded pipe is frozen — the
	## player may not build over their own history (spec section 08).
	var flooded: bool = false

	func _init(pipe_type: int) -> void:
		type = pipe_type


@onready var _terrain: Node2D = $Terrain
@onready var _live: Node2D = $Live

var _skin: LocationSkin
var balance: GameBalance
var rng := RandomNumberGenerator.new()

var cell_size: float = 100.0

var pipes: Dictionary = {}     # Vector2i -> PipeCell
var rocks: Dictionary = {}     # Vector2i -> true
var crystals: Dictionary = {}  # Vector2i -> true

## Highest row generated so far.
var rows_built: int = -1
var next_crystal_row: int = 0
## Highest row the cart has reached. Anchors the placement window.
var max_row: int = 0

## Rocks and crystals are only generated when this is on — the title screen
## wants a bare board with nothing but the runway on it.
var spawn_resources: bool = true
## No rock or crystal below this row, so the opening screen is clear and the
## first one the player meets is beyond it.
var resource_floor: int = 0

## Furthest row reached in any previous run, marked with a line across the
## board. Distance, not score — the line is a place, so it is labelled with
## the distance that reaches it.
var ghost_row: int = 0
var ghost_visible: bool = false

## Cell the cart currently occupies — nothing may be dropped on it.
var cart_cell := NO_CELL
## Cell the cart is already rolling into. Locked too, so a pipe can never be
## swapped out from under it once it is visibly inside.
var cart_incoming := NO_CELL

# Hints handed down by Main each frame; Board draws them, Main decides them.
var _ghost_cell := Vector2i.ZERO
var _ghost_type: int = PipeDefs.Type.V
var _ghost_visible: bool = false

var _frontier_cell := Vector2i.ZERO
var _frontier_need: int = PipeDefs.Side.D
var _frontier_fits: bool = false
var _frontier_visible: bool = false

# Redraw bookkeeping for the terrain layer.
var _drawn_row_min: int = 1
var _drawn_row_max: int = 0
var _terrain_dirty: bool = true

# Styleboxes are rebuilt on resize, never inside the frame loop.
var _grid_box := StyleBoxFlat.new()
var _rock_box := StyleBoxFlat.new()
var _ghost_box := StyleBoxFlat.new()

var _time: float = 0.0


func _ready() -> void:
	set_skin(Skins.current())


## Repaints with a new location skin.
func set_skin(skin: LocationSkin) -> void:
	_skin = skin
	_build_styleboxes()
	_terrain_dirty = true


func setup(game_balance: GameBalance) -> void:
	balance = game_balance


## Clears the world and lays the starting runway. `seed_value` keeps generation
## reproducible for daily challenges (spec section 11).
func start_run(seed_value: int, with_resources: bool = true,
		first_resource_row: int = 0) -> void:
	rng.seed = seed_value
	spawn_resources = with_resources
	resource_floor = first_resource_row
	pipes.clear()
	rocks.clear()
	crystals.clear()
	rows_built = -1
	next_crystal_row = maxi(balance.runway + 3, resource_floor)
	max_row = 0
	cart_cell = NO_CELL
	cart_incoming = NO_CELL
	_ghost_visible = false
	_frontier_visible = false

	var start_col: int = balance.cols / 2
	for row in balance.runway:
		pipes[Vector2i(start_col, row)] = PipeCell.new(PipeDefs.Type.V)

	ensure_rows(balance.runway + balance.generate_ahead + 4)
	_terrain_dirty = true


# --- geometry -----------------------------------------------------------

func set_cell_size(size: float) -> void:
	cell_size = size
	_build_styleboxes()
	_terrain_dirty = true


func cell_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * cell_size + cell_size * 0.5, -cell.y * cell_size)


## Continuous board position -> world, for the cart's fractional placement.
func board_to_world(col: float, row: float) -> Vector2:
	return Vector2(col * cell_size + cell_size * 0.5, -row * cell_size)


func world_to_cell(pos: Vector2) -> Vector2i:
	# Columns are bounded by multiples of cell_size, rows are centred on them.
	return Vector2i(int(floor(pos.x / cell_size)), int(round(-pos.y / cell_size)))


# --- generation ---------------------------------------------------------

## Builds rows lazily up to `up_to`. Spec section 10.
func ensure_rows(up_to: int) -> void:
	while rows_built < up_to:
		rows_built += 1
		var row := rows_built
		if row < balance.runway + 2:
			continue

		if not spawn_resources or row < resource_floor:
			_terrain_dirty = true
			continue

		if row > balance.rock_start_row:
			var density: float = minf(
				balance.rock_density_base
					+ (row - balance.rock_start_row) * balance.rock_density_gain,
				balance.rock_density_cap)
			for col in balance.cols:
				var cell := Vector2i(col, row)
				if pipes.has(cell):
					continue
				if rng.randf() < density:
					rocks[cell] = true

		if row >= next_crystal_row:
			var free: Array[int] = []
			for col in balance.cols:
				var cell := Vector2i(col, row)
				if not rocks.has(cell) and not pipes.has(cell):
					free.append(col)
			if not free.is_empty():
				crystals[Vector2i(free[rng.randi_range(0, free.size() - 1)], row)] = true
				next_crystal_row = row + rng.randi_range(
					balance.crystal_gap_min, balance.crystal_gap_max)

		_terrain_dirty = true


# --- placement ----------------------------------------------------------

## Spec section 08. Everything the player is forbidden to build on.
func can_place(cell: Vector2i) -> bool:
	if cell.x < 0 or cell.x >= balance.cols:
		return false
	if rocks.has(cell):
		return false
	var pipe: PipeCell = pipes.get(cell)
	if pipe != null and pipe.flooded:
		return false
	if cell == cart_cell or cell == cart_incoming:
		return false
	# The litter zone. Do not widen: dumping junk behind the cart is the skill.
	if cell.y > max_row + balance.place_above or cell.y < max_row - balance.place_below:
		return false
	return true


func place(cell: Vector2i, type: int) -> Placement:
	if not can_place(cell):
		return Placement.REJECTED
	var replaced := pipes.has(cell)
	pipes[cell] = PipeCell.new(type)
	# The crystal stays put under the pipe — routing the cart through one is
	# exactly how the player refuels (spec section 02).
	ensure_rows(cell.y + balance.generate_ahead)
	_terrain_dirty = true
	return Placement.REPLACED if replaced else Placement.PLACED


func get_pipe(cell: Vector2i) -> PipeCell:
	return pipes.get(cell)


## Marks a pipe as run through, freezing it against further edits.
func flood(cell: Vector2i) -> void:
	var pipe: PipeCell = pipes.get(cell)
	if pipe != null and not pipe.flooded:
		pipe.flooded = true
		_terrain_dirty = true


func take_crystal(cell: Vector2i) -> bool:
	if not crystals.has(cell):
		return false
	crystals.erase(cell)
	return true


func note_row_reached(row: int) -> void:
	if row > max_row:
		max_row = row
		_terrain_dirty = true


func set_cart_cell(cell: Vector2i) -> void:
	cart_cell = cell


func set_cart_incoming(cell: Vector2i) -> void:
	if cart_incoming == cell:
		return
	cart_incoming = cell
	_terrain_dirty = true  # the grid hint for that cell has to disappear


# --- lookahead ----------------------------------------------------------

## Walks the built pipes from the cart to find where the track runs out.
## Returns {cell, need, steps, blocked} or an empty dictionary if the path
## loops (an X-crossroads ring can do that).
func frontier(from_cell: Vector2i, from_entry: int) -> Dictionary:
	var cell := from_cell
	var entry := from_entry
	var steps := 0
	while steps < 80:
		var pipe: PipeCell = pipes.get(cell)
		if pipe == null:
			return {"cell": cell, "need": entry, "steps": steps, "blocked": false}
		var exit: int = PipeDefs.exit_side(pipe.type, entry)
		if exit == PipeDefs.NO_EXIT:
			return {"cell": cell, "need": entry, "steps": steps, "blocked": true}
		cell += PipeDefs.DIR[exit]
		entry = PipeDefs.OPPOSITE[exit]
		steps += 1
	return {}


# --- draw hints ---------------------------------------------------------

func show_ghost(cell: Vector2i, type: int) -> void:
	_ghost_cell = cell
	_ghost_type = type
	_ghost_visible = true


func hide_ghost() -> void:
	_ghost_visible = false


func show_frontier(cell: Vector2i, need: int, fits: bool) -> void:
	_frontier_cell = cell
	_frontier_need = need
	_frontier_fits = fits
	_frontier_visible = true


func hide_frontier() -> void:
	_frontier_visible = false


# --- rendering ----------------------------------------------------------

func _process(delta: float) -> void:
	_time += delta
	# The terrain pass culls to the visible rows, so it has to redraw when the
	# window scrolls — but only about twice a second, not every frame.
	var rows := _visible_rows()
	if _terrain_dirty or rows.x != _drawn_row_min or rows.y != _drawn_row_max:
		_drawn_row_min = rows.x
		_drawn_row_max = rows.y
		_terrain_dirty = false
		_terrain.queue_redraw()
	_live.queue_redraw()


## Inclusive row range covering the screen, with a cell of margin.
func _visible_rows() -> Vector2i:
	var camera := get_viewport().get_camera_2d()
	var half_height: float = get_viewport_rect().size.y * 0.5
	var centre: float = camera.global_position.y if camera != null else 0.0
	var top := centre - half_height
	var bottom := centre + half_height
	return Vector2i(
		int(floor(-bottom / cell_size)) - 2,
		int(ceil(-top / cell_size)) + 2)


func _build_styleboxes() -> void:
	var radius := int(cell_size * 0.09)

	_grid_box.bg_color = Color.TRANSPARENT
	_grid_box.set_border_width_all(maxi(1, int(cell_size * 0.015)))
	_grid_box.border_color = _skin.grid
	_grid_box.set_corner_radius_all(radius)

	_rock_box.bg_color = _skin.rock_fill
	_rock_box.set_border_width_all(maxi(1, int(cell_size * 0.03)))
	_rock_box.border_color = _skin.rock_edge
	_rock_box.set_corner_radius_all(radius)

	_ghost_box.bg_color = Color.TRANSPARENT
	_ghost_box.set_border_width_all(maxi(2, int(cell_size * 0.05)))
	_ghost_box.set_corner_radius_all(int(cell_size * 0.12))


func _cell_rect(cell: Vector2i, scale: float) -> Rect2:
	var centre := cell_to_world(cell)
	var size := cell_size * scale
	return Rect2(centre - Vector2(size, size) * 0.5, Vector2(size, size))


## Grid hints, rocks and pipes. Redrawn only when the board or the visible
## window changes.
func draw_terrain(ci: CanvasItem) -> void:
	if balance == null:
		return
	var row_min := _drawn_row_min
	var row_max := _drawn_row_max

	# Empty buildable cells, which also shows the player the placement window.
	for row in range(row_min, row_max + 1):
		for col in balance.cols:
			var cell := Vector2i(col, row)
			if pipes.has(cell) or rocks.has(cell):
				continue
			if not can_place(cell):
				continue
			ci.draw_style_box(_grid_box, _cell_rect(cell, 0.84))

	for row in range(row_min, row_max + 1):
		for col in balance.cols:
			var cell := Vector2i(col, row)
			if rocks.has(cell):
				ci.draw_style_box(_rock_box, _cell_rect(cell, 0.72))

	for cell: Vector2i in pipes:
		if cell.y < row_min or cell.y > row_max:
			continue
		var pipe: PipeCell = pipes[cell]
		_draw_pipe(ci, cell_to_world(cell), pipe.type, pipe.flooded, 1.0)

	if ghost_visible:
		_draw_record_ghost(ci)


## Marks how far the player has ever got. Spec section 11, P0: the near-miss
## effect — dying one cell short of your record is unbearable.
func show_record(distance: int) -> void:
	ghost_row = distance
	ghost_visible = distance > 0
	_terrain_dirty = true


func _draw_record_ghost(ci: CanvasItem) -> void:
	if ghost_row < _drawn_row_min - 1 or ghost_row > _drawn_row_max + 1:
		return

	# A line across the whole board, so it cannot be missed on the way up.
	var y := cell_to_world(Vector2i(0, ghost_row)).y
	var right := balance.cols * cell_size
	var mark := _skin.record_ghost
	mark.a = minf(mark.a * 2.4, 1.0)
	ci.draw_dashed_line(Vector2(0.0, y), Vector2(right, y), mark,
		cell_size * 0.05, cell_size * 0.16)

	var font := ThemeDB.fallback_font
	if font == null:
		return
	var label := "BEST %d" % ghost_row
	var size := maxi(12, int(cell_size * 0.24))
	var text_width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT,
		-1.0, size).x
	ci.draw_string(font, Vector2(right - text_width - cell_size * 0.15,
		y - cell_size * 0.16), label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, mark)


## Crystals, the placement ghost and the frontier ring. Every frame.
func draw_live(ci: CanvasItem) -> void:
	if balance == null:
		return
	for cell: Vector2i in crystals:
		if cell.y < _drawn_row_min or cell.y > _drawn_row_max:
			continue
		_draw_crystal(ci, cell)

	if _ghost_visible:
		_draw_ghost(ci)
	if _frontier_visible:
		_draw_frontier(ci)


## Shell then core, matching the prototype's two-pass stroke. Circles at the
## joint stand in for the canvas round line cap.
func _draw_pipe(ci: CanvasItem, centre: Vector2, type: int, flooded: bool, alpha: float) -> void:
	var sides: Array = PipeDefs.SIDES[type]
	var shell: Color = _skin.pipe_shell_used if flooded else _skin.pipe_shell
	var core: Color = _skin.pipe_core_used if flooded else _skin.pipe_core
	shell.a *= alpha
	core.a *= alpha

	var shell_width := cell_size * 0.34
	var core_width := cell_size * 0.09
	var reach := cell_size * 0.5

	for side: int in sides:
		var step: Vector2i = PipeDefs.DIR[side]
		var offset := Vector2(step.x, -step.y) * reach
		ci.draw_line(centre, centre + offset, shell, shell_width)
	ci.draw_circle(centre, shell_width * 0.5, shell)

	for side: int in sides:
		var step: Vector2i = PipeDefs.DIR[side]
		var offset := Vector2(step.x, -step.y) * reach
		ci.draw_line(centre, centre + offset, core, core_width)
	ci.draw_circle(centre, core_width * 0.5, core)


func _draw_crystal(ci: CanvasItem, cell: Vector2i) -> void:
	var centre := cell_to_world(cell)
	var pulse := 1.0 + 0.12 * sin(_time * 4.5 + cell.x)

	# Shaft of light rising out of the crystal, so it reads from a screen away.
	var beam := _skin.pickup
	beam.a = 0.07
	var beam_height := cell_size * 6.0
	ci.draw_rect(Rect2(centre.x - cell_size * 0.07, centre.y - beam_height,
		cell_size * 0.14, beam_height), beam)

	var half := cell_size * 0.17 * pulse
	var core_half := cell_size * 0.07 * pulse
	var glow := _skin.pickup
	glow.a = 0.28

	# Diamond = a square turned 45 degrees.
	ci.draw_set_transform(centre, PI * 0.25, Vector2.ONE)
	ci.draw_rect(Rect2(-half * 1.5, -half * 1.5, half * 3.0, half * 3.0), glow)
	ci.draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0), _skin.pickup)
	ci.draw_rect(Rect2(-core_half, -core_half, core_half * 2.0, core_half * 2.0),
		_skin.pickup_core)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_ghost(ci: CanvasItem) -> void:
	var ok := can_place(_ghost_cell)
	var tint: Color = _skin.ghost_ok if ok else _skin.ghost_bad
	var rect := _cell_rect(_ghost_cell, 0.92)

	var fill := tint
	fill.a = 0.30
	ci.draw_rect(rect, fill)
	_ghost_box.border_color = tint
	ci.draw_style_box(_ghost_box, rect)

	if not ok:
		return
	var centre := cell_to_world(_ghost_cell)
	var silhouette: Color = _skin.ghost_pipe
	silhouette.a = 0.85
	for side: int in PipeDefs.SIDES[_ghost_type]:
		var step: Vector2i = PipeDefs.DIR[side]
		var offset := Vector2(step.x, -step.y) * cell_size * 0.42
		ci.draw_line(centre, centre + offset, silhouette, cell_size * 0.12)


## The ring marking where the cart needs pipe next, plus a dot on the side it
## will arrive from. Teal when the piece in hand fits there.
func _draw_frontier(ci: CanvasItem) -> void:
	var centre := cell_to_world(_frontier_cell)
	var tint: Color = _skin.ghost_ok if _frontier_fits else Color.WHITE
	tint.a = 0.55 + 0.35 * sin(_time * 7.0)

	_ghost_box.border_color = tint
	_ghost_box.bg_color = Color.TRANSPARENT
	ci.draw_style_box(_ghost_box, _cell_rect(_frontier_cell, 0.88))

	var step: Vector2i = PipeDefs.DIR[_frontier_need]
	var dot := centre + Vector2(step.x, -step.y) * cell_size * 0.42
	tint.a = 1.0
	ci.draw_circle(dot, cell_size * 0.045, tint)
