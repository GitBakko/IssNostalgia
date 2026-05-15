class_name Goalkeeper
extends Node

## Sprint 8 T05 — arcade goalkeeper controller (Phase 2 spec).
## Implements the R04 cluster: F01 reachability gate, F02 commit-
## early teleport, F04 1-axis intercept formula, F05 angle-bisect
## idle position, F06 give-up gate. F03 (controlled-hesitation
## reaction delay) deferred to Phase 3 — Phase 2 teleport is an
## intentional visible cheat per the plan.
##
## Controller, NOT a subclass of Player — keeps the GK movement
## logic isolated so Player stays generic. Three behaviours per
## tick:
##   IDLE   — ball not heading toward our goal OR gives up:
##            lerp x toward `gk_idle_target_x = ball_x * 0.5`.
##   SAVE   — ball heading toward our goal, predicted within posts
##            and below crossbar, and reachable by walking only:
##            move toward intercept_x at gk_speed.
##   SNAP   — same SAVE conditions BUT not reachable by walking
##            within `t_flight - reaction_buffer_s`: teleport the
##            GK to the intercept_x and play the SAVING anim flag.
##
## Tactical cadence runs at the physics tick (120 Hz) — GK saves
## are time-critical, the 2 Hz tactical layer of StaticAI is not
## appropriate here.

# ---- Exports -------------------------------------------------------------
@export var goalkeeper: Player
@export var ball: BallPhysics
## Own goal line (own goal Z coordinate). Team A defends -52.5,
## Team B defends +52.5. Sign also drives the "ball heading toward
## us" check: own goal_z < 0 → save when ball.linear_velocity.z < 0.
@export var goal_z: float = -52.5
## Half-width of the goal mouth (post inner X). Default 3.2 m
## matches the Sprint 8 GameMatch.tscn post placement.
@export var goal_half_width_m: float = 3.2
## Crossbar height — predicted ball Y above this at crossing → give
## up (un-savable lob).
@export var crossbar_height_m: float = 2.44
## How far in front of the goal line the GK idles (positive number;
## sign is applied internally relative to `goal_z`).
@export var idle_forward_offset_m: float = 1.0
## GK lateral / forward speed cap, m/s. R04 Phase 2 spec value.
@export var gk_speed: float = 6.0
## Idle lerp factor per tick — exponential pull toward the idle
## target. 0.15 → ~99 % closure in 30 ticks at 120 Hz.
@export var idle_lerp: float = 0.15
## Reaction buffer (R04-F01 t_buf). Time subtracted from t_flight
## before comparing to the GK movement budget.
@export var reaction_buffer_s: float = 0.05
## Catch radius — extends GK reach by this amount on the X axis
## (R04-F01 d_eff = max(0, d_lat - r)) AND defines the actual
## catch zone: when the ball is within this XZ distance of the GK
## centre, the ball is intercepted (velocity zeroed, position
## snapped to the GK chest). Necessary because BallPhysics runs
## with custom_integrator = true and only resolves ground / wall
## contacts — without this gate the ball phases through the GK.
@export var catch_radius_m: float = 0.7
## Vertical catch height — ball Y above this (e.g. ball flying
## over the keeper) is NOT caught. Matches the GK arms-up reach.
@export var catch_max_height_m: float = 2.20
## Held-ball Y after a catch — ball sits at chest height, not at
## the foot or floating above the head. Safe-launch from here
## restores possession naturally on the next pickup tick.
@export var catch_hold_height_m: float = 0.90
## Min ball speed toward goal (Z component magnitude) to consider
## the shot a "save scenario". Below this the ball is loose / pass
## and the GK stays in idle mode.
@export var save_min_ball_speed_z_m_s: float = 4.0
## Gravity used in the predicted-height calc. Matches project gravity.
@export var gravity_m_s2: float = 9.81

# ---- Runtime state -------------------------------------------------------
var _last_decision: StringName = &"idle"


func _physics_process(delta: float) -> void:
	step(delta)


## Pure-on-instance step. Tests drive this directly.
func step(delta: float) -> void:
	if goalkeeper == null or ball == null:
		return
	if not is_instance_valid(goalkeeper) or not is_instance_valid(ball):
		return
	var ball_pos: Vector3 = ball.global_position
	var ball_v: Vector3 = ball.linear_velocity
	var save_data: Dictionary = compute_save_decision(ball_pos, ball_v)
	_last_decision = save_data.get("decision", &"idle")
	match _last_decision:
		&"snap":
			_perform_snap(save_data.intercept_x)
		&"save":
			_perform_save(save_data.intercept_x, delta)
		_:
			_perform_idle(ball_pos, delta)
	# Catch gate runs every tick AFTER positioning. The ball would
	# otherwise phase through the GK capsule (BallPhysics custom
	# integrator only resolves ground / wall contacts). Catch only
	# fires while we're not already the carrier — avoids re-triggering
	# every tick while holding the ball.
	_try_catch()


## Pure decision function. Returns a dict with:
##   decision: &"idle" | &"save" | &"snap"
##   t_flight: float
##   intercept_x: float (NaN when not applicable)
##   predicted_height: float
## Public so tests can assert the decision branch on canonical inputs.
func compute_save_decision(ball_pos: Vector3, ball_v: Vector3) -> Dictionary:
	var dz: float = goal_z - ball_pos.z
	var heading_toward_goal: bool = (signf(dz) == signf(ball_v.z)) \
		and absf(ball_v.z) > save_min_ball_speed_z_m_s
	if not heading_toward_goal:
		return {"decision": &"idle", "t_flight": 0.0,
			"intercept_x": NAN, "predicted_height": 0.0}
	var t_flight: float = dz / ball_v.z  ## same sign → positive
	if t_flight <= 0.0:
		return {"decision": &"idle", "t_flight": 0.0,
			"intercept_x": NAN, "predicted_height": 0.0}
	# R04-F04 — 1-axis intercept. Phase 2 ignores drag (acceptable
	# error for <1 s flights at typical shot speeds; F04 calls out
	# kinematic prediction as sufficient).
	var intercept_x: float = ball_pos.x + ball_v.x * t_flight
	# Predicted height at crossing (under gravity, no drag).
	var predicted_height: float = ball_pos.y + ball_v.y * t_flight \
		- 0.5 * gravity_m_s2 * t_flight * t_flight
	# R04-F06 — give-up gates.
	if absf(intercept_x) > goal_half_width_m:
		return {"decision": &"idle", "t_flight": t_flight,
			"intercept_x": intercept_x, "predicted_height": predicted_height}
	if predicted_height > crossbar_height_m:
		return {"decision": &"idle", "t_flight": t_flight,
			"intercept_x": intercept_x, "predicted_height": predicted_height}
	# R04-F01 — reachability gate.
	var d_lat: float = absf(intercept_x - goalkeeper.global_position.x)
	var d_eff: float = maxf(0.0, d_lat - catch_radius_m)
	var t_av: float = maxf(0.0, t_flight - reaction_buffer_s)
	var move_time_required: float = d_eff / gk_speed if gk_speed > 0.0 else INF
	if move_time_required > t_av:
		# R04-F02 — cannot reach by walking inside the response budget;
		# teleport to intercept_x (visible cheat, intentional).
		return {"decision": &"snap", "t_flight": t_flight,
			"intercept_x": intercept_x, "predicted_height": predicted_height}
	# Reachable by movement — steer toward the intercept.
	return {"decision": &"save", "t_flight": t_flight,
		"intercept_x": intercept_x, "predicted_height": predicted_height}


# ---- Decision executors -------------------------------------------------

## R04-F05 — angle-bisect idle. Tracks ball X at half magnitude so
## near-post is never exposed; clamps to the goal mouth.
func _perform_idle(ball_pos: Vector3, dt: float) -> void:
	goalkeeper.state = Player.State.IDLE
	goalkeeper.clear_static_target()
	var idle_x: float = clampf(ball_pos.x * 0.5,
		-goal_half_width_m, goal_half_width_m)
	var current: Vector3 = goalkeeper.global_position
	var target_x: float = lerpf(current.x, idle_x, idle_lerp)
	var target_z: float = goal_z + signf(-goal_z) * idle_forward_offset_m
	goalkeeper.global_position = Vector3(target_x, current.y, target_z)
	goalkeeper.velocity = Vector3.ZERO
	# Mark as driven so Player._physics_process doesn't re-apply the
	# zero-input decel path.
	goalkeeper.mark_driven()


func _perform_save(intercept_x: float, dt: float) -> void:
	goalkeeper.state = Player.State.SAVING
	goalkeeper.clear_static_target()
	var current: Vector3 = goalkeeper.global_position
	var target_z: float = goal_z + signf(-goal_z) * idle_forward_offset_m
	var dx: float = intercept_x - current.x
	var max_step: float = gk_speed * dt
	var step_x: float = clampf(dx, -max_step, max_step)
	goalkeeper.global_position = Vector3(current.x + step_x, current.y, target_z)
	goalkeeper.velocity = Vector3.ZERO
	goalkeeper.mark_driven()


func _perform_snap(intercept_x: float) -> void:
	goalkeeper.state = Player.State.SAVING
	goalkeeper.clear_static_target()
	var current: Vector3 = goalkeeper.global_position
	var target_z: float = goal_z + signf(-goal_z) * idle_forward_offset_m
	goalkeeper.global_position = Vector3(intercept_x, current.y, target_z)
	goalkeeper.velocity = Vector3.ZERO


## Read-only accessor for tests / HUD.
func get_last_decision() -> StringName:
	return _last_decision


## Explicit catch resolution — needed because BallPhysics runs with
## custom_integrator and skips dynamic-body contact response. When
## the ball is inside `catch_radius_m` (XZ) AND below
## `catch_max_height_m`, snap it to the GK chest and zero velocity.
## Skipped while the GK is already the ball carrier (avoids
## re-trigger every tick).
func _try_catch() -> void:
	if ball == null or goalkeeper == null:
		return
	if ball.get_possessor() == goalkeeper:
		return
	var bp: Vector3 = ball.global_position
	var gp: Vector3 = goalkeeper.global_position
	if bp.y > catch_max_height_m:
		return
	var dx: float = bp.x - gp.x
	var dz: float = bp.z - gp.z
	if dx * dx + dz * dz > catch_radius_m * catch_radius_m:
		return
	# Stop the ball at the GK chest. BallController's pickup scan
	# will then naturally reassign possession to the GK on the next
	# tick (the ball is now inside the pickup radius and below the
	# pickup speed gate).
	ball.apply_launch_state(Vector3.ZERO, Vector3.ZERO)
	ball.teleport_to(Vector3(gp.x, catch_hold_height_m, gp.z))
	_last_decision = &"catch"
