## Particle bursts and floating score text, drawn from fixed pools so the
## frame loop never allocates a node (spec section 12).
class_name Fx
extends Node2D

const PARTICLE_POOL := 256
const FLOATER_POOL := 16
const GRAVITY := 620.0

class Particle:
	var position: Vector2
	var velocity: Vector2
	var life: float = 0.0
	var max_life: float = 1.0
	var color: Color

class Floater:
	var position: Vector2
	var text: String = ""
	var life: float = 0.0
	var max_life: float = 1.0
	var color: Color

var _particles: Array[Particle] = []
var _floaters: Array[Floater] = []
var _next_particle: int = 0
var _next_floater: int = 0
var _font: Font
var _font_size: int = 26


func _ready() -> void:
	for i in PARTICLE_POOL:
		_particles.append(Particle.new())
	for i in FLOATER_POOL:
		_floaters.append(Floater.new())
	_font = ThemeDB.fallback_font


func set_cell_size(size: float) -> void:
	_font_size = maxi(12, int(size * 0.26))


func burst(at: Vector2, color: Color, count: int, spread: float) -> void:
	for i in count:
		var particle := _particles[_next_particle]
		_next_particle = (_next_particle + 1) % PARTICLE_POOL
		particle.position = at
		particle.velocity = Vector2(randf() - 0.5, randf() - 0.5 - 0.25) * spread
		particle.max_life = randf_range(0.4, 0.7)
		particle.life = particle.max_life
		particle.color = color


func floater(at: Vector2, text: String, color: Color) -> void:
	var item := _floaters[_next_floater]
	_next_floater = (_next_floater + 1) % FLOATER_POOL
	item.position = at
	item.text = text
	item.color = color
	item.max_life = 0.75
	item.life = item.max_life


func clear() -> void:
	for particle in _particles:
		particle.life = 0.0
	for item in _floaters:
		item.life = 0.0


func _process(delta: float) -> void:
	for particle in _particles:
		if particle.life <= 0.0:
			continue
		particle.life -= delta
		particle.velocity.y += GRAVITY * delta
		particle.position += particle.velocity * delta
	for item in _floaters:
		if item.life <= 0.0:
			continue
		item.life -= delta
		item.position.y -= 54.0 * delta
	queue_redraw()


func _draw() -> void:
	for particle in _particles:
		if particle.life <= 0.0:
			continue
		var color := particle.color
		color.a *= clampf(particle.life / particle.max_life, 0.0, 1.0)
		draw_circle(particle.position, 3.5, color)

	if _font == null:
		return
	for item in _floaters:
		if item.life <= 0.0:
			continue
		var color := item.color
		color.a *= clampf(item.life / item.max_life, 0.0, 1.0)
		var width := _font.get_string_size(item.text, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, _font_size).x
		draw_string(_font, item.position - Vector2(width * 0.5, 0.0), item.text,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, _font_size, color)
