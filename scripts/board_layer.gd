## Thin drawing proxy. Board splits its rendering across two of these so the
## expensive terrain pass can redraw a couple of times a second while the
## ghost and frontier ring redraw every frame. Spec section 12: 60 FPS with
## 300+ pipes on the board.
extends Node2D

## Name of the Board method that fills this layer, called with the layer itself
## as the canvas item to draw into.
@export var draw_method: StringName


func _draw() -> void:
	var board := get_parent()
	if board != null and board.has_method(draw_method):
		board.call(draw_method, self)
