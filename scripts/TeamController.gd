class_name TeamController
extends Node

## Sprint 6 T04 — Auto-switch (with hysteresis), manual cycle, selection
## indicator manager. ONE TeamController per team. Owns the team's roster
## (`players`) and the single `PlayerController` that currently drives the
## active player (the controller's `player` reference is mutated on switch).
##
## Decisions: S06-D01 (hysteresis 0.5 m + 3-frame hold), S06-D03 (tie-breaker
## human > AI — applied at possession layer in Sprint 7, NOT here),
## S06-D29 (TeamControllerB.is_human=true under both_human debug flag).

# ---- Tunables ------------------------------------------------------------
const SWITCH_THRESHOLD_M: float = 8.0     ## auto-switch distance gate
const SWITCH_DEAD_ZONE_M: float = 0.5     ## hysteresis half-width (S06-D01)
const SWITCH_HOLD_FRAMES: int = 3         ## minimum frames condition must
                                          ## stay true before commit (S06-D01)

# ---- Exports -------------------------------------------------------------
## Roster — 5 entries for a 2-1-1 + GK formation. Order matches the
## FormationData arrays the Player nodes were spawned from.
@export var players: Array[Player] = []

## The single PlayerController this team uses to drive whichever player
## is active. On switch, `controller.player` is updated to the new active.
@export var controller: PlayerController

@export var team_config: TeamConfig

## The "ball" — Node3D in Sprint 6 (mock), real RigidBody3D from Sprint 7.
## Used XZ-only for distance checks (Vector2(dx, dz).length_squared()).
@export var ball_ref: Node3D

## When true, the team is human-controlled and runs auto-switch + indicator
## logic. Static-AI teams skip both. Debug `both_human` (T06) flips Team B
## to true so tests can inhabit both sides locally.
@export var is_human: bool = false

# ---- Indicator visuals ---------------------------------------------------
const INDICATOR_RADIUS: float = 0.6
const INDICATOR_HEIGHT: float = 0.02
const INDICATOR_ACTIVE_ALPHA: float = 0.85
const INDICATOR_DIM_ALPHA: float = 0.25
const INDICATOR_Y_OFFSET: float = 0.011   ## just above the pitch plane

# ---- Runtime state -------------------------------------------------------
var active_index: int = 0
var _switch_pending_frames: int = 0
var _switch_pending_target: int = -1
var _indicators: Array[MeshInstance3D] = []


func _ready() -> void:
	_build_indicators()
	if not players.is_empty():
		active_index = _first_outfield_index()
		_assign_active_to_controller()
		_refresh_indicator_visuals()


# ---- Public API ----------------------------------------------------------

## Manual switch — cycles to the next outfield player (skipping the GK).
## Wired to `consume_buffered("switch_player")` from this team's controller
## so the input buffer + same-press-no-double-fire semantics apply.
func cycle_active_outfield() -> void:
	if players.is_empty():
		return
	var n: int = players.size()
	for offset in range(1, n + 1):
		var candidate: int = (active_index + offset) % n
		if not players[candidate].is_goalkeeper:
			_commit_switch(candidate)
			return


## Force-set the active player by index. Out-of-range indices and GK
## indices are no-ops. Used by tests / level scripts to set the initial
## active player from outside.
func set_active(new_index: int) -> void:
	if new_index < 0 or new_index >= players.size():
		return
	if players[new_index].is_goalkeeper:
		return
	_commit_switch(new_index)


## Pure-on-instance auto-switch step. Tests drive this with explicit
## ball-position state instead of going through `_physics_process`.
func step_autoswitch() -> void:
	if not is_human:
		return
	if controller == null or ball_ref == null or players.is_empty():
		return

	var active_player: Player = players[active_index]
	var active_dist: float = _xz_dist(active_player.global_position, ball_ref.global_position)

	# Hysteresis: only consider switching once we're CLEARLY outside the
	# threshold (above 8 + 0.5). Inside [7.5, 8.5] we hold whatever we
	# decided last (S06-D01).
	if active_dist <= SWITCH_THRESHOLD_M + SWITCH_DEAD_ZONE_M:
		_switch_pending_frames = 0
		_switch_pending_target = -1
		return

	# Block during shoot / pass animations (200 ms / 100 ms — S06 spec A2).
	# Player.is_busy_with_ball_action returns true when state ∈
	# {SHOOTING, PASSING}. PlayerController flags double-guard for cases
	# where the controller knows about the action before Player's state
	# updates (Sprint 7).
	if active_player.is_busy_with_ball_action() or controller.is_shooting or controller.is_passing:
		_switch_pending_frames = 0
		_switch_pending_target = -1
		return

	var closest_index: int = _closest_outfield_to_ball()
	if closest_index < 0 or closest_index == active_index:
		_switch_pending_frames = 0
		_switch_pending_target = -1
		return

	# Same target as last tick? Increment hold counter; otherwise restart.
	if closest_index == _switch_pending_target:
		_switch_pending_frames += 1
	else:
		_switch_pending_target = closest_index
		_switch_pending_frames = 1

	if _switch_pending_frames >= SWITCH_HOLD_FRAMES:
		_commit_switch(closest_index)


# ---- Lifecycle -----------------------------------------------------------

func _physics_process(_delta: float) -> void:
	if not is_human:
		return
	if controller != null and controller.consume_buffered(&"switch_player"):
		cycle_active_outfield()
	step_autoswitch()


# ---- Internal -----------------------------------------------------------

func _commit_switch(new_index: int) -> void:
	if new_index == active_index:
		return
	active_index = new_index
	_switch_pending_frames = 0
	_switch_pending_target = -1
	_assign_active_to_controller()
	_refresh_indicator_visuals()


func _assign_active_to_controller() -> void:
	if controller != null and active_index >= 0 and active_index < players.size():
		controller.player = players[active_index]


func _first_outfield_index() -> int:
	for i in range(players.size()):
		if not players[i].is_goalkeeper:
			return i
	return 0


func _closest_outfield_to_ball() -> int:
	var best_index: int = -1
	var best_dist_sq: float = INF
	var ball_pos: Vector3 = ball_ref.global_position
	for i in range(players.size()):
		if players[i].is_goalkeeper:
			continue
		var d_sq: float = _xz_dist_sq(players[i].global_position, ball_pos)
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best_index = i
	return best_index


static func _xz_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _xz_dist_sq(a: Vector3, b: Vector3) -> float:
	var dx: float = a.x - b.x
	var dz: float = a.z - b.z
	return dx * dx + dz * dz


# ---- Indicator -----------------------------------------------------------

func _build_indicators() -> void:
	_indicators.clear()
	for p in players:
		if p == null:
			_indicators.append(null)
			continue
		var ring: MeshInstance3D = MeshInstance3D.new()
		var mesh: CylinderMesh = CylinderMesh.new()
		mesh.top_radius = INDICATOR_RADIUS
		mesh.bottom_radius = INDICATOR_RADIUS
		mesh.height = INDICATOR_HEIGHT
		ring.mesh = mesh
		ring.position = Vector3(0.0, INDICATOR_Y_OFFSET, 0.0)
		ring.name = "SelectionIndicator"
		p.add_child(ring)
		_indicators.append(ring)


func _refresh_indicator_visuals() -> void:
	for i in range(_indicators.size()):
		var ring: MeshInstance3D = _indicators[i]
		if ring == null:
			continue
		# AI team — no rings at all.
		if not is_human:
			ring.visible = false
			continue
		ring.visible = true
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var alpha: float = INDICATOR_ACTIVE_ALPHA if i == active_index else INDICATOR_DIM_ALPHA
		var col: Color = team_config.primary_color if team_config != null else Color.WHITE
		col.a = alpha
		mat.albedo_color = col
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ring.material_override = mat
