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
## Used by SAVE branch (steer toward intercept_x at full pace).
@export var gk_speed: float = 6.0
## Slow re-positioning speed (m/s) used by the IDLE branch — the
## "settling back" walk after a catch or while tracking a sideways
## ball. Much lower than `gk_speed` so the keeper doesn't slingshot
## back to centre after a save (playtest 2026-05-15).
@export var idle_max_speed_m_s: float = 2.0
## Hold window (s) after a catch — GK freezes in place to "hold
## the ball" before resuming the idle drift. Reads as a natural
## beat instead of an instant snap toward centre.
@export var post_catch_hold_s: float = 0.6
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
## the ball "in motion" at all. Anything below this is loose ball
## settling — no save scenario. Set low (0.5) so even slow shots
## near goal are considered for the save path; the shot zone gate
## below filters out distant passes.
@export var save_min_ball_speed_z_m_s: float = 0.5
## Distance gate (m, along Z) within which a ball heading toward
## our goal is treated as a shot. Beyond this it's a midfield pass /
## clearance — GK stays idle. 25 m covers the attacking third
## (penalty area + a margin) without reacting to halfway-line shots
## that any drag/save would beat. Playtest 2026-05-15 — was missing,
## causing slow shots to fall under the save_min gate and slip past.
@export var shot_zone_m: float = 25.0
## Gravity used in the predicted-height calc. Matches project gravity.
@export var gravity_m_s2: float = 9.81

@export_group("DEBUG — auto-return ball to last shooter (TEMP playtest)")
## TEMP playtest aid 2026-05-15. After a catch + post_catch_hold_s,
## the GK kicks the ball back toward the player who last called
## `BallController.request_release` (i.e. the shooter). Lets a
## solo human iterate "shoot → save → return → shoot" without
## having to walk to the ball each time.
@export var debug_return_ball_enabled: bool = true
## Extra delay AFTER `post_catch_hold_s` before the auto-return
## fires. Total time from catch to kick = post_catch_hold_s +
## debug_return_delay_s.
@export var debug_return_delay_s: float = 1.0
## Planar speed (m/s) of the auto-return pass.
@export var debug_return_pass_speed_m_s: float = 14.0
## Vertical kick component (m/s) — slight arc so the pass clears
## the ground roughness and reads as a real kick.
@export var debug_return_pass_lift_m_s: float = 1.5
## BallController ref — needed to read the last shooter and stay
## aware of possession state. Wired by GameMatch after the
## controller is instantiated.
@export var ball_controller: BallController

@export_group("NBA Jam catch-up boost (R09-F02 — schema only)")
## T06 schema only — eligibility wiring requires the scoreboard
## (Sprint 9). When `false` (default) all catch-up modifiers are
## inert; `get_effective_reaction_buffer_s()` returns the raw
## `reaction_buffer_s` regardless of score state.
@export var catchup_boost_enabled: bool = false
## Trailing goal margin that arms the boost (R09-F02).
@export var trailing_goal_threshold: int = 2
## Match time-remaining window (s) the boost is active in (R09-F02).
@export var time_remaining_threshold_s: float = 60.0
## Shot-accuracy multiplier added to the trailing team's shooter
## (R09-F02). Schema only — applied in Sprint 9 by ShootingController.
@export var catchup_accuracy_boost: float = 0.125
## GK reaction-buffer multiplier when the GK's team is LEADING
## (i.e. the trailing AI shoots → the leading GK gets a slower
## reaction). 0.85 = 15 % faster reaction → smaller t_av buffer →
## SNAP fires earlier and the comeback team scores more easily.
@export var catchup_gk_reaction_factor: float = 0.85

# ---- Runtime state -------------------------------------------------------
var _last_decision: StringName = &"idle"
var _post_catch_hold_remaining_s: float = 0.0
var _debug_return_remaining_s: float = 0.0
var _debug_return_target: Player = null
## True while the GK is "holding" the ball (between catch and
## release). Ball is actively pinned to the chest each tick so
## gravity / drag don't drop it.
var _holding_ball: bool = false
## Brief lockout AFTER a release so `_try_catch` doesn't immediately
## re-grab the just-launched ball (it's still at the GK position
## the same tick the launch fires — gravity hasn't moved it yet).
var _post_release_lockout_s: float = 0.0


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
	# Runtime: drag-aware prediction (kinematic over-predicts on
	# diagonals — playtest 2026-05-15). Falls back to kinematic when
	# `ball.predict_forward` is unavailable. Tests can still call
	# `compute_save_decision` directly for the deterministic
	# kinematic path.
	var save_data: Dictionary = _predict_intercept_drag_aware(ball_pos, ball_v)
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
	if _post_release_lockout_s > 0.0:
		_post_release_lockout_s = maxf(0.0,
			_post_release_lockout_s - delta)
	_try_catch()
	_pin_held_ball()
	_drain_debug_return(delta)


## Pure decision function. Returns a dict with:
##   decision: &"idle" | &"save" | &"snap"
##   t_flight: float
##   intercept_x: float (NaN when not applicable)
##   predicted_height: float
## Public so tests can assert the decision branch on canonical inputs.
## Uses pure kinematic prediction; `step()` overrides with the drag-
## aware path via `_predict_intercept_drag_aware` so diagonals don't
## get falsely rejected by the give-up gate.
func compute_save_decision(ball_pos: Vector3, ball_v: Vector3) -> Dictionary:
	var pre: Dictionary = _kinematic_intercept(ball_pos, ball_v)
	if pre.decision != &"_proceed":
		return pre
	return _apply_decision_gates(pre.t_flight, pre.intercept_x,
		pre.predicted_height)


## Internal — pure kinematic intercept prediction (no drag). Returns
## either an early-out decision dict (idle when not heading at goal,
## outside shot zone, or t_flight <= 0) OR a "_proceed" stub dict
## with `t_flight`, `intercept_x`, `predicted_height` for the gates.
func _kinematic_intercept(ball_pos: Vector3, ball_v: Vector3) -> Dictionary:
	var dz: float = goal_z - ball_pos.z
	var heading_toward_goal: bool = (signf(dz) == signf(ball_v.z)) \
		and absf(ball_v.z) > save_min_ball_speed_z_m_s
	if not heading_toward_goal:
		return {"decision": &"idle", "t_flight": 0.0,
			"intercept_x": NAN, "predicted_height": 0.0}
	if absf(dz) > shot_zone_m:
		return {"decision": &"idle", "t_flight": 0.0,
			"intercept_x": NAN, "predicted_height": 0.0}
	var t_flight: float = dz / ball_v.z
	if t_flight <= 0.0:
		return {"decision": &"idle", "t_flight": 0.0,
			"intercept_x": NAN, "predicted_height": 0.0}
	var intercept_x: float = ball_pos.x + ball_v.x * t_flight
	var predicted_height: float = ball_pos.y + ball_v.y * t_flight \
		- 0.5 * gravity_m_s2 * t_flight * t_flight
	return {"decision": &"_proceed", "t_flight": t_flight,
		"intercept_x": intercept_x, "predicted_height": predicted_height}


## Internal — apply give-up + reachability gates to a precomputed
## (t_flight, intercept_x, predicted_height) triple. Same code path
## for kinematic and drag-aware predictions.
func _apply_decision_gates(t_flight: float, intercept_x: float,
		predicted_height: float) -> Dictionary:
	# R04-F06 — give-up gates. Save zone is the goal mouth EXTENDED
	# by `catch_radius_m`: the keeper can dive that far past the
	# post and still snag the ball with their fingertips. Without
	# this margin, kinematic over-prediction on diagonals (no drag
	# accounted for) falsely landed intercept_x just outside the
	# post and the GK gave up — playtest 2026-05-15.
	var save_zone_x: float = goal_half_width_m + catch_radius_m
	if absf(intercept_x) > save_zone_x:
		return {"decision": &"idle", "t_flight": t_flight,
			"intercept_x": intercept_x, "predicted_height": predicted_height}
	if predicted_height > crossbar_height_m:
		return {"decision": &"idle", "t_flight": t_flight,
			"intercept_x": intercept_x, "predicted_height": predicted_height}
	# R04-F01 — reachability.
	var d_lat: float = absf(intercept_x - goalkeeper.global_position.x)
	var d_eff: float = maxf(0.0, d_lat - catch_radius_m)
	var t_av: float = maxf(0.0, t_flight - reaction_buffer_s)
	var move_time_required: float = d_eff / gk_speed if gk_speed > 0.0 else INF
	if move_time_required > t_av:
		return {"decision": &"snap", "t_flight": t_flight,
			"intercept_x": intercept_x, "predicted_height": predicted_height}
	return {"decision": &"save", "t_flight": t_flight,
		"intercept_x": intercept_x, "predicted_height": predicted_height}


## Drag-aware intercept prediction using BallPhysics.predict_forward.
## Returns the same {decision, t_flight, intercept_x, predicted_height}
## shape as compute_save_decision. step() prefers this so diagonal
## shots account for drag (kinematic over-predicts X displacement
## by 10–20 % over typical shot flights).
func _predict_intercept_drag_aware(ball_pos: Vector3, ball_v: Vector3) -> Dictionary:
	var pre: Dictionary = _kinematic_intercept(ball_pos, ball_v)
	if pre.decision != &"_proceed":
		return pre
	if ball == null or not ball.has_method("predict_forward"):
		return _apply_decision_gates(pre.t_flight, pre.intercept_x,
			pre.predicted_height)
	var t_flight: float = pre.t_flight
	var sub_dt: float = 1.0 / 60.0
	var steps: int = int(ceil(t_flight / sub_dt))
	if steps <= 0:
		return _apply_decision_gates(t_flight, pre.intercept_x,
			pre.predicted_height)
	var omega: Vector3 = ball.angular_velocity \
		if ball is RigidBody3D else Vector3.ZERO
	var arr: PackedVector3Array = ball.predict_forward(ball_pos, ball_v,
		omega, 0.0, steps, sub_dt)
	if arr.size() == 0:
		return _apply_decision_gates(t_flight, pre.intercept_x,
			pre.predicted_height)
	var landing: Vector3 = arr[arr.size() - 1]
	return _apply_decision_gates(t_flight, landing.x, landing.y)


# ---- Decision executors -------------------------------------------------

## R04-F05 — angle-bisect idle. Tracks ball X at half magnitude so
## near-post is never exposed; clamps to the goal mouth. Movement
## uses a SPEED-clamped step (m/s, frame-rate-independent), NOT a
## per-tick lerp — at 120 Hz a 0.15 lerp gives ~22 m/s effective
## slingshot which reads as an unrealistic dash back to centre
## (playtest 2026-05-15). Post-catch hold window freezes the GK
## in place briefly so the idle drift starts from a beat, not an
## instant snap.
func _perform_idle(ball_pos: Vector3, dt: float) -> void:
	goalkeeper.state = Player.State.IDLE
	goalkeeper.clear_static_target()
	var current: Vector3 = goalkeeper.global_position
	var target_z: float = goal_z + signf(-goal_z) * idle_forward_offset_m
	if _post_catch_hold_remaining_s > 0.0:
		_post_catch_hold_remaining_s = maxf(0.0,
			_post_catch_hold_remaining_s - dt)
		# Hold position; stay at current X.
		goalkeeper.global_position = Vector3(current.x, current.y, target_z)
		goalkeeper.velocity = Vector3.ZERO
		goalkeeper.mark_driven()
		return
	var idle_x: float = clampf(ball_pos.x * 0.5,
		-goal_half_width_m, goal_half_width_m)
	var dx: float = idle_x - current.x
	var max_step: float = idle_max_speed_m_s * dt
	var step_x: float = clampf(dx, -max_step, max_step)
	goalkeeper.global_position = Vector3(current.x + step_x, current.y, target_z)
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


## While `_holding_ball` is true, pin the ball to the GK chest
## every tick. BallPhysics keeps integrating gravity even when
## possessed (the Sprint 8 T02 rework removed the early-return
## on `_possessed_by`), so without this the caught ball drops
## from the chest, bounces, and visually loops back to the GK.
func _pin_held_ball() -> void:
	if not _holding_ball or ball == null or goalkeeper == null:
		return
	var gp: Vector3 = goalkeeper.global_position
	ball.teleport_to(Vector3(gp.x, catch_hold_height_m, gp.z))
	ball.apply_launch_state(Vector3.ZERO, Vector3.ZERO)


## DEBUG — auto-return the held ball to the last shooter once the
## hold + return delay elapse. Computes a planar pass velocity
## from the GK to the shooter, adds a small lift, fires via
## `BallPhysics.apply_launch_state`. Skipped when target is gone
## (despawned mid-window) or BallController state changed.
func _drain_debug_return(dt: float) -> void:
	if _debug_return_remaining_s <= 0.0:
		return
	_debug_return_remaining_s = maxf(0.0, _debug_return_remaining_s - dt)
	if _debug_return_remaining_s > 0.0:
		return
	var target: Player = _debug_return_target
	_debug_return_target = null
	if target == null or not is_instance_valid(target):
		return
	if ball == null or goalkeeper == null:
		return
	var to: Vector3 = target.global_position - goalkeeper.global_position
	to.y = 0.0
	var dist: float = to.length()
	if dist < 0.1:
		return
	var dir: Vector3 = to / dist
	var v: Vector3 = Vector3(dir.x * debug_return_pass_speed_m_s,
		debug_return_pass_lift_m_s,
		dir.z * debug_return_pass_speed_m_s)
	# Release sequence:
	#   1. clear possession + holding flag
	#   2. teleport the ball OUT of the catch radius along the kick
	#      direction (otherwise next tick's `_try_catch` re-catches it)
	#   3. stage the launch velocity
	#   4. arm a brief catch lockout as a belt + braces guard
	ball.clear_possession()
	_holding_ball = false
	var release_offset_m: float = catch_radius_m + 0.6
	var release_pos: Vector3 = goalkeeper.global_position \
		+ dir * release_offset_m
	release_pos.y = catch_hold_height_m
	ball.teleport_to(release_pos)
	ball.apply_launch_state(v, Vector3.ZERO)
	_post_release_lockout_s = 0.4
	_last_decision = &"debug_return"


## R09-F02 schema hook — return the reaction buffer to use in the
## reachability gate, optionally scaled by the catch-up boost when
## eligible. In Sprint 8 the eligibility check is a stub that
## always returns false (no scoreboard yet); Sprint 9 wires it to
## the actual score + clock. Always safe to call.
func get_effective_reaction_buffer_s() -> float:
	if not catchup_boost_enabled:
		return reaction_buffer_s
	if not is_catchup_eligible():
		return reaction_buffer_s
	return reaction_buffer_s * catchup_gk_reaction_factor


## R09-F02 schema hook — eligibility predicate. Sprint 8 stub:
## ALWAYS returns false (the scoreboard / match clock that would
## populate a real check don't exist yet). Sprint 9 will inject a
## scoreboard reference and replace the body.
func is_catchup_eligible() -> bool:
	return false


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
	if _post_release_lockout_s > 0.0:
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
	# Mark possession so BallController's pickup scan + our own
	# `_try_catch` early-out skip the next ticks until release.
	ball.set_possessed(goalkeeper)
	_holding_ball = true
	_last_decision = &"catch"
	_post_catch_hold_remaining_s = post_catch_hold_s
	# DEBUG auto-return: capture the shooter so the next pass
	# lands at their feet. Only arms when the BallController and
	# the feature flag are both available.
	if debug_return_ball_enabled and ball_controller != null:
		var shooter: Player = ball_controller.get_last_released_carrier()
		if shooter != null and is_instance_valid(shooter):
			_debug_return_target = shooter
			_debug_return_remaining_s = post_catch_hold_s + debug_return_delay_s
