## One station of the story run.
##
## A level is an ordinary run on a fixed map with a finish condition attached:
## reach it and the run ends in success rather than going on until the cart
## derails. The goal metrics are the same counters the daily goals use, so a
## level asks for nothing the game does not already measure.
class_name Level
extends Resource

@export var number: int = 1
@export var title: String = ""
## What the run has to produce: distance, crystals, chain, dumped.
@export var goal_metric: StringName = &"distance"
@export var goal_target: int = 10
## Mixed into the seed so every station has its own map, stable for everyone.
@export var seed_salt: int = 0
## Crystals paid the first time it is cleared.
@export var reward: int = 30


func goal_text() -> String:
	match String(goal_metric):
		"distance":
			return "Reach row %d" % goal_target
		"crystals":
			return "Collect %d crystals" % goal_target
		"chain":
			return "Chain %d crystals" % goal_target
		"dumped":
			return "Dump %d pipes behind you" % goal_target
		_:
			return "%s %d" % [goal_metric, goal_target]


## Short form for the HUD, where there is no room for a sentence.
func goal_short() -> String:
	match String(goal_metric):
		"distance":
			return "ROW %d" % goal_target
		"crystals":
			return "%d CRYSTALS" % goal_target
		"chain":
			return "CHAIN %d" % goal_target
		"dumped":
			return "%d DUMPED" % goal_target
		_:
			return "%s %d" % [goal_metric, goal_target]
