## Plays the game by itself, for recording.
##
## It is deliberately not a cheat: it goes through the same two actions a
## finger has — place the piece in hand at a cell, or tap HOLD — reads only
## what is on screen, and cannot see past the preview. Nothing it does is
## privileged, so a run it plays counts exactly like a played one.
##
## Nor is it optimal. It thinks for a beat before acting, its timing wanders,
## and it takes the odd wrong turn on purpose. A perfect machine reads as a
## machine on video; a good player with a pulse does not.
class_name Autoplayer
extends Node

## Seconds between actions. The spread is what stops it looking mechanical.
const THINK_MIN := 0.16
const THINK_MAX := 0.42
## Every so often it pauses like someone reconsidering.
const HESITATE_CHANCE := 0.08
const HESITATE_EXTRA := 0.55
## And every so often it simply plays the wrong cell.
const MISTAKE_CHANCE := 0.03

var active: bool = false

var _main: Node
var _board: Board
var _cart: Cart
var _queue: PipeQueue
var _wait: float = 0.0
var _rng := RandomNumberGenerator.new()


func setup(main: Node, board: Board, cart: Cart, queue: PipeQueue) -> void:
	_main = main
	_board = board
	_cart = cart
	_queue = queue
	_rng.randomize()


func start() -> void:
	active = true
	_wait = 0.6


func stop() -> void:
	active = false


func _process(delta: float) -> void:
	if not active or _main == null:
		return
	if _main.state != 1:  # only while a run is live
		return
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = _think_time()
	_act()


## How long before the next action. A good player speeds up as the cart does,
## and stops dithering when the track runs out — so this tracks both, and only
## hesitates when there is room to.
func _think_time() -> float:
	var urgency: float = clampf(_main.speed / maxf(_main.balance.speed_cap, 0.1), 0.0, 1.0)
	var base: float = lerpf(THINK_MAX, THINK_MIN, urgency)
	var jitter: float = base * _rng.randf_range(0.7, 1.3)

	var ahead := _board.frontier(_cart.cell(), _cart.entry)
	var buffer: int = int(ahead.get("steps", 9))
	if buffer <= 1:
		return THINK_MIN * 0.6  # no time to think
	if buffer >= 4 and _rng.randf() < HESITATE_CHANCE:
		return jitter + HESITATE_EXTRA
	return jitter


func _act() -> void:
	var ahead := _board.frontier(_cart.cell(), _cart.entry)
	if ahead.is_empty():
		return
	var joint: Vector2i = ahead["cell"]
	var need: int = ahead["need"]
	var blocked: bool = ahead["blocked"]
	var piece: int = _queue.current()

	var buffer: int = int(ahead["steps"])
	if not blocked and _serves(piece, need) and _board.can_place(joint):
		if _worth_extending(joint, piece, need, buffer):
			_place(joint)
			return

	# The piece is no use here. Swap first if the pocket holds what this joint
	# wants — that is what the pocket is for.
	if _queue.held != PipeQueue.NONE and _serves(_queue.held, need) and not blocked:
		_main._on_hold_tapped()
		return

	# Pocket an awkward piece, but never a crossroads: it fits every joint, so
	# holding one is throwing away the piece that always works.
	if _queue.held == PipeQueue.NONE and piece != PipeDefs.Type.X:
		_main._on_hold_tapped()
		return

	_dump(joint)


## Whether laying this piece here is a move worth making.
##
## Not fitting the joint is only half the question. A piece that fits can still
## point the cart downward or into the wall, and the score is distance climbed
## — a run that wanders sideways along row three is a run going nowhere. The
## exception is a cart about to derail: then any track beats no track.
func _worth_extending(cell: Vector2i, piece: int, entry: int, buffer: int) -> bool:
	var exit: int = PipeDefs.exit_side(piece, entry)
	if exit == PipeDefs.NO_EXIT:
		return false

	var next: Vector2i = cell + PipeDefs.DIR[exit]
	if next.x < 0 or next.x >= _main.balance.cols:
		return false
	if _board.rocks.has(next):
		return false

	# Out of road: take whatever keeps the cart alive.
	if buffer <= 1:
		return true

	# A crystal is always worth the detour.
	if _board.crystals.has(next):
		return true

	if exit == PipeDefs.Side.D:
		return false  # gives back ground that has to be climbed again

	if exit == PipeDefs.Side.L or exit == PipeDefs.Side.R:
		# Sideways is a manoeuvre, not a habit: only when there is room to turn
		# back up on the far side.
		var beyond: Vector2i = next + PipeDefs.DIR[exit]
		if beyond.x < 0 or beyond.x >= _main.balance.cols:
			return false
		return not _board.rocks.has(Vector2i(next.x, next.y + 1))

	return true


func _serves(piece: int, need: int) -> bool:
	return PipeDefs.SIDES[piece].has(need)


func _place(cell: Vector2i) -> void:
	# The occasional misplay, so the run has texture.
	if _rng.randf() < MISTAKE_CHANCE:
		var sideways: int = [PipeDefs.Side.L, PipeDefs.Side.R][_rng.randi() % 2]
		var slip: Vector2i = cell + PipeDefs.DIR[sideways]
		if _board.can_place(slip):
			_main._try_place(slip)
			return
	_main._try_place(cell)


## Junk goes behind the cart, in the litter zone — the play the game is built
## around. Furthest-behind first, so the mess never grows into the route.
func _dump(joint: Vector2i) -> void:
	var best := Board.NO_CELL
	var best_score := -1000.0
	var lowest: int = _board.max_row - _main.balance.place_below

	for row in range(lowest, _cart.row):
		for col in _main.balance.cols:
			var spot := Vector2i(col, row)
			if spot == joint or _board.get_pipe(spot) != null:
				continue
			if not _board.can_place(spot):
				continue
			# Prefer far below and away from the column the cart is climbing.
			var score := float(_cart.row - row) + absf(col - _cart.col) * 0.6
			if score > best_score:
				best_score = score
				best = spot

	if best != Board.NO_CELL:
		_main._try_place(best)
