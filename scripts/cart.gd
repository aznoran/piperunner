## The cart: where it is, which way it entered, and how it walks the pipes.
## Spec section 05.
class_name Cart
extends Node2D

## Fired after a successful move into `cell`, before Main scores it.
signal stepped(cell: Vector2i)
## Fired once per run. `reason` is shown as the game-over title, so the three
## causes stay distinct (spec section 14).
signal derailed(reason: String)

const REASON_DERAILED := "Derailed"
const REASON_OFF_EDGE := "Off the edge"

var _skin: LocationSkin
var board: Board

var col: int = 0
var row: int = 0
## Side of the current cell the cart came in through.
var entry: int = PipeDefs.Side.D
## Progress towards the next cell, 0..1.
var t: float = 0.0

var alive: bool = false
## Drives the glow colour; Main owns the actual fuel number.
var low_fuel: bool = false

var _stylebox_body := StyleBoxFlat.new()
var _stylebox_window := StyleBoxFlat.new()
var _cell_size: float = 100.0


func _ready() -> void:
	set_skin(Skins.current())


## Repaints with a new location skin.
func set_skin(skin: LocationSkin) -> void:
	_skin = skin
	set_cell_size(_cell_size)


func set_cell_size(size: float) -> void:
	_cell_size = size
	var unit := size * 0.26
	_stylebox_body.bg_color = _skin.cart_body
	_stylebox_body.set_corner_radius_all(maxi(2, int(unit * 0.2)))
	_stylebox_window.bg_color = _skin.cart_window
	_stylebox_window.set_corner_radius_all(maxi(1, int(unit * 0.12)))
	queue_redraw()


func place_at(start_col: int, start_row: int, start_entry: int) -> void:
	col = start_col
	row = start_row
	entry = start_entry
	t = 0.0
	alive = true
	low_fuel = false
	_sync_transform()


func cell() -> Vector2i:
	return Vector2i(col, row)


## The cell the cart is rolling into, once it is at least `progress` of the way
## there. Board.NO_CELL while it is still mostly in the cell behind.
func incoming_cell(progress: float) -> Vector2i:
	if not alive or t < progress or board == null:
		return Board.NO_CELL
	var pipe := board.get_pipe(cell())
	if pipe == null:
		return Board.NO_CELL
	var exit: int = PipeDefs.exit_side(pipe.type, entry)
	if exit == PipeDefs.NO_EXIT:
		return Board.NO_CELL
	return cell() + PipeDefs.DIR[exit]


## Advances by `speed` cells per second, stepping cell to cell as `t` rolls over.
func advance(delta: float, speed: float) -> void:
	if not alive:
		return
	t += speed * delta
	while t >= 1.0:
		t -= 1.0
		if not _step():
			return


## One cell of travel. Returns false when the run ended.
func _step() -> bool:
	var pipe := board.get_pipe(cell())
	if pipe == null:
		return _die(REASON_DERAILED)

	var exit: int = PipeDefs.exit_side(pipe.type, entry)
	if exit == PipeDefs.NO_EXIT:
		return _die(REASON_DERAILED)

	var next: Vector2i = cell() + PipeDefs.DIR[exit]
	if next.x < 0 or next.x >= board.balance.cols:
		return _die(REASON_OFF_EDGE)

	var next_entry: int = PipeDefs.OPPOSITE[exit]
	var next_pipe := board.get_pipe(next)
	if next_pipe == null or not PipeDefs.SIDES[next_pipe.type].has(next_entry):
		# Roll into the gap first — the player should see where it came off.
		col = next.x
		row = next.y
		entry = next_entry
		return _die(REASON_DERAILED)

	col = next.x
	row = next.y
	entry = next_entry
	board.flood(next)
	stepped.emit(next)
	return alive


func _die(reason: String) -> bool:
	if not alive:
		return false
	alive = false
	t = 0.0
	derailed.emit(reason)
	return false


func _process(_delta: float) -> void:
	_sync_transform()


## Spec section 05, the critical note: the on-screen position must be a
## fractional interpolation between cells. Snapping to whole cells made the
## cart teleport and the camera stutter.
func _sync_transform() -> void:
	if board == null:
		return
	var target_col := float(col)
	var target_row := float(row)
	var angle := -PI * 0.5  # facing up, the default heading

	var pipe := board.get_pipe(cell())
	if pipe != null:
		var exit: int = PipeDefs.exit_side(pipe.type, entry)
		if exit != PipeDefs.NO_EXIT:
			var step: Vector2i = PipeDefs.DIR[exit]
			target_col += step.x
			target_row += step.y
			angle = Vector2(step.x, -step.y).angle()

	var blend := clampf(t, 0.0, 1.0)
	position = board.board_to_world(
		lerpf(col, target_col, blend),
		lerpf(row, target_row, blend))
	rotation = angle


## Fractional board row, so the camera can follow continuous motion.
func visual_row() -> float:
	if board == null:
		return float(row)
	return -position.y / board.cell_size


func _draw() -> void:
	var unit := _cell_size * 0.26
	# Stand-in for the prototype's shadowBlur: a few fading rings.
	var glow: Color = _skin.danger if low_fuel else _skin.accent
	for ring in range(4, 0, -1):
		glow.a = 0.05 * (5 - ring)
		draw_circle(Vector2.ZERO, unit * (0.7 + 0.3 * ring), glow)

	draw_style_box(_stylebox_body,
		Rect2(-unit, -unit * 0.76, unit * 2.0, unit * 1.52))
	draw_style_box(_stylebox_window,
		Rect2(-unit * 0.45, -unit * 0.36, unit * 0.9, unit * 0.72))
