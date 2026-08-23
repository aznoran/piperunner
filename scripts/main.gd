## Run orchestration: state machine, score, fuel, camera and the wiring between
## board, cart, offer and UI. Spec sections 02, 05, 06, 07 and 10.
extends Node2D

enum State { MENU, PLAYING, DEAD }

## What the run key launches. Classic is endless; a daily is endless on a
## shared map; a story run ends when its station's goal is met.
enum Mode { CLASSIC, DAILY, STORY }

const REASON_OUT_OF_FUEL := "Out of fuel"
## Beat before the game-over card slides in, so the crash is legible.
const DEATH_PAUSE := 0.42
## Longer beat after a station is cleared: the win is worth watching.
const CLEAR_CELEBRATION := 1.35
## Seconds for the menu to clear and for the generated world to arrive. The
## board is a touch slower so the two do not finish on the same frame.
const MENU_FADE := 0.24
const WORLD_REVEAL := 0.55
## Where the cart sits on the title screen, as a fraction of screen height.
## Higher than in play, which also lets the first crystals show in the
## distance rather than leaving the menu as one bare track.
const MENU_CAMERA_ANCHOR := 0.46
## Seconds the camera takes to push forward into the run.
const CAMERA_PUSH := 0.7
## Curtain timings for the trip back from a finished run.
const CURTAIN_OUT := 0.26
const CURTAIN_IN := 0.34
## Prototype shake, expressed against its 68 px cell so it scales with layout.
const SHAKE_REFERENCE_CELL := 68.0

## The untouched baseline from disk. Never modified — meta upgrades are
## applied to a copy (spec section 10 keeps the .tres as the tuning sheet).
@export var base_balance: GameBalance
## base_balance plus whatever the player has bought. Rebuilt for each run.
var balance: GameBalance
## Cells of reach around the cart that pull crystals in. 0 = must drive over.
var _magnet_reach: int = 0
## Seconds on the clock when the live run began, for the run's duration.
var _run_began: float = 0.0
## When the last pipe went down, so the log can carry how long the player took
## over each decision — hesitation is behaviour too.
var _last_placed_at: float = 0.0
## The seed the live board was generated from. Kept so a logged run can name
## the board it was played on: a run coming out of the menu reuses the board
## laid out there, so the seed is settled well before the run begins.
var _board_seed: int = 0
## Benchmarks pin the run seed here so the same board can be replayed. -1 in
## normal play, where every run is its own.
var forced_seed: int = -1

@onready var _board: Board = $World/Board
@onready var _cart: Cart = $World/Cart
@onready var _fx: Fx = $World/Fx
@onready var _camera: Camera2D = $Camera
@onready var _hud: Hud = $Hud
@onready var _offer_bar: OfferBar = $Ui/OfferBar
@onready var _screen_fx: ScreenFx = $ScreenFx
@onready var _overlay: GameOverScreen = $GameOver
@onready var _menu: MainMenu = $MainMenu
@onready var _input: InputHandler = $InputHandler
@onready var _autoplayer: Autoplayer = $Autoplayer
@onready var _start_hint: Label = %StartHint
@onready var _praise_slot: Control = %PraiseSlot
@onready var _praise_label: Label = %PraiseLabel
@onready var _background: TextureRect = $Background/Gradient
@onready var _decor: MenuDecor = $World/Decor
@onready var _curtain: ColorRect = $Curtain/Fill

var state: State = State.MENU

## Where the next pipe comes from. Which variant this is comes from the
## experiment, and nothing below this line asks which.
var _blocks: BlockSource
## Which rule fills the offer. This line is the whole extension point: anything
## deriving from PipeDealer plugs in here and nothing else has to move.
var _dealer: PipeDealer
var _praise := Praise.new()
## Pipes placed since the last overwrite, for the clean-run praise.
var _clean_streak: int = 0
## Overwrites this run, which a station goal may one day care about.
var overwrites: int = 0
## True once this run has spent its one continue.
var continued: bool = false
var _offer_rng := RandomNumberGenerator.new()

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
## The mode the run key will launch, picked in the modes carousel.
var selected_mode: Mode = Mode.CLASSIC
## The station a story run is playing. Null outside story mode.
var active_level: Level

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
## True while the board on screen is the untouched one the menu laid out. A
## retry comes straight from the game-over card, where the board is the one
## just played — pipes flooded, rock gone, the lot — so it has to be rebuilt.
var _board_fresh: bool = false
## Set when a story station was just cleared, so the pause before the card
## knows which card to show.
var _pending_clear: Dictionary = {}
var _hint_pulse: float = 0.0
## Where the camera holds the cart right now. Animated on the way into a run
## instead of switching, which is what made the cart appear to teleport.
var _camera_anchor: float = MENU_CAMERA_ANCHOR


func _ready() -> void:
	if base_balance == null:
		base_balance = load("res://resources/GameBalance.tres")
	_rebuild_balance()

	_board.setup(balance)
	_build_source()
	# Remote Config may answer after the game is already up. When it does, the
	# variant can change out from under a menu that has not been played yet —
	# which is exactly when it is safe to swap the mechanic.
	Experiment.resolved.connect(_on_variant_resolved)
	# Experiment publishes during its own _ready, before anything here is
	# listening, so the group is stamped once by hand as well as on the signal.
	_stamp_variant()
	Analytics.session_start()
	_praise.setup(balance)
	_cart.board = _board
	_cart.stepped.connect(_on_cart_stepped)
	_cart.derailed.connect(_on_cart_derailed)

	_input.offer_chosen.connect(_on_offer_chosen)
	_input.aim_started.connect(_on_aim_moved)
	_input.aim_moved.connect(_on_aim_moved)
	_input.aim_released.connect(_on_aim_released)
	_input.aim_cancelled.connect(_on_aim_cancelled)

	_hud.back_pressed.connect(abandon_run)
	_menu.location_chosen.connect(apply_skin)
	_menu.cart_chosen.connect(func(variant: int) -> void:
		_cart.variant = variant
		_cart.queue_redraw())
	_menu.start_pressed.connect(func() -> void: start_run(selected_mode))
	_menu.mode_chosen.connect(_select_mode)
	_menu.level_chosen.connect(_select_level)
	_menu.autoplay_requested.connect(_launch_autoplay)
	_autoplayer.setup(self, _board, _cart, _blocks)
	_autoplayer.took_over.connect(PlayLog.note_player)
	_overlay.retry_pressed.connect(func() -> void: start_run(selected_mode))
	_overlay.menu_pressed.connect(_curtain_to_menu)
	_overlay.continue_pressed.connect(_take_continue)
	GameState.best_changed.connect(_hud.set_best)
	get_viewport().size_changed.connect(_apply_layout)

	_apply_layout()
	var saved := Skins.by_name(GameState.location)
	if saved != null:
		apply_skin(saved)
	_refresh_mode_name()
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
	balance.offer_size += int(Upgrades.bonus(&"preview", GameState))
	balance.runway += int(Upgrades.bonus(&"runway", GameState))
	_magnet_reach = int(Upgrades.bonus(&"magnet", GameState))
	if _board != null:
		_board.setup(balance)
	if _dealer != null:
		_dealer.setup(balance)
	_praise.setup(balance)


## Hands a classic run to the autoplayer, for recording. The run itself is
## ordinary — same scoring, same records, same everything — because the player
## it runs through is the same one a finger drives.
func _start_autoplay() -> void:
	_launch_autoplay(Autoplayer.SHOWCASE_LEVEL)


## The one that is supposed to go the distance rather than look human.
func _start_expert_autoplay() -> void:
	_launch_autoplay(Autoplayer.EXPERT_LEVEL)


## `level` is how well it plays, 0..1 — see Autoplayer.proficiency. The two
## buttons pass the presets; the debug bench passes whatever the slider says.
func _launch_autoplay(level: float, style: Persona = null) -> void:
	selected_mode = Mode.CLASSIC
	_refresh_mode_name()
	start_run(Mode.CLASSIC)
	var plans: bool = level >= Autoplayer.PLANS_FROM
	if plans:
		_equip_for_the_long_run()
	_autoplayer.start(
		Autoplayer.Skill.EXPERT if plans else Autoplayer.Skill.SHOWCASE,
		-1, level, style)


## Gives the expert the loadout a fully upgraded player would bring, for this
## run only — the save is untouched.
##
## This is not a cheat code, it is the top of the shop: a hundred cells burns
## about three tanks, so on the starting tank the distance is arithmetic, not
## skill. A player who wants to see a hundred has bought these too.
func _equip_for_the_long_run() -> void:
	for upgrade in Upgrades.catalogue():
		var maxed: float = upgrade.step * upgrade.max_level()
		match String(upgrade.id):
			"tank":
				balance.fuel_max += maxed
			"preview":
				balance.offer_size += int(maxed)
			"runway":
				balance.runway += int(maxed)
			"magnet":
				_magnet_reach = int(maxed)
	fuel = balance.fuel_max
	_hud.set_fuel(1.0)
	_blocks.resize(_deal_context())
	_refresh_strip()


## The experiment settled on a group. Rebuilding is only safe between runs; a
## run in progress keeps the mechanic it started with, because a player whose
## strip changed mid-run is not a clean data point for either variant.
func _on_variant_resolved(_variant: int) -> void:
	_stamp_variant()
	if state != State.MENU:
		return
	_build_source()
	_blocks.start(_offer_rng, balance, _dealer, _deal_context())
	_refresh_strip()


## Puts the group on the user, which is the only thing Firebase's own
## retention report can be split by — D1 and D7 come from sessions the SDK logs
## itself, and those carry none of our parameters.
func _stamp_variant() -> void:
	Analytics.set_variant(Experiment.name_of(), Experiment.debug_override)


## Closes out the session, and the run inside it if one is live.
##
## Backgrounding the app on a phone is how most runs actually end, so it counts
## as abandoning that run rather than as nothing happening at all.
func _close_session() -> void:
	if state == State.PLAYING and started:
		Analytics.run_abandoned(distance, _seconds() - _run_began, "backgrounded")
		PlayLog.end_run(distance, score, "backgrounded")
	Analytics.session_end()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST:
			_close_session()
		NOTIFICATION_APPLICATION_RESUMED:
			Analytics.session_start()


## Builds the block source for the experiment's live variant, and the dealing
## rule that variant was designed around. Called at boot, and again whenever
## the debug bench forces a different variant.
##
## This is the only place in the game a variant letter turns into behaviour.
func _build_source() -> void:
	_blocks = Experiment.make_source()
	_dealer = _blocks.make_dealer()
	_dealer.setup(balance)
	_blocks.attach(_offer_bar)
	# The bot reads the strip through the same object the player taps, so it
	# has to be re-pointed at the new one. Holding the old source left it
	# reading a strip that had never been dealt.
	if _autoplayer != null:
		_autoplayer.setup(self, _board, _cart, _blocks)


## Shows the strip the live variant plays on, and only that one.
func _show_strip() -> void:
	_blocks.attach(_offer_bar)
	_blocks.reveal()
	_refresh_strip()


func _hide_strip() -> void:
	_offer_bar.visible = false


## Spends the chosen shape and deals whatever replaces it.
##
## The event goes out before the deal, so `slot` and `was_held` still describe
## the strip the player was looking at when they chose — after the deal, in
## variant C, the window has already been refilled.
func _spend_block(cell: Vector2i) -> void:
	Analytics.block_taken(_blocks.current(), _blocks.chosen_slot(),
		_blocks.slot_count(), _blocks.chosen_was_held(), distance)
	# The strip as it stood, before the deal replaces any of it.
	PlayLog.record(_blocks.current(), _blocks.chosen_slot(),
		_blocks.slot_count(), _blocks.chosen_was_held(), _blocks.choices(),
		cell, _cart.cell(), _joint_need(), fuel, distance, speed,
		_seconds() - _last_placed_at, _board_window())
	_last_placed_at = _seconds()
	_blocks.spend(_deal_context())
	_refresh_strip()


## Switches the location's look. Rules, generation and events are untouched —
## a skin is purely visual, so any location plays identically.
func apply_skin(skin: LocationSkin) -> void:
	if skin == null:
		return
	Skins.set_current(skin)
	_background.set_skin(skin)
	_decor.setup(skin, _cell_size, balance.cols)
	_board.set_skin(skin)
	_cart.set_skin(skin)
	_offer_bar.set_skin(skin)
	_hud.set_skin(skin)
	_screen_fx.set_skin(skin)


## Cell size follows viewport width: the board is always exactly 7 columns wide
## (spec section 03).
func _apply_layout() -> void:
	var viewport := get_viewport_rect().size
	_cell_size = viewport.x / float(balance.cols)

	_board.set_cell_size(_cell_size)
	_decor.setup(Skins.current(), _cell_size, balance.cols)
	_cart.set_cell_size(_cell_size)
	_fx.set_cell_size(_cell_size)
	_offer_bar.set_cell_size(_cell_size)
	_refresh_strip()
	_camera.position.x = viewport.x * 0.5


## Back out to the menu. Only reachable before the first pipe is placed — once
## the cart is rolling the way out is to finish the run — so there is nothing
## to bank and nothing to lose by leaving.
func abandon_run() -> void:
	if state == State.PLAYING and started:
		return
	if state == State.PLAYING:
		# Walked out before laying a pipe. Worth its own event: a player who
		# opens a run and leaves it is telling you something a death does not.
		Analytics.run_abandoned(distance, _seconds() - _run_began,
			"before_first_pipe")
		PlayLog.end_run(distance, score, "abandoned")
	_show_menu(true)


## Leaves a finished run behind a black curtain rather than by animating the
## camera back. After a crash the player is done with that board — watching it
## scroll away replays it. This lands them on the title screen as if they had
## just opened the game.
func _curtain_to_menu() -> void:
	_curtain.color.a = 0.0
	var tween := create_tween()
	tween.tween_property(_curtain, "color:a", 1.0, CURTAIN_OUT) \
		.set_trans(Tween.TRANS_SINE)
	tween.tween_callback(func() -> void: _show_menu())
	tween.tween_property(_curtain, "color:a", 0.0, CURTAIN_IN) \
		.set_trans(Tween.TRANS_SINE)


## A mode is chosen in the menu and launched by the run key, rather than each
## mode carrying its own button — that keeps one obvious way to start.
func _select_mode(mode: Mode) -> void:
	selected_mode = mode
	daily_mode = mode == Mode.DAILY
	_autoplayer.stop()
	if mode == Mode.STORY:
		active_level = Levels.current(GameState)
	_refresh_mode_name()
	# The menu shows the board the next run will be played on, so a mode change
	# lays its map out now rather than swapping it at the press.
	_prepare_board(true)
	_snap_camera()


## Picks a specific station and switches to story mode.
func _select_level(number: int) -> void:
	active_level = Levels.find(number)
	if active_level == null:
		return
	selected_mode = Mode.STORY
	daily_mode = false
	_refresh_mode_name()
	_prepare_board(true)
	_snap_camera()


func _refresh_mode_name() -> void:
	match selected_mode:
		Mode.DAILY:
			_menu.set_mode_name("TODAY", _menu.MODE_DAILY,
				"One map, same for everyone")
		Mode.STORY:
			if active_level == null:
				_menu.set_mode_name("STORY", _menu.MODE_STORY)
			else:
				_menu.set_mode_name("%d · %s" % [active_level.number, active_level.title],
					_menu.MODE_STORY, active_level.goal_text())
		_:
			_menu.set_mode_name("CLASSIC", _menu.MODE_CLASSIC)


func _set_camera_anchor(value: float) -> void:
	_camera_anchor = value


## Puts the cart back on the runway without disturbing the board the menu has
## already laid out.
func _reset_cart() -> void:
	var start_col: int = balance.cols / 2
	_cart.place_at(start_col, 0, PipeDefs.Side.D)
	_board.flood(Vector2i(start_col, 0))
	_board.set_cart_cell(_cart.cell())
	_board.set_cart_incoming(Board.NO_CELL)
	_board.set_cart_fill(_cart.cell(), 0.0, _cart.entry)
	_route_clear()


func _route_clear() -> void:
	_board.show_record(GameState.best_distance)


## The HUD lives on a CanvasLayer, which has no modulate of its own.
func _hud_root() -> CanvasItem:
	return _hud.get_node("Safe")


func _fade_in(item: CanvasItem, duration: float) -> void:
	item.modulate.a = 0.0
	create_tween().tween_property(item, "modulate:a", 1.0, duration)


## `animated` pulls the camera back out to the title framing and fades the
## menu in, for the trip a player takes with the back key. The first call at
## boot has nothing to animate from, so it snaps.
func _show_menu(animated: bool = false) -> void:
	state = State.MENU
	_autoplayer.stop()
	# Purchases made in the depot take effect on the board the menu lays out.
	_rebuild_balance()
	daily_mode = false
	# Every transition-owned flag goes back to its resting value here, so a
	# menu reached from any direction — title, back key, game over — is in the
	# same state.
	_death_pause = 0.0
	_input.enabled = false
	_input.cancel()
	_board.reveal = 1.0
	_input.enabled = false
	_hide_strip()
	_hud.visible = false
	_start_hint.visible = false
	_board.hide_ghost()
	_board.hide_frontier()
	# The title screen sits over a live but empty board.
	_decor.visible = true
	_prepare_board(true)
	_overlay.hide_overlay()
	_menu.open()

	if not animated:
		_camera_anchor = MENU_CAMERA_ANCHOR
		_decor.modulate.a = MenuDecor.RESTING_ALPHA
		_snap_camera()
		return

	# Pull back out the way we pushed in, so leaving a run reads as a move
	# rather than a cut.
	create_tween().tween_method(_set_camera_anchor, _camera_anchor,
		MENU_CAMERA_ANCHOR, CAMERA_PUSH).set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_IN_OUT)
	_decor.modulate.a = 0.0
	create_tween().tween_property(_decor, "modulate:a", MenuDecor.RESTING_ALPHA,
		MENU_FADE * 1.6)


## Lays out a fresh world and parks the cart on the runway. On the title screen
## the board stays bare — just the cart and the runway ahead of it.
func _prepare_board(with_resources: bool) -> void:
	# One seed drives the whole run; the offer gets its own stream so changing
	# how many shapes are dealt cannot reshuffle the map. On a daily the seed
	# comes from the date, so every player gets the same board (spec 11, P1).
	# A daily and a story station are fixed maps; classic rolls a fresh one.
	var run_seed: int = forced_seed if forced_seed >= 0 else randi()
	if daily_mode:
		run_seed = GameState.daily_seed()
	elif selected_mode == Mode.STORY and active_level != null:
		run_seed = Levels.seed_for(active_level)
	_board.start_run(run_seed, with_resources, _first_resource_row())
	_board_seed = run_seed
	_offer_rng.seed = run_seed + 1

	var start_col: int = balance.cols / 2
	_cart.place_at(start_col, 0, PipeDefs.Side.D)
	_board.flood(Vector2i(start_col, 0))
	_board.set_cart_cell(_cart.cell())

	# Dealt once the cart is parked, so the rule is asked about the joint this
	# run opens on rather than about whatever the last one ended on.
	_blocks.start(_offer_rng, balance, _dealer, _deal_context())

	_board.show_record(GameState.best_distance)

	_board.set_cart_fill(_cart.cell(), 0.0, _cart.entry)
	_board_fresh = true
	_fx.clear()
	_screen_fx.clear()
	_snap_camera()


## First row that may hold a rock or a crystal: just past what the player can
## see when a run starts, so the opening screen is always clean.
func _first_resource_row() -> int:
	var ahead: float = balance.camera_anchor * get_viewport_rect().size.y / _cell_size
	return int(ceil(ahead)) + 2


func start_run(mode: Mode = Mode.CLASSIC) -> void:
	# A run started straight off the end card is a retry; one started from the
	# menu is not. The overlay is only up in the first case.
	if state == State.DEAD:
		Analytics.retry()
	_run_began = _seconds()
	_last_placed_at = _run_began
	selected_mode = mode
	daily_mode = mode == Mode.DAILY
	_autoplayer.stop()
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
	overwrites = 0
	continued = false
	_clean_streak = 0
	_praise.start_run()
	fuel = balance.fuel_max
	speed = balance.start_speed
	started = false
	_shake = 0.0
	_camera_frozen = false
	_death_pause = 0.0

	# Coming from the menu the board is already laid out for this mode, and
	# reusing it is what makes the start read as a move rather than a cut.
	# Coming from a retry it is the board just played, and has to go.
	if _board_fresh:
		_reset_cart()
	else:
		_prepare_board(true)
	_board_fresh = false

	# Opened here rather than where the board is prepared: a run out of the
	# menu reuses that board, so preparing it is not the same event as playing
	# it, and a header written there would describe the wrong run.
	PlayLog.begin_run(Experiment.name_of(), _board_seed, int(selected_mode))
	_decor.visible = false
	# The board came from the menu, so the offer was dealt before this run's
	# balance sheet existed; an upgrade that widens it has to be applied now.
	_blocks.resize(_deal_context())
	_show_strip()
	_hud.visible = true
	_refresh_strip()
	_start_hint.visible = true
	_hint_pulse = 0.0

	# The camera pushes forward into the run while the menu clears: the cart
	# settles into its playing position instead of jumping there. On a daily
	# the board was just rebuilt, so its contents fade up too.
	_input.enabled = false
	# The disused tracks belong to the menu; they clear as the run begins.
	var fade_decor := create_tween()
	fade_decor.tween_property(_decor, "modulate:a", 0.0, MENU_FADE)
	fade_decor.tween_callback(func() -> void: _decor.visible = false)

	var push := create_tween()
	push.tween_method(_set_camera_anchor, _camera_anchor, balance.camera_anchor,
		CAMERA_PUSH).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_fade_in(_hud_root(), MENU_FADE)
	_fade_in(_blocks.strip(), MENU_FADE)
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
	_hud.set_objective(active_level if selected_mode == Mode.STORY else null, 0)


func _process(delta: float) -> void:
	match state:
		State.PLAYING:
			_run_frame(delta)
		State.MENU:
			_update_camera(delta)
		State.DEAD:
			_update_camera(delta)
			if _death_pause > 0.0:
				_death_pause -= delta
				if _death_pause <= 0.0:
					_show_end_card()


func _run_frame(delta: float) -> void:
	if started:
		speed = minf(balance.start_speed + score * balance.speed_gain, balance.speed_cap)
		_burn_fuel(balance.fuel_per_second * delta)
		if state != State.PLAYING:
			return
		_cart.advance(delta, speed)
		if state != State.PLAYING:
			return  # the cart died mid-step
	else:
		_hint_pulse += delta
		_start_hint.modulate.a = 0.72 + 0.20 * sin(_hint_pulse * 3.3)

	_board.set_cart_incoming(_cart.incoming_cell(balance.place_lockout_progress))
	_board.set_cart_fill(_cart.cell(), _cart.t, _cart.entry)
	_praise.tick(delta)
	_update_camera(delta)
	_update_frontier()


# --- camera -------------------------------------------------------------

## Follows the cart's fractional row and holds it at 72% of screen height.
## No dead zone: it banks up drift and then snaps, which felt worse.
func _camera_target() -> float:
	var viewport_height := get_viewport_rect().size.y
	return _cart.position.y - (_camera_anchor - 0.5) * viewport_height


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

## Shows a praise message, if the selector lets this one through. The pop is
## short on purpose: it has to land inside the moment it is praising, or it
## teaches the player about luck rather than about skill.
func _praise_for(kind: Praise.Kind, combo_value: int = 0) -> void:
	var text := _praise.consider(kind, combo_value)
	if text.is_empty():
		return

	_praise_label.text = text
	# The label lives inside a slot so the rise can move it without fighting the
	# anchors that place it — animating an anchored control's position drags it
	# to the top of the screen, which is where this went the first time.
	_praise_slot.visible = true
	_praise_slot.modulate = Color(Skins.current().accent, 1.0)
	if kind == Praise.Kind.RECORD:
		_praise_slot.modulate = Color(Skins.current().warn, 1.0)
	_praise_label.pivot_offset = _praise_label.size * 0.5
	_praise_label.scale = Vector2(0.7, 0.7)
	_praise_label.position = Vector2.ZERO

	var tween := create_tween()
	tween.tween_property(_praise_label, "scale", Vector2.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.45)
	tween.set_parallel(true)
	tween.tween_property(_praise_slot, "modulate:a", 0.0, 0.35)
	tween.tween_property(_praise_label, "position:y", -44.0, 0.35)
	tween.chain().tween_callback(func() -> void: _praise_slot.visible = false)


## The side the cart will arrive from at the joint it still has to reach, or
## NO_EXIT when the track ahead is already built.
func _joint_need() -> int:
	var ahead := _board.frontier(_cart.cell(), _cart.entry)
	if ahead.is_empty() or ahead["blocked"]:
		return PipeDefs.NO_EXIT
	return int(ahead["need"])


## Cells of built track in front of the cart.
func _buffer() -> int:
	var ahead := _board.frontier(_cart.cell(), _cart.entry)
	return int(ahead["steps"]) if not ahead.is_empty() else 0


## Everything a dealing rule may look at, gathered in one place so that a rule
## which starts caring about something new does not mean touching every site
## that deals an offer.
## The board around the cart, flattened for the behaviour log.
##
## Written relative to the cart rather than in board coordinates: the board
## scrolls forever, so an absolute row number says nothing about what the
## decision looked like, while "two rows below the cart" says everything.
func _board_window() -> PackedByteArray:
	var window := PackedByteArray()
	var cart := _cart.cell()
	for row in range(cart.y - PlayLog.WINDOW_ROWS_BELOW,
			cart.y + PlayLog.WINDOW_ROWS_ABOVE):
		for col in balance.cols:
			var cell := Vector2i(col, row)
			var pipe := _board.get_pipe(cell)
			if pipe != null:
				window.append(PlayLog.FLOODED if pipe.flooded else pipe.type)
			elif _board.rocks.has(cell):
				window.append(PlayLog.ROCK)
			elif _board.crystals.has(cell):
				window.append(PlayLog.CRYSTAL)
			else:
				window.append(PlayLog.EMPTY)
	return window


## Seconds on the wall clock. Wrapped so the run timer and the session timer
## agree on what a second is.
func _seconds() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


func _deal_context() -> Dictionary:
	return {
		"need": _joint_need(),
		"buffer": _buffer(),
		"fuel": fuel,
		"fuel_max": balance.fuel_max,
		"runs_played": GameState.runs_played,
		"in_slump": GameState.in_slump(),
	}


## Repaints the strip and re-points the input handler at it. Both the number of
## slots and where they sit move when the offer is re-dealt, so the two have to
## travel together or a tap lands on the shape next door.
func _refresh_strip() -> void:
	if _blocks == null:
		return
	_blocks.refresh()
	_input.offer_rects = _blocks.tap_targets()
	_input.offer_strip_top = _blocks.strip_top()


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
		and PipeDefs.SIDES[_blocks.current()].has(need)
		and _board.can_place(cell))
	_board.show_frontier(cell, need, fits)
	_screen_fx.danger = started and int(ahead["steps"]) <= 1


# --- input --------------------------------------------------------------

## Points the next placement at one of the shapes on offer. It costs nothing
## and may be done as often as the player likes: the turn is spent by placing,
## not by choosing.
func _on_offer_chosen(index: int) -> void:
	if state != State.PLAYING:
		return
	if not _blocks.point_at(index):
		return
	_refresh_strip()
	# The ghost is still holding up the shape chosen a moment ago.
	_board.hide_ghost()
	GameState.vibrate(balance.haptics_place_ms)


func _on_aim_moved(world_position: Vector2) -> void:
	if state != State.PLAYING:
		return
	# Freeze the board so it cannot slide out from under the finger.
	if not _camera_frozen:
		_camera_frozen = true
		_freeze_timer = 0.0
	_board.show_ghost(_board.world_to_cell(world_position), _blocks.current())


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
	# A joint served with nothing built ahead of the cart: the player placed it
	# as the cart was already rolling in. The only praise here that cannot be
	# earned by accident.
	var was_clutch: bool = cell == _board.frontier(_cart.cell(), _cart.entry).get(
		"cell", Board.NO_CELL) and _buffer() == 0 and started

	if _board.get_pipe(cell) != null:
		overwrites += 1
		_clean_streak = 0
		fuel -= balance.fuel_replace
		_fx.floater(_board.cell_to_world(cell), "-%d" % int(balance.fuel_replace),
			Skins.current().danger)
		_hud.set_fuel(fuel / balance.fuel_max)
		if fuel <= 0.0:
			fuel = 0.0
			_die(REASON_OUT_OF_FUEL)
			return

	if _board.place(cell, _blocks.current()) == Board.Placement.REJECTED:
		return

	if cell.y < _cart.row:
		pipes_dumped += 1

	_spend_block(cell)
	if not started:
		_hud.fade_out_back_key()
	started = true
	_start_hint.visible = false

	if was_clutch:
		_praise_for(Praise.Kind.CLUTCH)
	else:
		_clean_streak += 1
		if _clean_streak == balance.praise_clean_run:
			_praise_for(Praise.Kind.CLEAN)
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
		if GameState.best_distance > 0 and distance == GameState.best_distance + 1:
			_praise_for(Praise.Kind.RECORD)

	cells_run += 1

	var taken := _pull_crystals(cell)
	for spot in taken:
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

	if taken.size() >= 2:
		_praise_for(Praise.Kind.SWEEP)
	elif not taken.is_empty() and combo >= _praise.chain_threshold(distance):
		_praise_for(Praise.Kind.CHAIN, combo)

	if cells_run > balance.grace_cells:
		_burn_fuel(balance.fuel_per_cell)
		if state != State.PLAYING:
			return

	_board.ensure_rows(cell.y + balance.generate_ahead + 2)
	_check_station_goal()
	if state != State.PLAYING:
		return
	_hud.set_score(score)
	_hud.set_fuel(fuel / balance.fuel_max)

	var low := fuel / balance.fuel_max < 0.25
	_cart.low_fuel = low
	_screen_fx.low_fuel = low


## Single place fuel leaves the tank, so running dry always ends the run the
## same way whichever drain emptied it.
func _burn_fuel(amount: float) -> void:
	if amount <= 0.0:
		return
	fuel -= amount
	if fuel <= 0.0:
		fuel = 0.0
		_hud.set_fuel(0.0)
		_die(REASON_OUT_OF_FUEL)
		return
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
	Analytics.run_completed(distance, score, _seconds() - _run_began, reason)
	PlayLog.end_run(distance, score, reason)
	_bank_run()

	_pending_clear = {}
	_death_reason = ("%s  ·  daily" % reason) if daily_mode else reason
	_death_pause = DEATH_PAUSE


## Everything a goal can be measured against, in one place.
func run_metrics() -> Dictionary:
	return {
		"distance": distance,
		"crystals": crystals_collected,
		"chain": best_combo,
		"dumped": pipes_dumped,
		"cells": cells_run,
		"score": score,
	}


## A story run ends the moment its station's goal is met — that is the whole
## difference from an endless one. Reaching it is a finish, not a crash.
func _check_station_goal() -> void:
	if selected_mode != Mode.STORY or active_level == null:
		return
	var metrics := run_metrics()
	_hud.set_objective(active_level, Levels.progress(active_level, metrics))
	if not Levels.is_met(active_level, metrics):
		return

	state = State.DEAD
	_cart.alive = false
	_input.enabled = false
	_input.cancel()
	_board.hide_ghost()
	_board.hide_frontier()
	_screen_fx.danger = false
	_screen_fx.flash()
	_fx.burst(_cart.position, Skins.current().accent, 34, _cell_size * 8.0)
	GameState.vibrate(balance.haptics_crystal_ms)
	_bank_run()

	var reward := Levels.clear(GameState, active_level.number)
	var cleared := active_level
	active_level = Levels.current(GameState)
	_refresh_mode_name()
	_death_reason = ""
	_pending_clear = {"level": cleared, "reward": reward}
	_celebrate(cleared)


## The win itself, before the card. A station cleared is the only thing in the
## game worth interrupting the flow for, so it gets its own beat: the board
## flashes, the cart throws sparks, and the words land where praise lands.
func _celebrate(level: Level) -> void:
	_death_pause = CLEAR_CELEBRATION

	_praise_label.text = "CLEARED"
	_praise_slot.visible = true
	_praise_slot.modulate = Color(Skins.current().accent, 1.0)
	_praise_label.pivot_offset = _praise_label.size * 0.5
	_praise_label.scale = Vector2(0.5, 0.5)
	_praise_label.position = Vector2.ZERO

	var tween := create_tween()
	tween.tween_property(_praise_label, "scale", Vector2(1.15, 1.15), 0.22) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_praise_label, "scale", Vector2.ONE, 0.12)
	tween.tween_interval(0.5)
	tween.set_parallel(true)
	tween.tween_property(_praise_slot, "modulate:a", 0.0, 0.3)
	tween.tween_property(_praise_label, "position:y", -50.0, 0.3)
	tween.chain().tween_callback(func() -> void: _praise_slot.visible = false)

	# A second burst a beat after the first, so the celebration has a rhythm
	# rather than a single pop.
	var sparks := create_tween()
	sparks.tween_interval(0.18)
	sparks.tween_callback(func() -> void:
		_fx.burst(_cart.position, Skins.current().warn, 26, _cell_size * 7.0)
		_screen_fx.flash())


## A run ends one of two ways, and they are not the same event: a station goal
## met is a finish, a crash is a crash.
func _show_end_card() -> void:
	if _pending_clear.is_empty():
		_overlay.show_game_over(_death_reason, score, distance, _death_was_record,
			_death_went_further, _continue_is_worth_offering())
		return
	_overlay.show_station_cleared(_pending_clear["level"], _pending_clear["reward"],
		Levels.all_cleared(GameState))
	_pending_clear = {}


## Whether this death is the kind worth offering a way out of: close to the
## record, close to a station's goal, or simply a long run. A continue on a
## twelve-cell death is not a favour, it is an interruption.
func _continue_is_worth_offering() -> bool:
	if continued or not started:
		return false
	if GameState.runs_played < balance.continue_first_run:
		return false
	if Time.get_unix_time_from_system() - GameState.last_continue < balance.continue_cooldown:
		return false

	if distance >= balance.continue_min_distance:
		return true
	if GameState.best_distance > 0 \
			and distance >= GameState.best_distance * balance.continue_record_ratio:
		return true
	if selected_mode == Mode.STORY and active_level != null:
		var progress := Levels.progress(active_level, run_metrics())
		return progress >= active_level.goal_target * balance.continue_goal_ratio
	return false


## Puts the cart back on the last track it was actually on and refuels part of
## the tank. Not a revival on the spot: the crash still cost something, or the
## offer would cheapen every death that follows.
func _take_continue() -> void:
	if state != State.DEAD or continued:
		return
	continued = true
	GameState.last_continue = Time.get_unix_time_from_system()
	GameState.save_game()

	_overlay.hide_overlay()
	_pending_clear = {}
	_death_pause = 0.0

	var back: Vector2i = _cart.last_cell
	if _board.get_pipe(back) == null:
		back = Vector2i(balance.cols / 2, maxi(_board.max_row - balance.continue_rollback, 0))
		if _board.get_pipe(back) == null:
			_curtain_to_menu()
			return

	_cart.place_at(back.x, back.y, _cart.last_entry)
	_board.set_cart_cell(_cart.cell())
	_board.set_cart_incoming(Board.NO_CELL)
	_board.set_cart_fill(_cart.cell(), 0.0, _cart.entry)

	fuel = balance.fuel_max * balance.continue_fuel_ratio
	_hud.set_fuel(fuel / balance.fuel_max)
	_cart.low_fuel = false
	_screen_fx.low_fuel = false
	_screen_fx.danger = false
	combo = 0
	_hud.set_combo(0)

	# A fresh offer: the one that killed them is not the one to come back with.
	_blocks.start(_offer_rng, balance, _dealer, _deal_context())
	_refresh_strip()

	state = State.PLAYING
	_input.enabled = true
	_fx.burst(_cart.position, Skins.current().accent, 24, _cell_size * 6.0)
	GameState.vibrate(balance.haptics_crystal_ms)


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
	# A continued run does not set a distance record. Distance is what the
	# ghost line on the board measures and what the story goals count, so it
	# has to mean one uninterrupted run — otherwise the record stops being
	# something to race.
	_death_went_further = false if continued else GameState.submit_distance(distance)
	GameState.note_run(distance)
	if daily_mode:
		GameState.submit_daily(score)
	_hud.set_best(GameState.best)

