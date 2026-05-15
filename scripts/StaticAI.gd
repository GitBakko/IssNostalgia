class_name StaticAI
extends Node

## Sprint 8 T04 — static-formation AI driver for the non-human team.
##
## Implements the R05 cluster (Game AI Pro 2 Ch.30 + Voronoi-static
## arxiv 2501.05870 + Frontiers PMC12163489 role-differentiated
## positioning). NO per-frame influence map, NO Voronoi computation,
## NO grid:
##   target_position = anchor + (ball - anchor) * role_factor
##
## Tactical update at `update_hz` (default 2 Hz / 500 ms). Position
## interpolation runs at the player's normal physics tick (120 Hz)
## via `Player.set_static_target` autopilot. R05-F01 says tactical
## decisions don't need 60+ Hz on mobile; per-tick lerp gives smooth
## movement without spiking CPU.
##
## Role factors (R05-F03 / R05-F05):
##   GK  = 0.10  (handled by Goalkeeper.gd in T05 — skipped here)
##   DEF = 0.30
##   MID = 0.50
##   ATT = 0.70
##
## Skipped:
##   - Human teams (`team_controller.is_human == true`) — driven by
##     their PlayerController instead.
##   - Goalkeepers — Goalkeeper.gd (T05) owns their target.
##
## The active-player concept (TeamController.active_index) is HUD /
## indicator state for the human side; on the AI side every outfield
## player gets a formation target so the whole team holds shape.

# ---- Role factor table (R05-F03) ----------------------------------------
const ROLE_FACTOR_GK: float = 0.10
const ROLE_FACTOR_DEF: float = 0.30
const ROLE_FACTOR_MID: float = 0.50
const ROLE_FACTOR_ATT: float = 0.70

# ---- Exports -------------------------------------------------------------
@export var team_controller: TeamController
@export var ball_ref: Node3D
@export var formation: FormationData
## When true, the team defends +Z and uses `formation.get_anchor_mirrored`
## for every role. Team B by default in `GameMatch._spawn_team_b`.
@export var mirror_anchors: bool = false
## Tactical update rate (Hz). 2 Hz matches R05-F01 (Dave Mark — Game AI
## Pro 2 Ch.30) — tactical layer doesn't need per-frame updates.
@export var update_hz: float = 2.0
## Per-role max reposition speed (m/s, R05-F06). 0.0 = no override
## (Player default speeds). Velocity clamping prevents teleport feel.
@export var max_reposition_speed_def: float = 7.0
@export var max_reposition_speed_mid: float = 8.0
@export var max_reposition_speed_att: float = 9.0

# ---- Runtime state -------------------------------------------------------
var _update_timer_s: float = 0.0


func _physics_process(delta: float) -> void:
	step(delta)


## Tick the tactical timer; on overflow recompute targets and push them
## to the players. Pure-on-instance — tests drive `step(delta)` directly.
func step(delta: float) -> void:
	if team_controller == null or ball_ref == null or formation == null:
		return
	if team_controller.is_human:
		return
	var interval: float = 1.0 / maxf(update_hz, 0.1)
	_update_timer_s += delta
	if _update_timer_s < interval:
		return
	_update_timer_s = 0.0
	tick_targets()


## Recompute the formation target for every non-GK player on this team
## and push it to them via `Player.set_static_target`. Public so tests
## can fire a tactical update at a known instant without touching the
## timer.
func tick_targets() -> void:
	if team_controller == null or ball_ref == null or formation == null:
		return
	if team_controller.is_human:
		return  ## defensive — human teams never get an autopilot target
	var ball_pos: Vector3 = ball_ref.global_position
	for i in range(team_controller.players.size()):
		var p: Player = team_controller.players[i]
		if p == null or p.is_goalkeeper:
			continue  ## GK owned by Goalkeeper.gd (T05)
		var anchor: Vector3 = _anchor_for_role(i)
		var factor: float = _role_factor_for(i)
		var target: Vector3 = anchor + (ball_pos - anchor) * factor
		target.y = 0.0
		var max_speed: float = _max_speed_for(i)
		p.set_static_target(target, max_speed)


# ---- Internal -----------------------------------------------------------

func _anchor_for_role(role_index: int) -> Vector3:
	if mirror_anchors:
		return formation.get_anchor_mirrored(role_index)
	return formation.role_anchors[role_index]


func _role_factor_for(role_index: int) -> float:
	var role: StringName = formation.role_names[role_index]
	if role == &"gk":
		return ROLE_FACTOR_GK
	if role == &"mid":
		return ROLE_FACTOR_MID
	if role == &"att":
		return ROLE_FACTOR_ATT
	return ROLE_FACTOR_DEF  ## def_left, def_right


func _max_speed_for(role_index: int) -> float:
	var role: StringName = formation.role_names[role_index]
	if role == &"mid":
		return max_reposition_speed_mid
	if role == &"att":
		return max_reposition_speed_att
	return max_reposition_speed_def
