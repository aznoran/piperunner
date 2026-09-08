## Autoload. Bridge to the Yandex Games SDK, and the game's whole ad policy.
##
## The SDK is driven by a small JS shim in the web shell (window.YaBridge);
## GDScript calls plain functions and receives plain callbacks. Orchestrating
## the SDK's promises from GDScript is far more fragile than orchestrating them
## in the language they were written for.
##
## Every call degrades to a no-op, so the game stays fully playable off the
## platform — in the editor, on the phone builds, or when the SDK never loads.
## That is the reason a rewarded video grants its reward off-platform: the
## continue is a game feature that an ad happens to pay for, not the other way
## round, and it has to be testable without a browser.
extends Node

## Emitted once the rewarded video is done, whether or not it paid out.
signal rewarded_result(granted: bool)
## Emitted when a fullscreen ad closes — or immediately, when one is not shown.
signal interstitial_closed()
## Cloud progress, or an empty dictionary when there is none.
signal cloud_loaded(data: Dictionary)

## The platform's documented floor between fullscreen ads. Going under it is a
## moderation failure, so the cooldown is enforced here rather than trusted to
## the caller.
const INTERSTITIAL_COOLDOWN := 60.0
## Deaths between fullscreen ads. Every death is too many — the player is
## already being asked to sit through the game-over card — and the first death
## of a session is left alone entirely (see `_deaths`).
const DEATHS_PER_INTERSTITIAL := 2
## Longest an ad may hold the tree. A real ad closes well inside this; past it
## the callback is not coming and the game takes itself back.
const AD_TIMEOUT := 12.0
## Cloud writes are rate-limited by the platform, so saves are coalesced.
const CLOUD_FLUSH_DELAY := 4.0

var available := false
var lang := "ru"

## Typed loosely so a stand-in can be injected for testing the browser path.
var _bridge: Variant = null
## Callbacks must stay referenced or the JS side loses them to the collector.
var _cb_rewarded: Variant = null
var _cb_interstitial: Variant = null
var _cb_load: Variant = null

var _last_interstitial := -INTERSTITIAL_COOLDOWN
var _gameplay_running := false
var _in_ad := false
var _ad_elapsed := 0.0
## Deaths this session. Starts at 0 and is counted *before* the check, so the
## first fullscreen ad lands on the second death rather than the first.
var _deaths := 0
var _pending_cloud: Dictionary = {}
var _cloud_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("web"):
		return
	_bridge = JavaScriptBridge.get_interface("YaBridge")
	if _bridge == null:
		push_warning("YaBridge missing — running without the Yandex SDK")
		return

	_cb_rewarded = JavaScriptBridge.create_callback(_on_rewarded)
	_cb_interstitial = JavaScriptBridge.create_callback(_on_interstitial)
	_cb_load = JavaScriptBridge.create_callback(_on_cloud_loaded)
	_bridge.register(_cb_rewarded, _cb_interstitial, _cb_load)

	available = bool(_bridge.isReady())
	if available:
		lang = str(_bridge.getLang())
		# The platform knows which language the player opened the game in, and
		# it is a better answer than the browser's own setting — the same
		# browser serves ru and en catalogues. Off the platform Godot's default
		# (the system locale) already does the right thing, so it is left
		# alone rather than overridden with a guess.
		TranslationServer.set_locale(lang)


## Runs while the tree is paused (process_mode is ALWAYS), which is the whole
## point: an ad pauses everything, so a watchdog living in the game would be
## frozen alongside the thing it is meant to rescue.
func _process(delta: float) -> void:
	if _in_ad:
		_ad_elapsed += delta
		if _ad_elapsed > AD_TIMEOUT:
			push_warning("ad never closed; resuming")
			_leave_ad()
			interstitial_closed.emit()
			rewarded_result.emit(false)
	if _cloud_timer > 0.0:
		_cloud_timer -= delta
		if _cloud_timer <= 0.0:
			_flush_cloud()


func _notification(what: int) -> void:
	# Required by the platform: the game falls silent when it loses focus, and
	# has to survive the round trip through a fullscreen ad intact.
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_set_muted(true)
			_flush_cloud()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			if not _in_ad:
				_set_muted(false)


func _set_muted(muted: bool) -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), muted)


## Injects a stand-in bridge so the browser path can be exercised off-browser.
func install_test_bridge(bridge: Variant) -> void:
	_bridge = bridge
	_cb_rewarded = Callable(self, "_on_rewarded")
	_cb_interstitial = Callable(self, "_on_interstitial")
	_cb_load = Callable(self, "_on_cloud_loaded")
	_bridge.register(_cb_rewarded, _cb_interstitial, _cb_load)
	available = true


# --- platform lifecycle -------------------------------------------------

## Call once the first playable frame is on screen. Required for moderation:
## until it is called the platform holds its own loading screen over the game.
func loading_ready() -> void:
	if _bridge != null:
		_bridge.ready()


## Brackets active play, so the platform knows not to interrupt it.
func gameplay_start() -> void:
	if _gameplay_running:
		return
	_gameplay_running = true
	if _bridge != null:
		_bridge.gameplayStart()


func gameplay_stop() -> void:
	if not _gameplay_running:
		return
	_gameplay_running = false
	if _bridge != null:
		_bridge.gameplayStop()


# --- ads ----------------------------------------------------------------

## Whether a rewarded video is what stands between the player and a continue.
## Off-platform there is no ad to watch, so the button does not claim there is.
func rewarded_is_real() -> bool:
	return _bridge != null


## Opt-in rewarded video. Emits rewarded_result(true) only if it paid out.
func show_rewarded() -> void:
	if _bridge == null:
		# No platform: grant it, so the continue flow is playable in the editor
		# and on the phone builds, which have no ads at all.
		rewarded_result.emit(true)
		return
	_enter_ad()
	_bridge.showRewarded()


## Counts a death and shows a fullscreen ad if this is one of the ones that
## carries it. Emits interstitial_closed either way, so the caller can simply
## wait on the signal and not care which death this was.
func note_death() -> void:
	_deaths += 1
	if _deaths % DEATHS_PER_INTERSTITIAL != 0:
		interstitial_closed.emit()
		return
	show_interstitial()


## Fullscreen ad, rate-limited. Emits interstitial_closed either way.
func show_interstitial() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if _bridge == null or now - _last_interstitial < INTERSTITIAL_COOLDOWN:
		interstitial_closed.emit()
		return
	_last_interstitial = now
	_enter_ad()
	_bridge.showInterstitial()


## A rewarded video counts as the fullscreen ad the player owed: two in a row
## is the thing the platform's own guidelines call out, and the player who just
## sat through one voluntarily is the last one to punish.
func credit_ad_shown() -> void:
	_last_interstitial = Time.get_ticks_msec() / 1000.0
	_deaths = 0


## The platform requires the game to hold still and stay quiet behind an ad,
## and to come back exactly where it left off.
func _enter_ad() -> void:
	_in_ad = true
	_ad_elapsed = 0.0
	gameplay_stop()
	_set_muted(true)
	get_tree().paused = true


func _leave_ad() -> void:
	if not _in_ad:
		return
	_in_ad = false
	get_tree().paused = false
	_set_muted(false)


func _on_rewarded(args: Array) -> void:
	var granted := bool(args[0]) if args.size() > 0 else false
	_leave_ad()
	rewarded_result.emit(granted)


func _on_interstitial(_args: Array) -> void:
	_leave_ad()
	interstitial_closed.emit()


# --- cloud progress -----------------------------------------------------

## Asks for the player's cloud progress. Answers on cloud_loaded — with an
## empty dictionary off-platform, which is the caller's cue to keep what it
## already read off disk.
func load_cloud() -> void:
	if _bridge == null:
		cloud_loaded.emit({})
		return
	_bridge.load()


## Queues a cloud write. Coalesced: the platform rate-limits setData, and the
## game saves on every banked run.
func save_cloud(data: Dictionary) -> void:
	if _bridge == null:
		return
	_pending_cloud = data
	_cloud_timer = CLOUD_FLUSH_DELAY


func _flush_cloud() -> void:
	_cloud_timer = 0.0
	if _bridge == null or _pending_cloud.is_empty():
		return
	_bridge.save(JSON.stringify(_pending_cloud))
	_pending_cloud = {}


func _on_cloud_loaded(args: Array) -> void:
	var text := str(args[0]) if args.size() > 0 else ""
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	cloud_loaded.emit(parsed if parsed is Dictionary else {})
