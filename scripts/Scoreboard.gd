class_name Scoreboard
extends Node

## Sprint 9 T03 — match scoreboard.
##
## Two ints, two signals. Goal detection lives elsewhere (GameMatch
## sweeps the ball position past the goal lines and calls
## `register_goal`). Designed for autoload OR per-scene injection;
## both wiring paths work because the API is pure.
##
## Team identifiers match `Goalkeeper.goal_z` sign convention:
##   - `TEAM_A = 0` (defends -Z, scores into +Z)
##   - `TEAM_B = 1` (defends +Z, scores into -Z)

const TEAM_A: int = 0
const TEAM_B: int = 1

# ---- Signals -------------------------------------------------------------
signal goal_scored(team: int, total_for_team: int)
signal score_changed(a: int, b: int)

# ---- Runtime state -------------------------------------------------------
var team_a_goals: int = 0
var team_b_goals: int = 0


# ---- Public API ----------------------------------------------------------

func register_goal(team: int) -> void:
	if team == TEAM_A:
		team_a_goals += 1
		goal_scored.emit(TEAM_A, team_a_goals)
	elif team == TEAM_B:
		team_b_goals += 1
		goal_scored.emit(TEAM_B, team_b_goals)
	else:
		push_warning("Scoreboard.register_goal: unknown team id %d" % team)
		return
	score_changed.emit(team_a_goals, team_b_goals)


## Goals scored BY the given team (the team that put the ball in
## the opposing net). Used by Goalkeeper catch-up eligibility.
func goals_for(team: int) -> int:
	if team == TEAM_A:
		return team_a_goals
	if team == TEAM_B:
		return team_b_goals
	return 0


## Score gap from the given team's perspective (positive = trailing,
## negative = leading, zero = tied). Mirrors the R09-F02 spec input.
func goal_gap_from(team: int) -> int:
	if team == TEAM_A:
		return team_b_goals - team_a_goals
	if team == TEAM_B:
		return team_a_goals - team_b_goals
	return 0


func reset() -> void:
	team_a_goals = 0
	team_b_goals = 0
	score_changed.emit(0, 0)
