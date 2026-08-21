## One permanent upgrade bought with crystals between runs.
## Spec section 11, P0: the player loses, but comes back stronger.
class_name Upgrade
extends Resource

@export var id: StringName = &""
@export var display_name: String = ""
@export var description: String = ""
## Crystal cost of each level in turn. Its length is the maximum level.
@export var costs: PackedInt32Array = PackedInt32Array()
## What one level is worth. Read through Upgrades.bonus().
@export var step: float = 1.0
## Suffix for the shop line, e.g. "fuel" gives "+15 fuel".
@export var unit: String = ""


func max_level() -> int:
	return costs.size()


## Cost to go from `level` to the next one, or -1 when it is maxed out.
func cost_at(level: int) -> int:
	if level < 0 or level >= costs.size():
		return -1
	return costs[level]
