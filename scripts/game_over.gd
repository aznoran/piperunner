## End-of-run card: why the run ended, what it scored, and the two ways out.
class_name GameOverScreen
extends CanvasLayer

signal retry_pressed
signal menu_pressed

@onready var _title: Label = %Title
@onready var _final_score: Label = %FinalScore
@onready var _record: Label = %Record


func _ready() -> void:
	%RetryButton.pressed.connect(func() -> void: retry_pressed.emit())
	%MenuButton.pressed.connect(func() -> void: menu_pressed.emit())
	visible = false


func show_game_over(reason: String, score: int, is_record: bool) -> void:
	visible = true
	_title.text = reason
	_final_score.text = str(score)
	_record.visible = is_record


func hide_overlay() -> void:
	visible = false
