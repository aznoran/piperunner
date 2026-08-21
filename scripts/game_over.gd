## End-of-run card: why the run ended, what it scored, and the two ways out.
class_name GameOverScreen
extends CanvasLayer

signal retry_pressed
signal menu_pressed

@onready var _title: Label = %Title
@onready var _final_score: Label = %FinalScore
@onready var _distance: Label = %DistanceLabel
@onready var _record: Label = %Record


func _ready() -> void:
	%RetryButton.pressed.connect(func() -> void: retry_pressed.emit())
	%MenuButton.pressed.connect(func() -> void: menu_pressed.emit())
	visible = false


## Score and distance are reported separately: a run can score well on
## crystals without climbing far, and the two records move independently.
func show_game_over(reason: String, score: int, distance: int,
		is_record: bool, went_further: bool) -> void:
	visible = true
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


func hide_overlay() -> void:
	visible = false
