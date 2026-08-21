## Full-screen tints: the crystal flash, the low-fuel pulse, and the red
## warning when the cart is about to run out of track.
class_name ScreenFx
extends CanvasLayer

const FLASH_TIME := 0.2

@onready var _flash: ColorRect = $Flash
@onready var _low_fuel: ColorRect = $LowFuel
@onready var _danger: ColorRect = $Danger

## Set by Main: fuel below a quarter of a tank.
var _skin: LocationSkin
var low_fuel: bool = false
## Set by Main: one cell of built track left, or none.
var danger: bool = false

var _flash_left: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	set_skin(Skins.current())
	_flash.color = Color(_skin.accent, 0.0)
	_low_fuel.color = Color(_skin.danger, 0.0)
	_danger.color = Color(_skin.danger, 0.0)


## Repaints with a new location skin.
func set_skin(skin: LocationSkin) -> void:
	_skin = skin
	_flash.color = Color(_skin.accent, _flash.color.a)
	_low_fuel.color = Color(_skin.danger, _low_fuel.color.a)
	_danger.color = Color(_skin.danger, _danger.color.a)


func flash() -> void:
	_flash_left = FLASH_TIME


func clear() -> void:
	_flash_left = 0.0
	low_fuel = false
	danger = false


func _process(delta: float) -> void:
	_time += delta

	if _flash_left > 0.0:
		_flash_left -= delta
	_flash.color.a = maxf(_flash_left / FLASH_TIME, 0.0) * 0.22

	_low_fuel.color.a = (0.09 + 0.06 * sin(_time * 6.0)) if low_fuel else 0.0
	_danger.color.a = (0.13 + 0.10 * sin(_time * 14.0)) if danger else 0.0
