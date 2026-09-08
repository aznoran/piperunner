## End-of-run card: why the run ended, what it scored, and the two ways out.
class_name GameOverScreen
extends CanvasLayer

signal retry_pressed
signal menu_pressed
## The player took the continue offer.
signal continue_pressed

@onready var _title: Label = %Title
@onready var _final_score: Label = %FinalScore
@onready var _distance: Label = %DistanceLabel
@onready var _record: Label = %Record


func _ready() -> void:
	%RetryButton.pressed.connect(func() -> void: retry_pressed.emit())
	%MenuButton.pressed.connect(func() -> void: menu_pressed.emit())
	%ContinueButton.pressed.connect(func() -> void: continue_pressed.emit())
	visible = false


## Score and distance are reported separately: a run can score well on
## crystals without climbing far, and the two records move independently.
func show_game_over(reason: String, score: int, distance: int,
		is_record: bool, went_further: bool, offer_continue: bool = false) -> void:
	visible = true
	%RetryButton.text = tr("Try Again")
	%ContinueButton.visible = offer_continue
	# Say what it costs. On the platform the continue is paid for with a
	# rewarded video, and a button that asks for thirty seconds of the player's
	# time without saying so is the kind of thing that gets a game taken down.
	%ContinueButton.text = tr("Watch ad · Continue") if Yandex.rewarded_is_real() \
		else tr("Continue")
	# The reason travels as an English key from wherever the run ended —
	# Cart, Main — and is turned into words here, at the one place it is read.
	_title.text = tr(reason)
	_final_score.text = str(score)
	_distance.text = tr("%d cells climbed") % distance

	if is_record and went_further:
		_record.text = tr("NEW BEST  ·  FURTHEST YET")
	elif is_record:
		_record.text = tr("NEW BEST")
	elif went_further:
		_record.text = tr("FURTHEST YET")
	_record.visible = is_record or went_further
	if is_record and went_further:
		_record.text = tr("NEW BEST  ·  FURTHEST YET")


## The other end of a story run: the goal was met, so this is a finish rather
## than a crash. Retry becomes "next station" once there is one.
func show_station_cleared(level: Level, reward: int, campaign_done: bool) -> void:
	visible = true
	%ContinueButton.visible = false
	_title.text = tr("STATION %d CLEARED") % level.number
	_final_score.text = tr(level.title)
	_distance.text = (tr("+%d crystals") % reward) if reward > 0 else tr("Already cleared")
	_record.text = tr("STORY COMPLETE") if campaign_done else ""
	_record.visible = campaign_done
	%RetryButton.text = tr("Menu") if campaign_done else tr("Next")


## Puts the card back exactly as it was, with none of the reasoning that built
## it. Used when a rewarded video is skipped or fails: nothing about the run
## changed, so nothing about the card should be recomputed — least of all the
## death counter behind show_game_over's ad.
func reopen() -> void:
	visible = true


func hide_overlay() -> void:
	visible = false
