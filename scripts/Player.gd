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

## S08-T04 static-AI autopilot tuning. R05-F04: `lerp_alpha = dt /
## STATIC_TARGET_LERP_TAU_S` shapes the desired-speed envelope as
## `dist / tau` so the player decelerates smoothly into the target.
## R05-F06 max_reposition_speed cap is per-instance via
## `set_static_target(pos, max_speed)`.
const STATIC_TARGET_LERP_TAU_S: float = 1.5
## Within this radius the autopilot considers the player arrived
## and feeds zero input so velocity decays via the normal accel
## ramp. 0.30 m matches the Player capsule radius (0.40) + a small
## settling margin so successive ticks don't oscillate.
const STATIC_TARGET_ARRIVE_RADIUS_M: float = 0.30

## Direction-input buffer was REMOVED in S08-T02-fix12 (2026-05-14).
## Turn-glue (BallController._apply_turn_glue) keeps the ball locked
## to the foot through any direction change, so the buffer's job
## (preventing "ball lost on turn") is no longer needed — and the
## buffer was actively causing a "drift" feel where the mesh faced
## the new direction but the body kept moving the old way until the
## next touch fired. Velocity now tracks intended input directly.
##
## Constants kept for backward-compat in case some external system
## reads them; values are inert (no longer consulted).
const DIRECTION_BUFFER_DEAD_ZONE_DEG: float = 15.0
const DIRECTION_BUFFER_MAX_S: float = 0.8

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
## Boosted rotation speed used during a `start_facing_warp` window
## (R09-F04 FIFA Animation Warping pattern: facing warps within 1-2
## physics ticks while body / animation catches up). 50 rad/s gives
## ~99 % facing convergence in ~110 ms — fast enough to feel
## responsive on a pass reception, not so fast it reads as a snap.
@export var rotation_speed_warp: float = 50.0
## Default warp duration. The warp speed only applies for this window;
## after it expires the normal `rotation_speed` resumes. 150 ms covers
## the worst-case 180° turn at the warp rate without overshooting.
@export var facing_warp_duration_s: float = 0.15

@export_group("Visual")
## Optional front marker (small BoxMesh) used in Phase 2 to make the
## capsule's facing direction readable. Auto-coloured to team primary
## colour darkened, so it stays visible against the body.
## Paths are relative to the VisualRoot node (S07-T06): both meshes
## now live under `VisualRoot/` so a single rotation on `visual_root`
## moves the body + marker together while leaving the CharacterBody3D
## (collision capsule) at identity. R09-F04 / R01-F07 visual-vs-physics
## decoupling pattern — keeps the rotationally-symmetric capsule
## untouched and isolates the future animated mesh work.
@export var front_marker_path: NodePath = ^"VisualRoot/FrontMarker"
@export var body_mesh_path: NodePath = ^"VisualRoot/BodyMesh"
## Path to the visual root node — every facing rotation writes here.
@export var visual_root_path: NodePath = ^"VisualRoot"

# ---- Runtime state -------------------------------------------------------
var state: State = State.IDLE
var stamina: float = STAMINA_FULL
var _facing_target: Vector3 = Vector3.FORWARD
var _body_mesh: MeshInstance3D
var _front_marker: MeshInstance3D
var _visual_root: Node3D
## Set true by `apply_movement_step()`; consumed (and reset) at the end of
## `_physics_process`. When false we auto-apply a zero-input drive step so
## an inactive player decelerates to a stop instead of coasting on its
## last-active velocity. (S06-D32, found during T05 Q-switch playtest.)
var _driven_this_tick: bool = false
## Mirrored by `BallController._assign_carrier` / `_clear_carrier_flag`.
## Read-only intent — do not write from outside BallController, or HUD
## state desyncs from the actual carry. Sprint 7 T02.
var has_ball: bool = false
## When > 0, `update_facing` uses `rotation_speed_warp` instead of
## `rotation_speed` (R09-F04 facing warp window — used by BallController
## on pickup). Drained by `update_facing(delta)`.
var _facing_warp_remaining_s: float = 0.0
## Direction buffer state — see DIRECTION_BUFFER_* constants.
var _committed_input_dir: Vector3 = Vector3.ZERO  ## drives velocity
var _intended_input_dir: Vector3 = Vector3.ZERO   ## latest from input (drives facing + buffer snapshot)
var _input_buffer_active: bool = false
var _input_buffer_remaining_s: float = 0.0
## True after the FIRST BallController touch fires while we hold the
## ball — buffer engages only from this point on, so the initial
## "starting from rest" input applies immediately (Q4).
var _ball_moving_with_me: bool = false
## Pickup input-lock window (S08-T02-fix13). When > 0, direction
## input is overridden — committed direction is forced toward
## `_facing_target` (= the warp direction toward the incoming ball
## set by `start_facing_warp` on pickup). Lets the receive
## animation read as a brief "settling" before the player can
## redirect. Drained inside `_resolve_committed_input`.
var _pickup_input_lock_remaining_s: float = 0.0
## True once `apply_movement_step` has run at least once. Lets
## BallController's stop-glue distinguish "carrier actively let go
## of input" from "test code set velocity directly without ever
## driving input" — only the former should snap the ball to the
## foot for the decel match.
var _intent_explicitly_set: bool = false
## S08-T04 static AI autopilot state. When `_has_static_target` is
## true and `apply_movement_step` is NOT called this tick, the
## `_physics_process` autopilot drives toward `_static_target_pos`
## using the R05-F04 / F06 lerp+cap envelope. Active-side overrides
## (PlayerController, future ball-pursuit AI) clear the target via
## `clear_static_target()` so they take precedence.
var _has_static_target: bool = false
var _static_target_pos: Vector3 = Vector3.ZERO
var _static_target_max_speed: float = 0.0  ## 0 = no cap (Player defaults)


func _ready() -> void:
	_visual_root = get_node_or_null(visual_root_path) as Node3D
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
	_intent_explicitly_set = true
	# Capture INTENDED input (planar) — drives facing immediately and
	# is the snapshot read by the buffer on the next touch.
	_intended_input_dir = Vector3(input_dir.x, 0.0, input_dir.z)
	# Resolve the COMMITTED direction the velocity should follow this
	# tick (may equal intended, or may be the buffered "old" direction).
	var commit_dir: Vector3 = _resolve_committed_input(_intended_input_dir, dt)

	# 1) stamina (S06-D04 gate: recovery happens ONLY when sprint released)
	if sprint_held and stamina > STAMINA_EMPTY:
		stamina = maxf(STAMINA_EMPTY, stamina - STAMINA_DRAIN_PER_SEC * dt)
	elif not sprint_held:
		stamina = minf(STAMINA_FULL, stamina + STAMINA_RECOVERY_PER_SEC * dt)
	# else: sprint held but stamina exhausted → frozen at 0 (no recovery)

	# 2) effective max speed (sprint Q6: immediate, never buffered)
	var sprint_active: bool = sprint_held and stamina > STAMINA_EMPTY
	var max_speed: float = max_sprint_speed if sprint_active else max_walk_speed

	# 3) target velocity from COMMITTED direction
	var planar_input: Vector3 = commit_dir
	if planar_input.length_squared() > 1.0:
		planar_input = planar_input.normalized()
	var target_velocity: Vector3 = planar_input * max_speed
	var dv: Vector3 = target_velocity - velocity
	var max_dv: float = accel * dt
	if dv.length() > max_dv:
		dv = dv.normalized() * max_dv
	velocity += dv

	# 4) facing target from INTENDED input (Q1: immediate visual feedback
	# even while velocity is buffered).
	if _intended_input_dir.length_squared() > INPUT_DEAD_ZONE_SQ:
		_facing_target = _intended_input_dir

	# 5) state — purely informational for now (HUD / TeamController)
	if velocity.length_squared() < 0.01:
		state = State.IDLE
	elif sprint_active:
		state = State.RUNNING
	else:
		state = State.RUNNING


## Direction-input buffer was REMOVED in S08-T02-fix12. This now
## always returns `intended` — velocity tracks the latest input
## directly. Two exceptions:
##   - Q8 SHOOTING/PASSING freeze (mid-animation lock).
##   - Pickup input lock window (fix13) — for the first
##     ~`facing_warp_duration_s` after pickup, committed direction
##     is forced toward `_facing_target` so the player visibly
##     "settles" with the ball before the next input redirects.
func _resolve_committed_input(intended: Vector3, dt: float) -> Vector3:
	if is_busy_with_ball_action():
		return _committed_input_dir
	if _pickup_input_lock_remaining_s > 0.0:
		_pickup_input_lock_remaining_s = maxf(0.0,
			_pickup_input_lock_remaining_s - dt)
		var locked: Vector3 = _facing_target
		if locked.length_squared() > INPUT_DEAD_ZONE_SQ:
			_committed_input_dir = locked
			_input_buffer_active = false
			_input_buffer_remaining_s = 0.0
			return locked
	_committed_input_dir = intended
	_input_buffer_active = false
	_input_buffer_remaining_s = 0.0
	return intended


static func _within_buffer_dead_zone(a: Vector3, b: Vector3) -> bool:
	var a_zero: bool = a.length_squared() < 1.0e-4
	var b_zero: bool = b.length_squared() < 1.0e-4
	if a_zero and b_zero:
		return true
	if a_zero != b_zero:
		return false  ## ZERO ↔ non-ZERO = significant change (Q5: stop is buffered)
	var dot: float = a.normalized().dot(b.normalized())
	var cos_threshold: float = cos(deg_to_rad(DIRECTION_BUFFER_DEAD_ZONE_DEG))
	return dot >= cos_threshold


## Called by BallController each time a proximity-kick fires while
## this player is the carrier. Q3: snapshot intended at touch instant
## → committed; clears buffer; marks ball-moving-with-me.
func on_dribble_touch() -> void:
	_committed_input_dir = _intended_input_dir
	_input_buffer_active = false
	_input_buffer_remaining_s = 0.0
	_ball_moving_with_me = true


## Called by BallController on possession loss. Q7: flush buffer
## immediately — full input control restored.
func on_possession_lost() -> void:
	_committed_input_dir = _intended_input_dir
	_input_buffer_active = false
	_input_buffer_remaining_s = 0.0
	_ball_moving_with_me = false


## S08-T04 — assign a world-space target position the player should
## steer toward when no human / AI controller is driving them this
## tick. `max_speed` (R05-F06) caps the velocity so a far-away
## target doesn't read as a teleport; pass 0.0 for no cap (uses
## the Player walk/sprint defaults). Idempotent — overwrites prior
## target. Cleared by `clear_static_target()` or by the carrier
## flag flipping (BallController takes priority).
func set_static_target(pos: Vector3, max_speed: float = 0.0) -> void:
	_has_static_target = true
	_static_target_pos = Vector3(pos.x, 0.0, pos.z)
	_static_target_max_speed = maxf(0.0, max_speed)


## Stop steering to the static target — the next non-driven tick
## will fall back to zero-input decel. Used by the active-side
## controllers when they take over.
func clear_static_target() -> void:
	_has_static_target = false


## Public read of the latest intended input direction (planar, NOT
## normalized). ZERO = "stop intent" — but only meaningful when
## `is_stop_intent_active()` confirms the intent was explicitly
## driven (vs. uninitialized test fixtures).
func get_intended_input_dir() -> Vector3:
	return Vector3(_intended_input_dir.x, 0.0, _intended_input_dir.z)


## True when the carrier has explicitly released input (stick / keys
## centered). Used by BallController's stop-glue so the ball locks
## to the foot ONLY during a real "I want to stop" deceleration,
## not when test code sets `velocity` directly without ever calling
## `apply_movement_step`.
func is_stop_intent_active() -> bool:
	if not _intent_explicitly_set:
		return false
	return _intended_input_dir.length_squared() < 1.0e-4


## Arm a pickup input-lock window. While the lock drains, direction
## input is overridden — committed direction follows `_facing_target`
## (which BallController sets toward the incoming ball via
## `start_facing_warp`). Defaults to `facing_warp_duration_s` so the
## input lock and the visual warp end together.
func start_pickup_input_lock(duration_s: float = -1.0) -> void:
	if duration_s < 0.0:
		duration_s = facing_warp_duration_s
	_pickup_input_lock_remaining_s = maxf(_pickup_input_lock_remaining_s,
		duration_s)


## Read-only snapshot of the buffer state for BallController. Returns
## { active: bool, intent: Vector3 } — `intent` is the planar
## _intended_input_dir (NOT normalized; ZERO = stop intent). Used by
## the proximity kick to decide PIVOT (turn) vs TRAP (stop) on touch.
func get_buffer_state() -> Dictionary:
	return {
		"active": _input_buffer_active,
		"intent": Vector3(_intended_input_dir.x, 0.0, _intended_input_dir.z),
	}


## Force-redirect velocity to a new planar direction, preserving the
## current planar speed and Y component. Called by BallController on a
## buffered-turn touch so the body pivots in lockstep with the ball
## kick — without this, the player keeps drifting in the OLD direction
## (committed) while the ball flies in the NEW direction (intended) and
## possession is lost on every sharp turn.
func snap_velocity_direction(planar_dir: Vector3) -> void:
	var d: Vector3 = Vector3(planar_dir.x, 0.0, planar_dir.z)
	if d.length_squared() < INPUT_DEAD_ZONE_SQ:
		return
	d = d.normalized()
	var planar_speed: float = sqrt(velocity.x * velocity.x + velocity.z * velocity.z)
	velocity = Vector3(d.x * planar_speed, velocity.y, d.z * planar_speed)


## Frame-rate-independent rotation of the visual basis toward `_facing_target`.
## Called from `_physics_process` and exposed for tests / Sprint 7 facing snap.
## When `_facing_warp_remaining_s > 0`, the boosted `rotation_speed_warp`
## replaces the baseline rate (R09-F04 FIFA Animation Warping window —
## used by BallController on pickup so the receiver smoothly turns
## TOWARD the incoming ball over ~100-150 ms instead of either slerping
## for ~400 ms or snapping in one tick).
func update_facing(dt: float) -> void:
	if _facing_target.length_squared() < INPUT_DEAD_ZONE_SQ:
		return
	if _visual_root == null:
		return  ## scene set up without VisualRoot — nothing to rotate
	var rate: float = rotation_speed
	if _facing_warp_remaining_s > 0.0:
		rate = rotation_speed_warp
		_facing_warp_remaining_s = maxf(0.0, _facing_warp_remaining_s - dt)
	# Basis.looking_at: -Z (model forward) points at the target direction.
	# Capsule is symmetric on Y, but the front marker mesh exposes the
	# direction so the player isn't visually a featureless pill.
	# Rotate the VisualRoot ONLY — the CharacterBody3D collision capsule
	# stays at identity (R09-F04 / R01-F07 visual-vs-physics decoupling).
	var target_basis: Basis = Basis.looking_at(_facing_target, Vector3.UP)
	# alpha = 1 - 0.5^(rate * dt). Frame-rate independent — same response
	# at 30/60/120 fps. Baseline 20: 99 % in ~160 ms. Warp 50: 99 % in ~110 ms.
	var alpha: float = 1.0 - pow(0.5, rate * dt)
	_visual_root.transform.basis = _visual_root.transform.basis.slerp(target_basis, alpha)


## True iff the player is currently in an animation state that should block
## auto-switch (TeamController consults this — see S06 spec A2).
func is_busy_with_ball_action() -> bool:
	return state == State.SHOOTING or state == State.PASSING


## Visual basis (VisualRoot.transform.basis) — the basis everything ball-
## interaction-related reads: pass cones, shot direction, carry offset.
## Falls back to the player's own basis if VisualRoot wasn't found, so
## scenes that haven't migrated to T06 still work.
func get_visual_basis() -> Basis:
	if _visual_root != null:
		return _visual_root.transform.basis
	return transform.basis


## Visual forward direction (= -visual_basis.z, planar). Convenience for
## consumers that only need a direction vector.
func get_visual_forward() -> Vector3:
	var b: Basis = get_visual_basis()
	var f: Vector3 = -b.z
	f.y = 0.0
	if f.length_squared() < 1.0e-6:
		return Vector3.FORWARD
	return f.normalized()


## Snap the visual facing AND the rotation target to a direction now —
## bypasses the slerp from `update_facing`. Reserved for cases that
## REALLY need a hard snap (Sprint 6 Q-switch, debug teleports). For
## reception-style "turn toward the ball" prefer `start_facing_warp`
## which is smooth (R09-F04). Direction is XZ-only; Y is dropped.
## No-op on near-zero input.
func set_facing_immediate(direction: Vector3) -> void:
	var planar: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if planar.length_squared() < INPUT_DEAD_ZONE_SQ:
		return
	planar = planar.normalized()
	_facing_target = planar
	if _visual_root != null:
		_visual_root.transform.basis = Basis.looking_at(planar, Vector3.UP)


## Turn toward `direction` over a brief warp window — uses the boosted
## `rotation_speed_warp` for `duration_s` seconds, then resumes the
## baseline `rotation_speed`. R09-F04 FIFA Animation Warping pattern:
## "rotate the mesh facing toward input within 1-2 physics ticks while
## the body / animation catches up." Smoother than `set_facing_immediate`
## (no scatto) but much faster than baseline slerp. Used by
## BallController when a player picks up an incoming pass.
##   duration_s defaults to `facing_warp_duration_s` (0.15 s).
func start_facing_warp(direction: Vector3, duration_s: float = -1.0) -> void:
	var planar: Vector3 = Vector3(direction.x, 0.0, direction.z)
	if planar.length_squared() < INPUT_DEAD_ZONE_SQ:
		return
	planar = planar.normalized()
	_facing_target = planar
	if duration_s < 0.0:
		duration_s = facing_warp_duration_s
	# Always extend (max), never shorten — overlapping warps just keep
	# the longer window so chained passes don't fall back to slow slerp.
	_facing_warp_remaining_s = maxf(_facing_warp_remaining_s, duration_s)


# ---- Lifecycle ----------------------------------------------------------

func _physics_process(delta: float) -> void:
	# If no controller drove us this tick:
	#   - has a static-AI target → steer toward it (R05 autopilot)
	#   - otherwise → zero-input decel so the player coasts to a stop.
	# Active controllers (PlayerController, future ball-pursuit AI)
	# call `apply_movement_step` directly, which sets _driven_this_tick
	# and bypasses both branches.
	if not _driven_this_tick:
		if _has_static_target:
			_drive_toward_static_target(delta)
		else:
			apply_movement_step(Vector3.ZERO, false, delta)
	update_facing(delta)
	move_and_slide()
	_driven_this_tick = false


## Static-AI autopilot driver (R05-F04 lerp envelope + R05-F06 cap).
## Computes a desired planar speed = `dist / STATIC_TARGET_LERP_TAU_S`
## clamped to `_static_target_max_speed`, then feeds an equivalent
## scaled input vector (and sprint flag when the desired speed
## exceeds walk) into `apply_movement_step` so all the existing
## stamina / accel / facing logic stays in one path.
func _drive_toward_static_target(dt: float) -> void:
	var to: Vector3 = _static_target_pos - global_position
	to.y = 0.0
	var dist: float = to.length()
	if dist < STATIC_TARGET_ARRIVE_RADIUS_M:
		apply_movement_step(Vector3.ZERO, false, dt)
		return
	var dir: Vector3 = to / dist
	# R05-F04: desired speed envelope smoothly decelerates as the
	# player approaches the target — at 7.5 m the speed request is
	# 5 m/s, at 1.5 m it's 1 m/s. Combined with Player.accel this
	# gives a settled arrival without overshoot.
	var desired_speed: float = dist / STATIC_TARGET_LERP_TAU_S
	# R05-F06: per-role velocity cap prevents teleport-feel on
	# large repositions (e.g. half-change transitions).
	if _static_target_max_speed > 0.0:
		desired_speed = minf(desired_speed, _static_target_max_speed)
	var sprint: bool = desired_speed > max_walk_speed
	var max_at_speed: float = max_sprint_speed if sprint else max_walk_speed
	var input_mag: float = clampf(desired_speed / max_at_speed, 0.0, 1.0)
	apply_movement_step(dir * input_mag, sprint, dt)


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
