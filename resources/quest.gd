## One rotating goal. Spec section 11, P2.
##
## A quest is a metric, a target and a payout. Which metric it watches decides
## how it is scored: most accumulate across the day's runs, while the ones
## phrased "in one run" keep the best single attempt instead.
class_name Quest
extends Resource

@export var id: StringName = &""
## Printf template with one %d for the target, e.g. "Collect %d crystals".
@export var description: String = ""
## Which run statistic this watches: crystals, cells, dumped, score, combo.
@export var metric: StringName = &""
## Candidate targets. The day's roll picks one, so the same quest is not
## identical every time it comes up.
@export var targets: PackedInt32Array = PackedInt32Array()
## Crystals paid on completion.
@export var reward: int = 40
## True for "in one run" goals: progress is the best single run, not the sum.
@export var single_run: bool = false


func text(target: int) -> String:
	# The description is a printf template held in the .tres, so it is the
	# template that gets translated and the number that gets substituted —
	# the other way round would need one key per target.
	return tr(description) % target
