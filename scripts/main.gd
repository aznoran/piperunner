## Run orchestration: state machine, score, fuel, camera and the wiring between
## board, cart, queue and UI. Spec sections 02, 05, 06, 07 and 10.
extends Node2D

enum State { MENU, PLAYING, DEAD }

const REASON_OUT_OF_FUEL := "Out of fuel"
## Beat before the game-over card slides in, so the crash is legible.
const DEATH_PAUSE := 0.42
## Seconds the daily banner stays up before fading out.
const BANNER_TIME := 2.6
## Seconds for the menu to clear and for the generated world to arrive. The
## board is a touch slower so the two do not finish on the same frame.
const MENU_FADE := 0.24
const WORLD_REVEAL := 0.55
## Prototype shake, expressed against its 68 px cell so it scales with layout.
const SHAKE_REFERENCE_CELL := 68.0

## The untouched baseline from disk. Never modified — meta upgrades are
## applied to a copy (spec section 10 keeps the .tres as the tuning sheet).
@export var base_balance: GameBalance
## base_balance plus whatever the player has bought. Rebuilt for each run.
var balance: GameBalance
## Cells of reach around the cart that pull crystals in. 0 = must drive over.
var _magnet_reach: int = 0

@onready var _board: Board = $World/Board
@onready var _cart: Cart = $World/Cart
@onready var _fx: Fx = $World/Fx
@onready var _camera: Camera2D = $Camera
@onready var _hud: Hud = $Hud
@onready var _queue_bar: QueueBar = $Ui/QueueBar
@onready var _screen_fx: ScreenFx = $ScreenFx
@onready var _overlay: GameOverScreen = $GameOver
@onready var _menu: MainMenu = $MainMenu
@onready var _input: InputHandler = $InputHandler
@onready var _start_hint: Label = %StartHint
@onready var _mode_banner: Label = %ModeBanner
@onready var _background: TextureRect = $Background/Gradient

var state: State = State.MENU

var _queue := PipeQueue.new()
var _queue_rng := RandomNumberGenerator.new()

var score: int = 0
var combo: int = 0
var cells_run: int = 0
var crystals_collected: int = 0
## Rows climbed this run. Distinct from score, which also pays for crystals.
var distance: int = 0
## Longest chain this run, for the quest that asks for one.
var best_combo: int = 0
## Pipes dropped in a row below the cart — the litter play from spec 08, and
## the only quest metric nothing was counting yet.
var pipes_dumped: int = 0
var fuel: float = 0.0
var speed: float = 0.0
## The cart waits for the player's first pipe. Spec section 02.
var started: bool = false
## True while playing today's fixed-seed challenge (spec section 11, P1).
var daily_mode: bool = false

var _cell_size: float = 100.0
var _camera_frozen: bool = false
var _freeze_timer: float = 0.0
## 0 = camera follows freely, 1 = fully parked under a finger.
var _freeze_blend: float = 0.0
var _shake: float = 0.0
var _death_pause: float = 0.0
var _death_reason: String = ""
var _death_was_record: bool = false
var _death_went_further: bool = false
var _hint_pulse: float = 0.0
var _banner_left: float = 0.0


func _ready() -> void:
	if base_balance == null:
		base_balance = load("res://resources/GameBalance.tres")
	_rebuild_balance()

	_board.setup(balance)
	_cart.board = _board
	_cart.stepped.connect(_on_cart_stepped)
	_cart.derailed.connect(_on_cart_derailed)

	_input.hold_tapped.connect(_on_hold_tapped)
	_input.aim_started.connect(_on_aim_moved)
	_input.aim_moved.connect(_on_aim_moved)
	_input.aim_released.connect(_on_aim_released)
	_input.aim_cancelled.connect(_on_aim_cancelled)

	_hud.back_pressed.connect(abandon_run)
	_menu.location_chosen.connect(apply_skin)
	_menu.cart_chosen.connect(func(variant: int) -> void:
		_cart.variant = variant
		_cart.queue_redraw())
	_menu.start_pressed.connect(start_run.bind(false))
	_menu.daily_pressed.connect(start_run.bind(true))
	_overlay.retry_pressed.connect(func() -> void: start_run(daily_mode))
	_overlay.menu_pressed.connect(_show_menu)
	GameState.best_changed.connect(_hud.set_best)
	get_viewport().size_changed.connect(_apply_layout)

	_apply_layout()
	var saved := Skins.by_name(GameState.location)
	if saved != null:
		apply_skin(saved)
	_cart.variant = GameState.cart_variant
	_hud.set_best(GameState.best)
	_hud.set_score(0)
	_hud.set_fuel(1.0)
	_show_menu()


## Folds bought upgrades into a copy of the baseline. Called before every run,
## so a purchase made in the shop takes effect on the next one.
func _rebuild_balance() -> void:
	balance = base_balance.duplicate()
	balance.fuel_max += Upgrades.bonus(&"tank", GameState)
	balance.queue_preview += int(Upgrades.bonus(&"preview", GameState))
	balance.runway += int(Upgrades.bonus(&"runway", GameState))
	_magnet_reach = int(Upgrades.bonus(&"magnet", GameState))
	if _board != null:
		_board.setup(balance)


## Switches the location's look. Rules, generation and events are untouched —
## a skin is purely visual, so any location plays identically.
func apply_skin(skin: LocationSkin) -> void:
	if skin == null:
		return
	Skins.set_current(skin)
	_background.set_skin(skin)
	_board.set_skin(skin)
	_cart.set_skin(skin)
	_queue_bar.set_skin(skin)
	_hud.set_skin(skin)
	_screen_fx.set_skin(skin)


## Cell size follows viewport width: the board is always exactly 7 columns wide
## (spec section 03).
func _apply_layout() -> void:
	var viewport := get_viewport_rect().size
	_cell_size = viewport.x / float(balance.cols)

	_board.set_cell_size(_cell_size)
	_cart.set_cell_size(_cell_size)
	_fx.set_cell_size(_cell_size)
	_queue_bar.set_cell_size(_cell_size)

	_input.hold_rect = _queue_bar.hold_rect
	_input.queue_strip_top = _queue_bar.strip_top
	_camera.position.x = viewport.x * 0.5


## Back out to the menu. Only reachable before the first pipe is placed — once
## the cart is rolling the way out is to finish the run — so there is nothing
## to bank and nothing to lose by leaving.
func abandon_run() -> void:
	if state == State.PLAYING and started:
		return
	_show_menu()


## The HUD lives on a CanvasLayer, which has no modulate of its own.
func _hud_root() -> CanvasItem:
	return _hud.get_node("Safe")


func _fade_in(item: CanvasItem, duration: float) -> void:
	item.modulate.a = 0.0
	create_tween().tween_property(item, "modulate:a", 1.0, duration)


func _show_menu() -> void:
	state = State.MENU
	daily_mode = false
	_board.reveal = 1.0
	_input.enabled = false
	_queue_bar.visible = false
	_hud.visible = false
	_start_hint.visible = false
	_mode_banner.visible = false
	_board.hide_ghost()
	_board.hide_frontier()
	# The title screen sits over a live but empty board.
	_prepare_board(false)
	_overlay.hide_overlay()
	_menu.open()


## Lays out a fresh world and parks the cart on the runway. On the title screen
## the board stays bare — just the cart and the runway ahead of it.
func _prepare_board(with_resources: bool) -> void:
	# One seed drives the whole run; the queue gets its own stream so tuning the
	# preview length cannot reshuffle the map. On a daily the seed comes from
	# the date, so every player gets the same board (spec section 11, P1).
	var run_seed: int = GameState.daily_seed() if daily_mode else randi()
	_board.start_run(run_seed, with_resources, _first_resource_row())
	_queue_rng.seed = run_seed + 1
	_queue.start(_queue_rng, balance.queue_preview)

	var start_col: int = balance.cols / 2
	_cart.place_at(start_col, 0, PipeDefs.Side.D)
	_board.flood(Vector2i(start_col, 0))
	_board.set_cart_cell(_cart.cell())

	_board.show_record(GameState.best_distance)

	_fx.clear()
	_screen_fx.clear()
	_snap_camera()


## First row that may hold a rock or a crystal: just past what the player can
## see when a run starts, so the opening screen is always clean.
func _first_resource_row() -> int:
	var ahead: float = balance.camera_anchor * get_viewport_rect().size.y / _cell_size
	return int(ceil(ahead)) + 2


func start_run(daily: bool = false) -> void:
	daily_mode = daily
	_overlay.hide_overlay()
	_menu.fade_out(MENU_FADE)
	state = State.PLAYING
	_rebuild_balance()

	score = 0
	combo = 0
	cells_run = 0
	distance = 0
	crystals_collected = 0
	best_combo = 0
	pipes_dumped = 0
	fuel = balance.fuel_max
	speed = balance.start_speed
	started = false
	_shake = 0.0
	_camera_frozen = false
	_death_pause = 0.0

	_prepare_board(true)
	_queue_bar.visible = true
	_hud.visible = true
	_queue_bar.set_contents(_queue.upcoming, _queue.held)
	_start_hint.visible = true
	_hint_pulse = 0.0

	# The world arrives rather than appearing: rock, crystals and the grid fade
	# up while the menu clears. Input waits for the menu to be out of the way,
	# so a stray finger on a menu button cannot drop a pipe.
	_input.enabled = false
	_board.reveal = 0.0
	create_tween().tween_property(_board, "reveal", 1.0, WORLD_REVEAL) \
		.set_trans(Tween.TRANS_SINE)
	_fade_in(_hud_root(), MENU_FADE)
	_fade_in(_queue_bar, MENU_FADE)
	var gate := create_tween()
	gate.tween_interval(MENU_FADE)
	gate.tween_callback(func() -> void:
		if state == State.PLAYING:
			_input.enabled = true)

	_hud.set_score(0)
	_hud.set_best(GameState.best)
	_hud.set_combo(0)
	_hud.set_fuel(1.0)
	_hud.reset_back_key()
	_hud.set_daily(daily_mode, GameState.today())
	_mode_banner.visible = daily_mode
	_mode_banner.modulate.a = 1.0
	_banner_left = BANNER_TIME if daily_mode else 0.0


func _process(delta: float) -> void:
	match state:
		State.PLAYING:
			_run_frame(delta)
		State.DEAD:
			_update_camera(delta)
			if _death_pause > 0.0:
				_death_pause -= delta
				if _death_pause <= 0.0:
					_overlay.show_game_over(_death_reason, score, distance, _death_was_record,
		_death_went_further)


func _run_frame(delta: float) -> void:
	if started:
		speed = minf(balance.start_speed + score * balance.speed_gain, balance.speed_cap)
		_cart.advance(delta, speed)
		if state != State.PLAYING:
			return  # the cart died mid-step
	else:
		_hint_pulse += delta
		_start_hint.modulate.a = 0.72 + 0.20 * sin(_hint_pulse * 3.3)

	if _banner_left > 0.0:
		_banner_left -= delta
		_mode_banner.modulate.a = clampf(_banner_left / 0.8, 0.0, 1.0)
		if _banner_left <= 0.0:
			_mode_banner.visible = false

	_board.set_cart_incoming(_cart.incoming_cell(balance.place_lockout_progress))
	_update_camera(delta)
	_update_frontier()


# --- camera -------------------------------------------------------------

## Follows the cart's fractional row and holds it at 72% of screen height.
## No dead zone: it banks up drift and then snaps, which felt worse.
func _camera_target() -> float:
	var viewport_height := get_viewport_rect().size.y
	return _cart.position.y - (balance.camera_anchor - 0.5) * viewport_height


func _snap_camera() -> void:
	_camera.position.y = _camera_target()
	_camera.offset = Vector2.ZERO
	_freeze_blend = 0.0


func _update_camera(delta: float) -> void:
	_shake *= pow(0.86, delta * 60.0)
	_camera.offset = (Vector2(randf() - 0.5, randf() - 0.5) * _shake
		if _shake > 0.3 else Vector2.ZERO)

	if _camera_frozen:
		# Safety release, so the cart can never slide out of frame under a
		# resting finger (spec section 06).
		_freeze_timer += delta
		if _freeze_timer >= balance.camera_freeze_timeout:
			_camera_frozen = false

	# The freeze eases in and out rather than snapping. A quick tap only dips
	# the follow rate for a few frames, which reads as smooth; holding still
	# brings the board to a complete stop within the ramp.
	_freeze_blend = move_toward(_freeze_blend, 1.0 if _camera_frozen else 0.0,
		delta / maxf(balance.camera_freeze_ramp, 0.001))

	var follow: float = balance.camera_follow * (1.0 - _freeze_blend)
	if follow <= 0.0:
		return

	var target := _camera_target()
	_camera.position.y += (target - _camera.position.y) * minf(delta * follow, 1.0)


# --- lookahead ----------------------------------------------------------

## Marks the cell where the cart needs pipe next, and warns when the track is
## about to run out.
func _update_frontier() -> void:
	var ahead := _board.frontier(_cart.cell(), _cart.entry)
	if ahead.is_empty():
		_board.hide_frontier()
		_screen_fx.danger = false
		return

	var cell: Vector2i = ahead["cell"]
	var need: int = ahead["need"]
	var fits: bool = (not ahead["blocked"]
		and PipeDefs.SIDES[_queue.current()].has(need)
		and _board.can_place(cell))
	_board.show_frontier(cell, need, fits)
	_screen_fx.danger = started and int(ahead["steps"]) <= 1


# --- input --------------------------------------------------------------

func _on_hold_tapped() -> void:
	if state != State.PLAYING:
		return
	_queue.swap_hold()
	_queue_bar.set_contents(_queue.upcoming, _queue.held)
	_fx.burst(_screen_to_world(_queue_bar.hold_rect.get_center()),
		Skins.current().warn, 10, _cell_size * 4.0)
	GameState.vibrate(balance.haptics_place_ms)


func _on_aim_moved(world_position: Vector2) -> void:
	if state != State.PLAYING:
		return
	# Freeze the board so it cannot slide out from under the finger.
	if not _camera_frozen:
		_camera_frozen = true
		_freeze_timer = 0.0
	_board.show_ghost(_board.world_to_cell(world_position), _queue.current())


func _on_aim_released(world_position: Vector2) -> void:
	_camera_frozen = false
	_board.hide_ghost()
	if state != State.PLAYING:
		return
	_try_place(_board.world_to_cell(world_position))


func _on_aim_cancelled() -> void:
	_camera_frozen = false
	_board.hide_ghost()


# --- placement ----------------------------------------------------------

func _try_place(cell: Vector2i) -> void:
	if not _board.can_place(cell):
		return

	# Building over an unused pipe is allowed, but it costs fuel — a real trade
	# rather than a free undo (spec section 08).
	if _board.get_pipe(cell) != null:
		fuel -= balance.fuel_replace
		_fx.floater(_board.cell_to_world(cell), "-%d" % int(balance.fuel_replace),
			Skins.current().danger)
		_hud.set_fuel(fuel / balance.fuel_max)
		if fuel <= 0.0:
			fuel = 0.0
			_die(REASON_OUT_OF_FUEL)
			return

	if _board.place(cell, _queue.current()) == Board.Placement.REJECTED:
		return

	if cell.y < _cart.row:
		pipes_dumped += 1

	_queue.consume()
	_queue_bar.set_contents(_queue.upcoming, _queue.held)
	if not started:
		_hud.fade_out_back_key()
	started = true
	_start_hint.visible = false
	GameState.vibrate(balance.haptics_place_ms)


# --- run events ---------------------------------------------------------

func _on_cart_stepped(cell: Vector2i) -> void:
	_board.set_cart_cell(cell)

	var previous_max := _board.max_row
	_board.note_row_reached(cell.y)
	if cell.y > previous_max:
		score += cell.y - previous_max
		distance = _board.max_row
		_note_crystals_passed(previous_max, cell.y)

	cells_run += 1

	for spot in _pull_crystals(cell):
		combo += 1
		best_combo = maxi(best_combo, combo)
		crystals_collected += 1
		fuel = minf(balance.fuel_max, fuel + balance.fuel_crystal + minf(
			combo * balance.fuel_combo_bonus, balance.fuel_combo_bonus_cap))
		var points: int = balance.crystal_points * mini(combo, balance.crystal_combo_cap)
		score += points

		var at := _board.cell_to_world(spot)
		_fx.burst(at, Skins.current().accent, 20, _cell_size * 6.0)
		_fx.floater(at, "+%d" % points, Skins.current().accent)
		_screen_fx.flash()
		_hud.set_combo(combo)
		GameState.vibrate(balance.haptics_crystal_ms)

	if cells_run > balance.grace_cells:
		fuel -= balance.fuel_per_cell
		if fuel <= 0.0:
			fuel = 0.0
			_hud.set_fuel(0.0)
			_die(REASON_OUT_OF_FUEL)
			return

	_board.ensure_rows(cell.y + balance.generate_ahead + 2)
	_hud.set_score(score)
	_hud.set_fuel(fuel / balance.fuel_max)

	var low := fuel / balance.fuel_max < 0.25
	_cart.low_fuel = low
	_screen_fx.low_fuel = low


## Crystals collected by arriving at `cell`: the one under the cart, plus any
## within the magnet's reach. Nearest first, so the chain counts up outward.
func _pull_crystals(cell: Vector2i) -> Array[Vector2i]:
	var taken: Array[Vector2i] = []
	if _board.take_crystal(cell):
		taken.append(cell)
	for ring in range(1, _magnet_reach + 1):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dy)) != ring:
					continue  # only the shell of this ring
				var spot := cell + Vector2i(dx, dy)
				if _board.take_crystal(spot):
					taken.append(spot)
	return taken


## A crystal left behind in a row the cart has climbed past breaks the chain.
## The prototype never resets combo; the spec's acceptance list (section 14)
## requires it, so this is the missing rule made explicit.
func _note_crystals_passed(from_row: int, to_row: int) -> void:
	for row in range(from_row, to_row):
		for col in balance.cols:
			if _board.crystals.has(Vector2i(col, row)):
				combo = 0
				_hud.set_combo(0)
				return


func _on_cart_derailed(reason: String) -> void:
	_die(reason)


func _die(reason: String) -> void:
	if state != State.PLAYING:
		return
	state = State.DEAD
	_cart.alive = false
	_input.enabled = false
	_input.cancel()
	_board.hide_ghost()
	_board.hide_frontier()
	_screen_fx.danger = false
	_start_hint.visible = false

	_shake = 16.0 * (_cell_size / SHAKE_REFERENCE_CELL)
	_fx.burst(_cart.position, Skins.current().danger, 28, _cell_size * 8.0)
	GameState.vibrate(balance.haptics_death_ms)
	_bank_run()

	_death_reason = ("%s  ·  daily" % reason) if daily_mode else reason
	_death_pause = DEATH_PAUSE


## Files the finished run: currency, goal progress and both records.
func _bank_run() -> void:
	GameState.bank_crystals(crystals_collected)
	Quests.report(GameState, {
		"crystals": crystals_collected,
		"cells": cells_run,
		"dumped": pipes_dumped,
		"score": score,
		"combo": best_combo,
	})
	_death_was_record = GameState.submit_score(score)
	_death_went_further = GameState.submit_distance(distance)
	if daily_mode:
		GameState.submit_daily(score)
	_hud.set_best(GameState.best)


func _screen_to_world(screen_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * screen_position
