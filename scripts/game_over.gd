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
	%RetryButton.text = "Try Again"
	%ContinueButton.visible = offer_continue
	_title.text = reason
	_final_score.text = str(score)
	_distance.text = "%d cells climbed" % distance

	if is_record and went_further:
		_record.text = "NEW BEST  ·  FURTHEST YET"
	elif is_record:
		_record.text = "NEW BEST"
	elif went_further:
		_record.text = "FURTHEST YET"
	_record.visible = is_record or went_further
	if is_record and went_further:
		_record.text = "NEW BEST  ·  FURTHEST YET"


## The other end of a story run: the goal was met, so this is a finish rather
## than a crash. Retry becomes "next station" once there is one.
func show_station_cleared(level: Level, reward: int, campaign_done: bool) -> void:
	visible = true
	%ContinueButton.visible = false
	_title.text = "STATION %d CLEARED" % level.number
	_final_score.text = level.title
	_distance.text = ("+%d crystals" % reward) if reward > 0 else "Already cleared"
	_record.text = "STORY COMPLETE" if campaign_done else ""
	_record.visible = campaign_done
	%RetryButton.text = "Menu" if campaign_done else "Next"


func hide_overlay() -> void:
	visible = false
