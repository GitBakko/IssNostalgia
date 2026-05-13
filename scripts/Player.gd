class_name Player
extends CharacterBody3D

## Single player entity. Sprint 6: movement + sprint + stamina + facing.
## State machine and ball-interaction states placeholder for Sprint 7+.
##
## Driven by `PlayerController` (human) or `StaticAI` (Sprint 8 opponent).
## All movement intent enters via `apply_movement_step()` — a pure-ish call
## that updates `velocity`, `stamina` and `_facing_target` deterministically
## given an explicit `dt`. `_physics_process` only commits the result via
## `move_and_slide()` and rotates the visual basis toward the facing target.
##
## Locked params from S06-D04, S06-D21, S06-D22; rotation pattern from
## RESEARCH_INDEX R01-F04 + R06-F06 (frame-rate-independent slerp).

# ---- States --------------------------------------------------------------
enum State {
	IDLE,
	RUNNING,
	TURNING,
	# Sprint 7+ placeholders — wired here so the auto-switch guard in
	# TeamController can read them safely without checking for `null`.
	SHOOTING,
	PASSING,
}

# ---- Tunables ------------------------------------------------------------
const STAMINA_FULL: float = 1.0
const STAMINA_EMPTY: float = 0.0
## 1.0 / 3.0 — full stamina lasts 3 s of continuous sprint.
const STAMINA_DRAIN_PER_SEC: float = 1.0 / 3.0
## 1.0 / 5.0 — empty stamina recovers in 5 s while NOT sprinting (S06-D04).
const STAMINA_RECOVERY_PER_SEC: float = 1.0 / 5.0
## Smallest squared input magnitude treated as "movement intent".
const INPUT_DEAD_ZONE_SQ: float = 1.0e-4

# ---- Exports -------------------------------------------------------------
@export var team_config: TeamConfig
@export var role_index: int = 0
@export var is_goalkeeper: bool = false

@export_group("Movement")
@export var max_walk_speed: float = 5.5      ## m/s, walking baseline
@export var max_sprint_speed: float = 8.0    ## m/s, sprint with stamina > 0
## m/s² — single-phase acceleration. Two-phase ramp (R01-F06) deferred to
## Sprint 9 polish backlog.
@export var accel: float = 20.0
## Rotation speed scalar for FR-independent slerp. Matches R01-F04 typical
## range (5-10). At dt=1/120 with rotation_speed=8 the alpha per tick is
## `1 - 0.5^(8/120) ≈ 0.045`.
@export var rotation_speed: float = 8.0

@export_group("Visual")
## Optional front marker (small BoxMesh) used in Phase 2 to make the
## capsule's facing direction readable. Auto-coloured to team primary
## colour darkened, so it stays visible against the body.
@export var front_marker_path: NodePath = ^"FrontMarker"
@export var body_mesh_path: NodePath = ^"BodyMesh"

# ---- Runtime state -------------------------------------------------------
var state: State = State.IDLE
var stamina: float = STAMINA_FULL
var _facing_target: Vector3 = Vector3.FORWARD
var _body_mesh: MeshInstance3D
var _front_marker: MeshInstance3D
## Set true by `apply_movement_step()`; consumed (and reset) at the end of
## `_physics_process`. When false we auto-apply a zero-input drive step so
## an inactive player decelerates to a stop instead of coasting on its
## last-active velocity. (S06-D32, found during T05 Q-switch playtest.)
var _driven_this_tick: bool = false
## Mirrored by `BallController._assign_carrier` / `_clear_carrier_flag`.
## Read-only intent — do not write from outside BallController, or HUD
## state desyncs from the actual carry. Sprint 7 T02.
var has_ball: bool = false


func _ready() -> void:
	_body_mesh = get_node_or_null(body_mesh_path) as MeshInstance3D
	_front_marker = get_node_or_null(front_marker_path) as MeshInstance3D
	_apply_team_colour()
	# Initialise facing along -Z so a freshly spawned player looks "into the
	# pitch" by default. PlayerController / StaticAI override on first input.
	_facing_target = -global_transform.basis.z


# ---- Public API ----------------------------------------------------------

## Pure-on-instance step. Updates `velocity`, `stamina` and the facing
## target from an input direction (XZ-plane vector, magnitude ≤ 1) and a
## sprint flag. Tests drive this directly with explicit `dt` — no scene
## tick coupling.
func apply_movement_step(input_dir: Vector3, sprint_held: bool, dt: float) -> void:
	_driven_this_tick = true
	# 1) stamina (S06-D04 gate: recovery happens ONLY when sprint released)
	if sprint_held and stamina > STAMINA_EMPTY:
		stamina = maxf(STAMINA_EMPTY, stamina - STAMINA_DRAIN_PER_SEC * dt)
	elif not sprint_held:
		stamina = minf(STAMINA_FULL, stamina + STAMINA_RECOVERY_PER_SEC * dt)
	# else: sprint held but stamina exhausted → frozen at 0 (no recovery)

	# 2) effective max speed
	var sprint_active: bool = sprint_held and stamina > STAMINA_EMPTY
	var max_speed: float = max_sprint_speed if sprint_active else max_walk_speed

	# 3) target velocity from input, cap accel per tick
	var planar_input: Vector3 = Vector3(input_dir.x, 0.0, input_dir.z)
	if planar_input.length_squared() > 1.0:
		planar_input = planar_input.normalized()
	var target_velocity: Vector3 = planar_input * max_speed
	var dv: Vector3 = target_velocity - velocity
	var max_dv: float = accel * dt
	if dv.length() > max_dv:
		dv = dv.normalized() * max_dv
	velocity += dv

	# 4) facing target from movement input (rotates only when there's intent)
	if planar_input.length_squared() > INPUT_DEAD_ZONE_SQ:
		_facing_target = planar_input

	# 5) state — purely informational for now (HUD / TeamController)
	if velocity.length_squared() < 0.01:
		state = State.IDLE
	elif sprint_active:
		state = State.RUNNING
	else:
		state = State.RUNNING


## Frame-rate-independent rotation of the visual basis toward `_facing_target`.
## Called from `_physics_process` and exposed for tests / Sprint 7 facing snap.
func update_facing(dt: float) -> void:
	if _facing_target.length_squared() < INPUT_DEAD_ZONE_SQ:
		return
	# Basis.looking_at: -Z (model forward) points at the target direction.
	# Capsule is symmetric on Y, but the front marker mesh exposes the
	# direction so the player isn't visually a featureless pill.
	var target_basis: Basis = Basis.looking_at(_facing_target, Vector3.UP)
	# alpha = 1 - 0.5^(rotation_speed * dt). At rotation_speed=8 and dt=1/120
	# alpha ≈ 0.045 per tick, so 99 % of the rotation completes in ~50 ticks
	# (~0.4 s). Frame-rate independent — same response at 30/60/120 fps.
	var alpha: float = 1.0 - pow(0.5, rotation_speed * dt)
	transform.basis = transform.basis.slerp(target_basis, alpha)


## True iff the player is currently in an animation state that should block
## auto-switch (TeamController consults this — see S06 spec A2).
func is_busy_with_ball_action() -> bool:
	return state == State.SHOOTING or state == State.PASSING


## Snap the visual facing AND the rotation target to a direction now —
## bypasses the slerp from `update_facing`. Used by BallController when
## a player receives a pass: the carry offset is in the player's local
## forward, so without this snap the ball would visually attach behind
## or to the side of the receiver depending on their stale facing.
## Direction is XZ-only; Y is dropped. No-op on near-zero input.
func set_facing_immediate(direction: Vector3) -> void:
	var planar: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if planar.length_squared() < INPUT_DEAD_ZONE_SQ:
		return
	planar = planar.normalized()
	_facing_target = planar
	transform.basis = Basis.looking_at(planar, Vector3.UP)


# ---- Lifecycle ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	# If no controller drove us this tick (we're inactive — TeamController
	# pointed elsewhere, or StaticAI hasn't woken up yet), apply a
	# zero-input step so velocity decays naturally toward 0 instead of
	# coasting forever. Active players are driven by their PlayerController
	# AFTER this — but the controller's call sets _driven_this_tick = true
	# next tick, so the active player skips this branch from then on.
	if not _driven_this_tick:
		apply_movement_step(Vector3.ZERO, false, delta)
	update_facing(delta)
	move_and_slide()
	_driven_this_tick = false


# ---- Internal -----------------------------------------------------------

func _apply_team_colour() -> void:
	if team_config == null:
		return
	if _body_mesh != null:
		var mat: StandardMaterial3D = StandardMaterial3D.new()
		mat.albedo_color = team_config.primary_color
		mat.roughness = 0.55
		_body_mesh.material_override = mat
	if _front_marker != null:
		var nose_mat: StandardMaterial3D = StandardMaterial3D.new()
		nose_mat.albedo_color = team_config.primary_color.lightened(0.55)
		nose_mat.metallic = 0.0
		_front_marker.material_override = nose_mat
