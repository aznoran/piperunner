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

## How well it plays. SHOWCASE is a good player with a pulse — it hesitates,
## it misplays, it dies. EXPERT is the one that has to reach a hundred cells:
## same two actions, same information, but it looks a move ahead and does not
## make casual mistakes.
enum Skill { SHOWCASE, EXPERT }

var skill: Skill = Skill.SHOWCASE

## How good it is, on a dial rather than a switch: 0 is a beginner who mostly
## reacts, 1 is the expert that reads the queue to the end. The two presets sit
## at either end and the debug panel can put it anywhere between, which is the
## only way to see how a given standard of play meets a given set of formulas.
var proficiency: float = SHOWCASE_LEVEL

const SHOWCASE_LEVEL := 0.35
const EXPERT_LEVEL := 1.0
## Below this it plays move to move; above it, it plans.
const PLANS_FROM := 0.6

## Seconds between actions. The spread is what stops it looking mechanical.
const THINK_MIN := 0.16
const THINK_MAX := 0.42
## Every so often it pauses like someone reconsidering.
const HESITATE_CHANCE := 0.08
const HESITATE_EXTRA := 0.55
## And every so often it simply plays the wrong cell.
const MISTAKE_CHANCE := 0.03
## How far ahead of the cart it will build. Beyond this the track leaves the
## screen, which is no use to a player watching and no use on video either.
const MAX_BUFFER := 5
## The expert keeps a deeper reserve than the showcase bot, but the screen is
## the real limit: track laid where the player cannot see it is not play, it
## just looks like the run is happening somewhere else.
const MAX_BUFFER_EXPERT := 10
## Below this fraction of a tank it starts routing towards crystals rather
## than straight up.
const THIRSTY := 0.45

var active: bool = false

var _main: Node
var _board: Board
var _cart: Cart
var _queue: PipeQueue
var _wait: float = 0.0
## The pocket is a swap, so trading twice in a row just puts the piece back —
## two moves spent, no track laid. Measured at 99 swaps against 51 placements
## in a forty-cell run.
var _just_swapped: bool = false
var _rng := RandomNumberGenerator.new()

## Why the last run went the way it did. Debug only; costs nothing to keep.
var tally := {}


func _bump(what: String) -> void:
	tally[what] = int(tally.get(what, 0)) + 1


func setup(main: Node, board: Board, cart: Cart, queue: PipeQueue) -> void:
	_main = main
	_board = board
	_cart = cart
	_queue = queue


## `dice` fixes the bot's own randomness — benchmarks pass a seed so two runs
## of different code face the same hesitations. Left at -1 in play.
func start(level: Skill = Skill.SHOWCASE, dice: int = -1,
		level_override: float = -1.0) -> void:
	skill = level
	proficiency = level_override if level_override >= 0.0 \
		else (EXPERT_LEVEL if level == Skill.EXPERT else SHOWCASE_LEVEL)
	tally = {}
	_just_swapped = false
	if dice >= 0:
		_rng.seed = dice
	else:
		_rng.randomize()
	active = true
	_wait = 0.6


func stop() -> void:
	active = false


func _process(delta: float) -> void:
	if not active or _main == null:
		return
	if _main.state != 1:  # only while a run is live
		return
	# One action per frame is not enough when frames are long — on a stuttering
	# phone the cart keeps rolling while the hand waits for the next frame. Work
	# through the time that actually passed, capped so a hitch cannot turn into
	# a burst of play no finger could match.
	_wait -= delta
	var actions := 0
	while _wait <= 0.0 and actions < 4:
		_wait += _think_time()
		_act()
		actions += 1


## How long before the next action. A good player speeds up as the cart does,
## and stops dithering when the track runs out — so this tracks both, and only
## hesitates when there is room to.
func _think_time() -> float:
	var urgency: float = clampf(_main.speed / maxf(_main.balance.speed_cap, 0.1), 0.0, 1.0)
	var base: float = lerpf(THINK_MAX, THINK_MIN, urgency)
	base *= lerpf(1.0, 0.55, _grade())  # better players are quicker on the tap
	var jitter: float = base * _rng.randf_range(0.7, 1.3)

	var ahead := _board.frontier(_cart.cell(), _cart.entry)
	var buffer: int = int(ahead.get("steps", 9))
	if bool(ahead.get("blocked", false)):
		return THINK_MIN * 0.35  # a wrong-facing pipe ahead: fix it now
	if buffer <= 1:
		return THINK_MIN * 0.5  # no time to think
	if buffer >= 4 and _rng.randf() < HESITATE_CHANCE * (1.0 - _grade()):
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
	var rows := _board.visible_rows()

	# Building past the top of the screen wastes pieces on track nobody can see
	# — and on video it looks like the run is happening somewhere else.
	var cap: int = int(roundf(lerpf(MAX_BUFFER, MAX_BUFFER_EXPERT, _grade())))
	var too_far: bool = buffer >= cap or joint.y > rows.y - 1

	# A pipe at the joint that refuses the cart is not a dead end — it is a pipe
	# nobody has replaced yet. The game lets you build over anything the cart
	# has not run through, and a cart three cells away from a wrong-facing pipe
	# is exactly when a strong player does it. Distance caps do not apply: this
	# is the run ending in three seconds.
	if blocked:
		_bump("blocked")
		if _serves(piece, need) and _board.can_place(joint):
			# Building over the wrong-facing pipe. No slip here, however
			# casually the bot is playing — this move is the run.
			_bump("repair")
			_main._try_place(joint)
		elif _reroute(piece):
			_bump("reroute")
		elif _queue.held != PipeQueue.NONE and _serves(_queue.held, need):
			_main._on_hold_tapped()
		elif _queue.held == PipeQueue.NONE and piece != PipeDefs.Type.X:
			_main._on_hold_tapped()
		else:
			# Neither hand nor pocket fits. Standing still is death; spending
			# the piece behind the cart brings the next one up.
			_bump("cycle")
			_dump(joint)
		return

	if _serves(piece, need) and (too_far or not _board.can_place(joint)):
		_bump("wait")
		return  # hold the good piece until the joint opens up

	if _plans() and not blocked and not too_far:
		var line: Array = _queue.upcoming.duplicate()
		var read: Dictionary = _plan(joint, need, line, _queue.held,
			float(buffer), PLAN_DEPTH, _just_swapped)
		match read["do"]:
			"place":
				if _board.can_place(joint):
					_bump("plan_place")
					_just_swapped = false
					_place(joint)
					return
			"hold":
				_bump("plan_hold")
				_just_swapped = true
				_main._on_hold_tapped()
				return
			"dump":
				_just_swapped = false
				if _stockpile(joint, piece):
					_bump("stockpile")
					return
				_bump("plan_dump")
				_dump(joint)
				return
			_:
				_bump("plan_wait")
				return

	if not too_far and _serves(piece, need) \
			and _board.can_place(joint):
		if _worth_extending(joint, piece, need, buffer):
			_bump("extend")
			_place(joint)
			return
		_bump("refused")
	elif too_far:
		_bump("too_far")
	elif not _serves(piece, need):
		_bump("wrong_shape")
	else:
		_bump("cant_place")

	# No use at the joint. Before pocketing or dumping it, see whether it is
	# track the route will want anyway.
	if _stockpile(joint, piece):
		_bump("stockpile")
		return

	# Swap first if the pocket holds what this joint wants — that is what the
	# pocket is for.
	if _queue.held != PipeQueue.NONE and _serves(_queue.held, need) and not blocked:
		_main._on_hold_tapped()
		return

	# Pocket an awkward piece, but never a crossroads: it fits every joint, so
	# holding one is throwing away the piece that always works.
	if _queue.held == PipeQueue.NONE and piece != PipeDefs.Type.X:
		_main._on_hold_tapped()
		return

	_bump("dump")
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
	# Pointing the cart at a pipe that will not take it is how these runs end.
	# Only when the track has run out is it worth the gamble — by then there is
	# time to build over it, and no track at all is certain death.
	if not _clear(next, PipeDefs.OPPOSITE[exit]) and buffer > 2:
		return false

	# Out of road: take whatever keeps the cart alive. The expert calls it a
	# cell earlier — every refusal costs a turn, and a turn spent not building
	# is how the buffer reaches zero. Derailing, not fuel, is what ends these
	# runs.
	if buffer <= (2 if _plans() else 1):
		return true

	# A crystal is always worth the detour.
	if _board.crystals.has(next):
		return true

	if exit == PipeDefs.Side.D:
		# Ground given back has to be climbed again, so this is a last resort —
		# but with the track running out it still beats no track at all.
		# Measured: allowing it on a full tank instead drops the run from 69
		# cells to 12, because the route walks itself down out of the build
		# zone and every move after that is refused.
		return _plans() and buffer <= 3

	if exit == PipeDefs.Side.L or exit == PipeDefs.Side.R:
		var beyond: Vector2i = next + PipeDefs.DIR[exit]
		if beyond.x < 0 or beyond.x >= _main.balance.cols:
			return false
		if _board.rocks.has(Vector2i(next.x, next.y + 1)):
			return false

		var crystal := _nearest_crystal()
		if crystal != Board.NO_CELL:
			# Towards fuel is always worth it; away from it only with a
			# comfortable tank.
			if absi(next.x - crystal.x) < absi(cell.x - crystal.x):
				return true
			return _main.fuel / _main.balance.fuel_max > 0.5

		# No crystal in sight: sideways keeps the track alive and costs no
		# height, so the expert takes it rather than burning the turn.
		return _plans() \
			or _main.fuel / _main.balance.fuel_max < _thirst()

	return true


# --- planning -----------------------------------------------------------

## How far down the preview the expert reads. The tree is three-way and the
## preview is short, so the whole thing costs a few hundred cheap steps.
const PLAN_DEPTH := 7
## What a run that ends is worth: nothing, whatever height it reached.
const DEATH := -400.0

## Plays the visible queue out to the end and returns the first move of the
## best line, as {"do": "place"/"hold"/"dump"}.
##
## There is no rotating a piece in this game — it fits the joint or it does
## not — so the only real decisions are spend it here, pocket it, or throw it
## behind the cart. That is a small enough tree to walk properly, and walking
## it is the difference between a bot that reacts and one that reads the
## queue the way a strong player does.
func _plan(joint: Vector2i, entry: int, line: Array, held: int,
		slack: float, depth: int, swapped: bool) -> Dictionary:
	if depth <= 0 or line.is_empty():
		return {"score": float(joint.y) + slack * 0.5, "do": "wait"}
	if slack < 0.0:
		return {"score": DEATH + joint.y, "do": "wait"}

	var piece: int = line[0]
	var best := {"score": DEATH * 2.0, "do": "dump"}

	# Spend it at the joint.
	if _serves(piece, entry):
		var exit: int = PipeDefs.exit_side(piece, entry)
		if exit != PipeDefs.NO_EXIT:
			var next: Vector2i = joint + PipeDefs.DIR[exit]
			if next.x >= 0 and next.x < _main.balance.cols \
					and not _board.rocks.has(next) \
					and _clear(next, PipeDefs.OPPOSITE[exit]):
				var rest: Array = line.slice(1)
				var deeper := _plan(next, PipeDefs.OPPOSITE[exit], rest, held,
					slack + 1.0 - _step_cost(), depth - 1, false)
				var gain: float = float(next.y - joint.y) * 4.0
				if _board.crystals.has(next):
					gain += 6.0  # fuel is distance
				var here: float = deeper["score"] + gain
				if here > best["score"]:
					best = {"score": here, "do": "place"}

	# Pocket it, or trade it for what is pocketed. Trading does not advance the
	# queue, so it is allowed once per line — otherwise the search would sit
	# there swapping forever.
	if not swapped:
		var traded: Array = line.duplicate()
		var pocket := held
		if held == PipeQueue.NONE:
			pocket = piece
			traded.remove_at(0)
		else:
			traded[0] = held
			pocket = piece
		var swap_line := _plan(joint, entry, traded, pocket,
			slack - _step_cost(), depth - 1, held != PipeQueue.NONE)
		if swap_line["score"] > best["score"]:
			best = {"score": swap_line["score"], "do": "hold"}

	# Spend it behind the cart to bring the next one up.
	var skipped: Array = line.slice(1)
	var dumped := _plan(joint, entry, skipped, held,
		slack - _step_cost(), depth - 1, false)
	if dumped["score"] > best["score"]:
		best = {"score": dumped["score"], "do": "dump"}

	return best


## Ground a plan may route through: empty, or a pipe that already takes the
## cart from that side. Deliberately stricter than _accepts, which counts on
## being able to build over a wrong-facing pipe — true at the joint in front of
## the cart, wishful thinking four moves down a line.
func _clear(cell: Vector2i, side: int) -> bool:
	var existing := _board.get_pipe(cell)
	return existing == null or PipeDefs.SIDES[existing.type].has(side)


## How much of a cell the cart covers while the hand makes one move. This is
## what makes throwing pieces away expensive: the track does not grow, but the
## cart still arrives.
func _step_cost() -> float:
	var think: float = lerpf(THINK_MAX, THINK_MIN,
		clampf(_main.speed / maxf(_main.balance.speed_cap, 0.1), 0.0, 1.0)) * 0.55
	return _main.speed * think


## The pipes the cart is going to run through, in the order it meets them,
## each with the side it will arrive from.
func _route() -> Array:
	var cell: Vector2i = _cart.cell()
	var entry: int = _cart.entry
	var path := []
	for _i in 40:
		var pipe := _board.get_pipe(cell)
		if pipe == null:
			break
		var exit: int = PipeDefs.exit_side(pipe.type, entry)
		if exit == PipeDefs.NO_EXIT:
			break
		path.append({"cell": cell, "entry": entry})
		cell += PipeDefs.DIR[exit]
		entry = PipeDefs.OPPOSITE[exit]
	return path


## Sends the cart a different way by rebuilding a pipe it has not reached yet.
##
## When the jam itself cannot be built over — the cart is standing on it, or it
## is already run through — the track further back usually can be, and turning
## the route aside a cell earlier saves the run just as well. This is the move
## a player makes without thinking about it and the bot used to die without.
func _reroute(piece: int) -> bool:
	var path := _route()
	# Latest first: the change closest to the jam disturbs the least track.
	for i in range(path.size() - 1, -1, -1):
		var cell: Vector2i = path[i]["cell"]
		var entry: int = path[i]["entry"]
		if not _board.can_place(cell):
			continue
		if not _serves(piece, entry):
			continue
		var existing := _board.get_pipe(cell)
		if existing != null and existing.type == piece:
			continue  # same pipe, same jam
		var exit: int = PipeDefs.exit_side(piece, entry)
		if exit == PipeDefs.NO_EXIT:
			continue
		var next: Vector2i = cell + PipeDefs.DIR[exit]
		if next.x < 0 or next.x >= _main.balance.cols:
			continue
		if _board.rocks.has(next) or not _clear(next, PipeDefs.OPPOSITE[exit]):
			continue
		var rows := _board.visible_rows()
		if next.y > rows.y - 1:
			continue
		_main._try_place(cell)
		return true
	return false


## Where this bot sits between the two presets, 0..1. Every skill-dependent
## number is a lerp along this, so the presets keep exactly the behaviour they
## were tuned and measured at.
func _grade() -> float:
	return clampf((proficiency - SHOWCASE_LEVEL)
		/ maxf(EXPERT_LEVEL - SHOWCASE_LEVEL, 0.001), 0.0, 1.0)


## Whether it is good enough to plan rather than react.
func _plans() -> bool:
	return proficiency >= PLANS_FROM


## Whether the cart survives entering this cell from `side`. Empty ground is
## fine — that is just track not built yet. A pipe already there has to take
## that entry, and one the cart has run through can no longer be replaced.
func _accepts(cell: Vector2i, side: int) -> bool:
	var existing := _board.get_pipe(cell)
	if existing == null:
		return true
	if PipeDefs.SIDES[existing.type].has(side):
		return true
	return not existing.flooded and _board.can_place(cell)


## Somewhere useful for a piece that does not serve the joint.
##
## The refusal version of this — decline the move unless the queue can follow
## it — measured worse than no expertise at all: refusing costs a turn, the
## buffer drains, and the cart derails anyway. Building ahead spends the same
## turn on track the cart will need, which is what a strong player does with
## an awkward piece.
##
## It lays into the column the route is climbing, one or two cells past the
## joint, where the cart will arrive from below.
func _stockpile(joint: Vector2i, piece: int) -> bool:
	if not _plans():
		return false
	if not _serves(piece, PipeDefs.Side.D):
		return false  # nothing that takes the cart from below, no use up there

	# Only stockpile straight ahead when the route is not about to turn off
	# towards fuel.
	var target := _nearest_crystal()
	if target != Board.NO_CELL and absi(target.x - joint.x) > 1:
		return false

	var rows := _board.visible_rows()
	for step in [1, 2]:
		var spot := Vector2i(joint.x, joint.y + step)
		if spot.y > rows.y - 1:
			break
		if _board.get_pipe(spot) != null:
			continue
		if not _board.can_place(spot):
			continue
		var exit: int = PipeDefs.exit_side(piece, PipeDefs.Side.D)
		if exit == PipeDefs.NO_EXIT:
			continue
		var next: Vector2i = spot + PipeDefs.DIR[exit]
		if next.x < 0 or next.x >= _main.balance.cols or _board.rocks.has(next):
			continue
		_main._try_place(spot)
		return true
	return false


## When to start caring about fuel. The expert plans its refuelling earlier,
## because a hundred cells cannot be crossed on one tank.
func _thirst() -> float:
	return lerpf(THIRSTY, 0.75, _grade())


## The nearest crystal ahead that is actually on screen. Chasing one off the
## top of the display would take the run out of frame.
func _nearest_crystal() -> Vector2i:
	var rows := _board.visible_rows()
	var best := Board.NO_CELL
	var best_cost := 999
	for cell: Vector2i in _board.crystals:
		if cell.y <= _cart.row or cell.y > rows.y:
			continue
		var cost: int = (cell.y - _cart.row) + absi(cell.x - _cart.col) * 2
		if cost < best_cost:
			best_cost = cost
			best = cell
	return best


func _serves(piece: int, need: int) -> bool:
	return PipeDefs.SIDES[piece].has(need)


func _place(cell: Vector2i) -> void:
	# The occasional misplay, so the run has texture.
	if _rng.randf() < MISTAKE_CHANCE * (1.0 - _grade()):
		var sideways: int = [PipeDefs.Side.L, PipeDefs.Side.R][_rng.randi() % 2]
		var slip: Vector2i = cell + PipeDefs.DIR[sideways]
		if _board.can_place(slip):
			_main._try_place(slip)
			return
	_main._try_place(cell)


## Junk goes behind the cart, in the litter zone — the play the game is built
## around. It also has to go somewhere visible: a piece dropped off the bottom
## of the screen looks to a viewer like the piece simply vanished.
func _dump(joint: Vector2i) -> void:
	var rows := _board.visible_rows()
	var lowest: int = maxi(_board.max_row - _main.balance.place_below, rows.x + 1)
	var highest: int = mini(_cart.row, rows.y)

	var best := Board.NO_CELL
	var best_score := -1000.0
	for row in range(lowest, highest):
		for col in _main.balance.cols:
			var spot := Vector2i(col, row)
			if spot == joint or _board.get_pipe(spot) != null:
				continue
			if not _board.can_place(spot):
				continue
			# Just behind the cart and off to one side: in shot, out of the way.
			var score := 6.0 - absf(float(_cart.row - row) - 2.0) \
				+ absf(col - _cart.col) * 0.5
			if score > best_score:
				best_score = score
				best = spot

	if best != Board.NO_CELL:
		_main._try_place(best)
