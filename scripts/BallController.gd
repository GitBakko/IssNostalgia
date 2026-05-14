class_name BallController
extends Node

## Sprint 7 T02 — single arbiter for ball possession at the match level
## (S07-D02). Players don't see each other; only BallController decides
## who picks the ball up, syncs its position during carry, and proxies
## `release()` calls from ShootingController / PassingController.
##
## Tie-breaker on simultaneous pickup (S06-D03): human teams iterated
## first, so a human player and an AI player tied at the same horizontal
## distance always lets the human win.
##
## Sprint 8 T02-rework adopts R02-F05 Architecture B: the ball stays
## LIVE the whole time (no freeze, no collision change). Possession is
## logical — the `_carrier` flag gates shoot/pass eligibility and
## auto-switch — but the ball physics keeps integrating. While the
## carrier is moving, BallController applies a periodic touch impulse
## (`apply_launch_state(carrier_v * touch_velocity_factor)`) every
## ~0.25-0.4 s in the carrier's direction of travel. Drag + rolling
## friction handle deceleration when the carrier slows. No "glued to
## foot" carry phase — the ball is always rolling.
##
## Possession ends naturally when:
##   - SHOOT/PASS via request_release (pickup lockout armed),
##   - the ball drifts beyond `loss_threshold_m` from the carrier
##     (1.6 m per R02-F05; tackled / out-paced).

enum ReleaseKind {
	SHOOT,    ## intentional shot — armed by ShootingController
	PASS,     ## intentional pass — armed by PassingController
}

# ---- Tunables ------------------------------------------------------------
## Horizontal pickup radius. 0.8 m matches the project spec.
const PICKUP_RADIUS_M: float = 0.8
const PICKUP_RADIUS_SQ: float = PICKUP_RADIUS_M * PICKUP_RADIUS_M
## Ball relative-speed gate. Above this the ball is "going too fast" to
## be cleanly picked up — 12 m/s matches the project spec.
const PICKUP_MAX_BALL_SPEED: float = 12.0
const PICKUP_MAX_BALL_SPEED_SQ: float = PICKUP_MAX_BALL_SPEED * PICKUP_MAX_BALL_SPEED

@export_group("Dribble — geometric proximity kick (R02-F05 Arch B feel)")
## When the carrier's body reaches the ball's position (XZ distance
## under this), a TOUCH fires — kicks the ball forward at carrier
## velocity * kick_factor. This is the geometric analog of "foot
## reaches ball" — no periodic timer, the cycle length emerges from
## drag + carrier speed (real football: kick → coast → catch up → kick).
@export var kick_proximity_m: float = 0.35
## Boost factor on the carrier velocity at WALK speed. 1.08 = ball
## leaves 8 % faster than carrier → ~0.5–0.7 m flight before drag
## brings it back. Short hops, tight close-control feel. Tuned
## 2026-05-14 per user playtest. Will become per-player attribute
## (close_control / dribble_skill) in Sprint 9 — see R02-F07.
@export var kick_factor_walk: float = 1.08
## Boost factor at SPRINT speed (carrier_speed > max_walk_speed).
## 1.18 → ~1.8–2.2 m flight, attackers cover ground but the ball
## stays in the carry zone. Tuned 2026-05-14 per user playtest.
## Per-player override planned for Sprint 9 (R02-F07 attributes).
@export var kick_factor_sprint: float = 1.18
## Fix #2 (R09-F04 anim warp + R02-F03 blend): kick direction = blend
## of carrier visual_forward (rotates immediately on input) and
## carrier.velocity (physical, lags on hard turn). 0.0 = pure
## velocity (ball lags on turn), 1.0 = pure visual (responsive to
## facing). 0.7 = strongly visual-led with physics safety net.
@export_range(0.0, 1.0, 0.05) var kick_direction_blend_visual: float = 0.7
## Fix #4 (R02-F04 attribute-driven control): when the new kick
## direction differs from the previous kick direction by more than
## this many degrees, scale down the kick factor — keeps the ball
## closer through hard turns instead of launching it across the pitch.
@export var kick_turn_dampen_threshold_deg: float = 30.0
## Multiplier applied to the chosen walk/sprint factor when the turn
## threshold trips. 0.65 → 35 % weaker kick on a sharp redirect.
@export_range(0.0, 1.0, 0.05) var kick_turn_dampen_factor: float = 0.65
## Brief lockout after each kick — prevents the same physics tick
## from firing the kick twice in a row (kick → ball still inside
## proximity for a frame → would re-fire). 0.05 s = 6 ticks @ 120 Hz,
## enough for the ball to clear the proximity radius at any kick speed.
@export var kick_lockout_s: float = 0.05
## Minimum carrier speed to fire a kick. Below this, the carrier is
## essentially stopped and the ball just sits at its feet (drag will
## stop any prior motion).
@export var kick_min_carrier_speed_m_s: float = 0.5
## Loss threshold — ball drifts beyond this from the carrier on the
## XZ plane → carrier flag cleared. Generous since the natural cycle
## keeps the ball within ~1-2 m at all times; this is a safety rail
## for hard-turn / tackle (Sprint 9+) scenarios.
@export var loss_threshold_m: float = 3.0
## Brief pickup lockout when possession is lost.
@export var touch_loss_lockout_s: float = 0.1

@export_group("Stop trap & passive brake (anti-runaway-ball)")
## Radius around the carrier within which a passive brake is applied
## to the ball when the carrier is at/near rest. Prevents the
## "player stops, ball rolls away forever" frustration. 1.2 m covers
## the natural kick flight distance at walk speed.
@export var brake_radius_m: float = 1.2
## Per-second decay rate applied to the ball's planar velocity while
## the carrier is below `kick_min_carrier_speed_m_s` and ball is
## within `brake_radius_m`. 6.0 → 95 % planar speed gone in ~0.5 s.
@export var brake_decay_per_sec: float = 6.0
## Below this planar speed the passive brake snaps the ball to a
## complete planar stop (avoids endless tiny crawls).
@export var brake_snap_threshold_m_s: float = 0.4

@export_group("Turn-glue (ball locked to foot during direction change)")
## Master switch. The ONLY moment the ball is "glued" to the foot —
## while the carrier is rotating their visual forward. Outside of
## active turning, normal kick + drag physics apply (no continuous
## tracking, no centering pull).
@export var turn_glue_enabled: bool = true
## Maximum ball-to-carrier distance for the glue snap. Beyond
## this the ball is too loose to be considered "at the foot" and
## the loss / loose-ball path takes over instead.
@export var turn_glue_radius_m: float = 1.0
## Minimum per-tick visual rotation (deg) before the glue fires.
## Below this the carrier is essentially steady — ignore jitter so
## the ball can coast freely between turns.
@export var turn_glue_min_angle_deg: float = 0.5
## Carry offset along visual_forward used by the glue snap. Ball
## position is locked to (carrier + visual_forward * this) on every
## turn tick. Slightly larger than kick_proximity_m so the glue
## snap does NOT immediately satisfy the kick gate the same tick
## (otherwise the snap would chain into a kick that scatters the
## ball away from the foot during the turn).
@export var turn_glue_offset_m: float = 0.40

@export_group("Magnetic centering (R02-F03 PhysicsFC carry-zone)")
## Master switch. DEFAULT OFF (per playtest 2026-05-14): the
## centering lerp is exactly the "dynamic repositioning" feel the
## user rejected. Turn-glue handles direction changes, and free
## physics handles between-kick coasting. Kept as opt-in @export
## for future cases where a softer pull may be wanted.
@export var centering_enabled: bool = false
## Ideal carry distance ahead of the carrier along carry_dir
## (visual_forward + velocity blend). 0.45 m sits the ball just
## beyond the foot — within next-touch reach but visibly "ahead".
@export var centering_offset_m: float = 0.45
## Position-error magnitude below which centering is a no-op
## (avoids jitter when the ball is already in the carry zone).
@export var centering_dead_zone_m: float = 0.15
## Per-second pull rate. 4.0 → ~87 % of error closed in 0.5 s.
## NOT a "glue" — the ball still flies on kicks and decelerates
## via drag; centering only fires between kicks while the ball
## is slow enough (< centering_max_ball_speed_m_s) and inside
## centering_max_radius_m. Tuned conservative so the visible
## kick-chase rhythm survives.
@export var centering_pull_per_sec: float = 4.0
## Caps the corrective velocity component added on top of the
## carrier-matched baseline. Prevents teleport-feeling snaps.
@export var centering_max_correction_m_s: float = 5.0
## Beyond this distance from the carrier, centering is skipped —
## the loss threshold (3 m) takes over instead. Centering is for
## small carry-zone deviations during turns, not full recoveries.
@export var centering_max_radius_m: float = 1.5
## Centering is skipped while the ball is moving faster than this
## (e.g. just been kicked, mid-shot). Lets natural physics play
## out before the carry-zone pull resumes.
@export var centering_max_ball_speed_m_s: float = 8.0

# ---- Exports -------------------------------------------------------------
@export var ball: BallPhysics
## All TeamControllers participating in this match. The order is
## significant for the tie-breaker — controllers are sorted by
## `is_human` (true first) at _ready.
@export var teams: Array[TeamController] = []

## Print every pickup attempt + carrier change. Off by default — flip on
## from the editor when diagnosing "the ball doesn't latch" complaints.
@export var debug_log: bool = false

## Post-release pickup lockout. After a shoot / pass releases the ball,
## NO player can pick it up for this many seconds. Without this gate,
## the same physics tick that fires the release also re-runs the pickup
## scan — and since the ball sits 0.5 m in front of the carrier (the
## CARRY_OFFSET), it's already inside the 0.8 m pickup radius, so the
## carrier instantly grabs it back and the launch velocity (staged via
## the deferred-freeze/pending pipeline) is wiped. 300 ms covers the
## ~36 physics ticks the integrator needs to re-establish |v| > 0 and
## carry the ball outside the radius even for the slowest grounder pass.
@export var post_release_lockout_s: float = 0.3

# ---- Runtime state -------------------------------------------------------
var _carrier: Player = null
var _ordered_teams: Array[TeamController] = []
var _last_log_pickup_dist_sq: float = INF
var _pickup_lockout_remaining_s: float = 0.0
var _kick_lockout_remaining_s: float = 0.0
## Direction of the previous kick — used to detect turn for #4 dampen.
var _last_kick_direction: Vector3 = Vector3.ZERO
## Last carry direction (visual+velocity blend) for turn-glue rotation
## detection. Cleared on possession change.
var _last_carry_dir: Vector3 = Vector3.ZERO

## Emitted whenever a touch (proximity kick) fires. Carrier listens to
## flush its direction-input buffer (S08 dribble-buffer system).
signal touch_fired(carrier: Player)
## Player currently in the ball's collision-exception list (the only
## one that can "walk through" the ball). Tracked here so we can
## remove the exception cleanly on release / loss.
var _exception_carrier: Node = null


func _ready() -> void:
	_rebuild_team_order()


# ---- Public API ----------------------------------------------------------

func get_carrier() -> Player:
	return _carrier


func is_carried() -> bool:
	return _carrier != null


## Proxy for shoot / pass triggers. Releases the ball with a launch
## velocity and arms the anti re-grab lockout (Sprint 7 fix2). The
## kind argument is informational for logging / future per-release
## animation timing.
func request_release(velocity: Vector3, angular: Vector3 = Vector3.ZERO,
		kind: ReleaseKind = ReleaseKind.SHOOT) -> void:
	if _carrier == null or ball == null:
		return
	if debug_log:
		print("[BallController] RELEASE (%s) by %s, |v|=%.2f m/s, |ω|=%.2f rad/s" % [
			ReleaseKind.keys()[kind], _carrier.name, velocity.length(), angular.length(),
		])
	_clear_carrier_flag()
	_clear_collision_exception()
	_carrier = null
	_pickup_lockout_remaining_s = post_release_lockout_s
	_kick_lockout_remaining_s = 0.0
	ball.release(velocity, angular)


## Pure-on-instance step. Tests drive this directly with explicit player
## / ball positions instead of going through `_physics_process`.
func step(delta: float) -> void:
	if ball == null:
		return
	if _pickup_lockout_remaining_s > 0.0:
		_pickup_lockout_remaining_s = maxf(0.0, _pickup_lockout_remaining_s - delta)
	if _carrier == null:
		_try_pickup()
		return
	# Carrier present — check loss first, then nudge the ball.
	if _check_loss():
		return
	_tick_dribble_impulses(delta)


## R02-F05 loss threshold: ball drifts beyond `loss_threshold_m` from
## the carrier on the XZ plane → possession lost. Returns true when
## the carrier was cleared this tick.
func _check_loss() -> bool:
	if _carrier == null:
		return false
	var dx: float = ball.global_position.x - _carrier.global_position.x
	var dz: float = ball.global_position.z - _carrier.global_position.z
	if dx * dx + dz * dz > loss_threshold_m * loss_threshold_m:
		if debug_log:
			print("[BallController] LOSS — %s lost ball at d=%.2fm" % [
				_carrier.name, sqrt(dx * dx + dz * dz),
			])
		_clear_carrier_flag()
		_clear_collision_exception()
		_carrier = null
		_kick_lockout_remaining_s = 0.0
		# CRITICAL: also clear BallPhysics._possessed_by — without this
		# the ball keeps reporting is_possessed() == true and _try_pickup
		# skips every subsequent pickup forever. Without launch override
		# (loss is "the foot couldn't keep up", not an intentional kick).
		ball.clear_possession()
		# Brief pickup lockout so the carrier doesn't instantly re-grab
		# the ball still drifting away — gives the loss feel weight.
		_pickup_lockout_remaining_s = touch_loss_lockout_s
		return true
	return false


## Geometric proximity-kick dribble (R02-F05 Architecture B feel,
## emergent rhythm per R02-F04 + R02-F03). Each tick:
##   - If the carrier's body has reached the ball (XZ distance under
##     kick_proximity_m) AND no kick lockout AND carrier moving →
##     fire a touch: ball.velocity = carrier.velocity * kick_factor.
##   - Otherwise: nothing. Ball coasts under live physics (drag,
##     friction, bounce). Carrier moves freely. The two will meet
##     again when the carrier closes the gap to the slowing ball.
##
## NO position copy. NO continuous tracking. NO periodic timer.
## The cycle length emerges from drag + carrier speed:
##   walk (5.5 m/s, factor 1.10): cycle ≈ 0.22 s, flight ≈ 1.2 m
##   sprint (8 m/s, factor 1.10): cycle ≈ 0.32 s, flight ≈ 2.5 m
## Producing the visible "lancia → rincorri → lancia" rhythm of
## real football dribbling. Ball is kicked AT the foot (the kick
## fires when foot reaches ball), not from far ahead.
func _tick_dribble_impulses(delta: float) -> void:
	if _carrier == null:
		return
	if _kick_lockout_remaining_s > 0.0:
		_kick_lockout_remaining_s = maxf(0.0, _kick_lockout_remaining_s - delta)
	if _kick_lockout_remaining_s > 0.0:
		return
	var carrier_v: Vector3 = _carrier.velocity
	var carrier_speed: float = carrier_v.length()
	if carrier_speed < kick_min_carrier_speed_m_s:
		# Carrier essentially stopped: passive-brake the ball if it's
		# still rolling within trap range so it doesn't drift away.
		_apply_passive_brake(delta)
		_last_carry_dir = Vector3.ZERO  ## reset turn-glue baseline
		return
	# Turn-glue first: if the carrier's visual_forward rotated this
	# tick AND the ball is at the foot, hard-snap the ball to the
	# foot zone in the new heading and match carrier velocity.
	# Returning true skips the kick + centering paths so the snap
	# doesn't immediately scatter the ball back out (per playtest
	# 2026-05-14 — turn must look exactly glued, no smoothing).
	if _apply_turn_glue(carrier_v, carrier_speed):
		return
	# Geometric trigger: carrier body reached the ball position.
	var dx: float = ball.global_position.x - _carrier.global_position.x
	var dz: float = ball.global_position.z - _carrier.global_position.z
	if dx * dx + dz * dz <= kick_proximity_m * kick_proximity_m \
			and _kick_lockout_remaining_s <= 0.0:
		# FIRE THE KICK — ball gets carrier_v * factor. Uses carrier
		# velocity direction (not ball direction) so ball always flies
		# in the player's current heading, even on hard turns.
		_apply_proximity_kick(carrier_v)
		_kick_lockout_remaining_s = kick_lockout_s
		return
	# Not at the ball this tick: optional magnetic centering pull.
	# DEFAULT OFF (centering_enabled = false) per the same playtest
	# — the lerp toward the ideal carry zone is exactly the "dynamic
	# repositioning" feel the user rejected.
	_apply_magnetic_centering(delta, carrier_v, carrier_speed)


## Carry direction = same blend used by the kick (visual_forward +
## velocity dir, weighted by `kick_direction_blend_visual`). Returns
## a unit vector or ZERO if neither input was usable. Kept for the
## centering helper; turn-glue uses pure visual_forward.
func _compute_carry_dir(carrier_v: Vector3, carrier_speed: float) -> Vector3:
	var v_dir: Vector3 = Vector3.ZERO
	if carrier_speed > 0.001:
		v_dir = Vector3(carrier_v.x / carrier_speed, 0.0,
			carrier_v.z / carrier_speed)
	var fwd: Vector3 = _carrier.get_visual_forward()
	var blend_w: float = clampf(kick_direction_blend_visual, 0.0, 1.0)
	var raw: Vector3 = v_dir * (1.0 - blend_w) + fwd * blend_w
	if raw.length_squared() < 0.001:
		return Vector3.ZERO
	return raw.normalized()


## Turn-glue. When the carrier's VISUAL forward rotates by more than
## `turn_glue_min_angle_deg` in a single tick AND the ball is within
## `turn_glue_radius_m`, HARD-SNAP the ball to the ideal foot offset
## along the new visual forward AND match the carrier velocity. No
## smoothing, no per-tick cap — the ball is locked to the foot for
## that tick.
##
## Returns true when glue was applied (callers skip the kick gate so
## the snap doesn't immediately re-fire as a proximity kick).
##
## Tracks visual_forward (NOT the velocity blend used by the kick)
## because the player's mesh rotates immediately on input (Q1) while
## velocity lags via accel — using visual_forward here makes the ball
## follow the rotation instantly with no apparent delay or arc swing.
func _apply_turn_glue(carrier_v: Vector3, _carrier_speed: float) -> bool:
	if not turn_glue_enabled or _carrier == null or ball == null:
		return false
	var fwd_now: Vector3 = _carrier.get_visual_forward()
	if fwd_now.length_squared() < 0.001:
		return false
	if _last_carry_dir.length_squared() < 0.001:
		_last_carry_dir = fwd_now
		return false  ## first tick — establish baseline
	var p_pos: Vector3 = _carrier.global_position
	var b_pos: Vector3 = ball.global_position
	var rel_x: float = b_pos.x - p_pos.x
	var rel_z: float = b_pos.z - p_pos.z
	if rel_x * rel_x + rel_z * rel_z > turn_glue_radius_m * turn_glue_radius_m:
		_last_carry_dir = fwd_now
		return false  ## ball loose — let physics / loss handle it
	# Signed planar angle delta from _last_carry_dir → fwd_now.
	var ang_a: float = atan2(_last_carry_dir.z, _last_carry_dir.x)
	var ang_b: float = atan2(fwd_now.z, fwd_now.x)
	var dtheta: float = ang_b - ang_a
	if dtheta > PI:
		dtheta -= TAU
	elif dtheta < -PI:
		dtheta += TAU
	var min_ang: float = deg_to_rad(turn_glue_min_angle_deg)
	if absf(dtheta) < min_ang:
		_last_carry_dir = fwd_now
		return false  ## no meaningful turn this tick
	# HARD GLUE — ball snaps to the carrier's foot zone in the new
	# visual heading, velocity matches the carrier so the ball
	# continues with the player on the next tick.
	var ideal_x: float = p_pos.x + fwd_now.x * turn_glue_offset_m
	var ideal_z: float = p_pos.z + fwd_now.z * turn_glue_offset_m
	ball.teleport_to(Vector3(ideal_x, b_pos.y, ideal_z))
	ball.apply_launch_state(Vector3(carrier_v.x,
		ball.linear_velocity.y, carrier_v.z))
	_last_carry_dir = fwd_now
	return true


## Passive brake — when carrier intent is "stop" (low velocity) and the
## ball is within trap range, decay the ball's planar speed each tick.
## Y is preserved so a mid-bounce ball still falls naturally.
func _apply_passive_brake(delta: float) -> void:
	if _carrier == null or ball == null:
		return
	var dx: float = ball.global_position.x - _carrier.global_position.x
	var dz: float = ball.global_position.z - _carrier.global_position.z
	if dx * dx + dz * dz > brake_radius_m * brake_radius_m:
		return
	var v: Vector3 = ball.linear_velocity
	var planar_sq: float = v.x * v.x + v.z * v.z
	if planar_sq < 0.0001:
		return
	var planar_speed: float = sqrt(planar_sq)
	if planar_speed <= brake_snap_threshold_m_s:
		ball.apply_launch_state(Vector3(0.0, v.y, 0.0))
		return
	var factor: float = clampf(1.0 - brake_decay_per_sec * delta, 0.0, 1.0)
	ball.apply_launch_state(Vector3(v.x * factor, v.y, v.z * factor))


## Carry-zone magnetic centering. Each non-kick tick (carrier moving
## but not at proximity yet, or in kick lockout), nudges the ball's
## planar velocity toward the ideal carry point ahead of the carrier.
##
## NOT continuous-tracking glue (Architecture C, explicitly rejected):
##   - skipped while ball planar speed > centering_max_ball_speed_m_s
##     (just-kicked ball flies free until drag slows it),
##   - skipped beyond centering_max_radius_m (loss threshold owns
##     the recovery arc past 1.5 m),
##   - skipped within centering_dead_zone_m (no jitter when settled),
##   - corrective velocity capped by centering_max_correction_m_s.
##
## The visible kick → fly → catch-up rhythm is preserved; the centering
## only fixes the residual drift that accumulates during slow circular
## direction sweeps where each input step is below the buffer dead-zone.
func _apply_magnetic_centering(delta: float, carrier_v: Vector3,
		carrier_speed: float) -> void:
	if not centering_enabled or _carrier == null or ball == null:
		return
	var bv: Vector3 = ball.linear_velocity
	if bv.x * bv.x + bv.z * bv.z \
			> centering_max_ball_speed_m_s * centering_max_ball_speed_m_s:
		return
	var p_pos: Vector3 = _carrier.global_position
	var b_pos: Vector3 = ball.global_position
	var to_ball_x: float = b_pos.x - p_pos.x
	var to_ball_z: float = b_pos.z - p_pos.z
	if to_ball_x * to_ball_x + to_ball_z * to_ball_z \
			> centering_max_radius_m * centering_max_radius_m:
		return
	# Carry direction = same blend used by the kick (visual_forward
	# + velocity dir). Keeps the ball aligned with where the player
	# is heading next, not just where they're going right now.
	var v_dir: Vector3 = Vector3(carrier_v.x / carrier_speed, 0.0,
		carrier_v.z / carrier_speed)
	var fwd_dir: Vector3 = _carrier.get_visual_forward()
	var blend_w: float = clampf(kick_direction_blend_visual, 0.0, 1.0)
	var carry_raw: Vector3 = v_dir * (1.0 - blend_w) + fwd_dir * blend_w
	var carry_dir: Vector3 = v_dir
	if carry_raw.length_squared() > 0.001:
		carry_dir = carry_raw.normalized()
	var ideal_x: float = p_pos.x + carry_dir.x * centering_offset_m
	var ideal_z: float = p_pos.z + carry_dir.z * centering_offset_m
	var err_x: float = ideal_x - b_pos.x
	var err_z: float = ideal_z - b_pos.z
	var err_len: float = sqrt(err_x * err_x + err_z * err_z)
	if err_len < centering_dead_zone_m:
		return
	# Target velocity = match the carrier's planar motion + corrective
	# pull toward the ideal point. Cap the correction magnitude so the
	# ball never visibly teleports.
	var corr_speed: float = clampf(err_len * centering_pull_per_sec,
		0.0, centering_max_correction_m_s)
	var corr_x: float = (err_x / err_len) * corr_speed
	var corr_z: float = (err_z / err_len) * corr_speed
	var target_vx: float = carry_dir.x * carrier_speed + corr_x
	var target_vz: float = carry_dir.z * carrier_speed + corr_z
	# Lerp planar velocity toward target. alpha is dt-scaled so frame
	# rate doesn't change the perceived feel.
	var alpha: float = clampf(centering_pull_per_sec * delta, 0.0, 1.0)
	var new_vx: float = lerpf(bv.x, target_vx, alpha)
	var new_vz: float = lerpf(bv.z, target_vz, alpha)
	ball.apply_launch_state(Vector3(new_vx, bv.y, new_vz))


func _apply_proximity_kick(carrier_v: Vector3) -> void:
	var planar: Vector3 = Vector3(carrier_v.x, 0.0, carrier_v.z)
	var carrier_speed: float = planar.length()
	if carrier_speed < 0.01:
		return
	var v_dir: Vector3 = planar / carrier_speed

	# Buffer-aware: a touch fired while the carrier had a buffered
	# direction change is the moment the dribble snaps to the new
	# heading. Two cases:
	#   - buffered STOP (intent ~ ZERO) → TRAP: zero out planar ball
	#     velocity so the ball comes to rest at the foot;
	#   - buffered TURN (intent != ZERO) → PIVOT: kick along the new
	#     intent AND snap player.velocity to it (preserves planar
	#     speed). Without the velocity snap the body keeps drifting
	#     in the OLD committed direction while the ball flies in the
	#     NEW intended direction → instant possession loss on every
	#     hard turn (Bug 1, playtest 2026-05-14).
	var buf_active: bool = false
	var buf_intent: Vector3 = Vector3.ZERO
	if _carrier.has_method("get_buffer_state"):
		var bs: Dictionary = _carrier.get_buffer_state()
		buf_active = bool(bs.get("active", false))
		buf_intent = bs.get("intent", Vector3.ZERO)
	var buf_intent_zero: bool = buf_intent.length_squared() < 1.0e-4

	if buf_active and buf_intent_zero:
		# TRAP — buffered stop. Settle the ball planar-still at foot.
		var bv: Vector3 = ball.linear_velocity
		ball.apply_launch_state(Vector3(0.0, bv.y, 0.0))
		_last_kick_direction = Vector3.ZERO
		if _carrier.has_method("on_dribble_touch"):
			_carrier.on_dribble_touch()
		touch_fired.emit(_carrier)
		return

	# Choose kick direction.
	var kick_dir: Vector3
	if buf_active and not buf_intent_zero:
		# PIVOT — kick along the new intent; pivot the body too.
		kick_dir = buf_intent.normalized()
		if _carrier.has_method("snap_velocity_direction"):
			_carrier.snap_velocity_direction(kick_dir)
	else:
		# Default — visual-led blend (Fix #2 R09-F04 + R02-F03).
		var fwd_dir: Vector3 = _carrier.get_visual_forward()
		var blend_w: float = clampf(kick_direction_blend_visual, 0.0, 1.0)
		var kick_dir_raw: Vector3 = v_dir * (1.0 - blend_w) + fwd_dir * blend_w
		kick_dir = v_dir
		if kick_dir_raw.length_squared() > 0.001:
			kick_dir = kick_dir_raw.normalized()

	# Walk vs sprint factor (user tune 2026-05-14).
	var factor: float = kick_factor_walk
	if carrier_speed > _carrier.max_walk_speed:
		factor = kick_factor_sprint

	# Fix #4 — dampen the factor on detected turn so the ball doesn't
	# escape control during direction changes.
	if _last_kick_direction.length_squared() > 0.001:
		var cos_thresh: float = cos(deg_to_rad(kick_turn_dampen_threshold_deg))
		if _last_kick_direction.dot(kick_dir) < cos_thresh:
			factor *= kick_turn_dampen_factor

	var target: Vector3 = kick_dir * (carrier_speed * factor)
	target.y = ball.linear_velocity.y  ## preserve Y (mid-bounce)
	ball.apply_launch_state(target)
	_last_kick_direction = kick_dir

	# Notify carrier — flushes its direction-input buffer (Q1-Q8).
	if _carrier.has_method("on_dribble_touch"):
		_carrier.on_dribble_touch()
	touch_fired.emit(_carrier)


# ---- Lifecycle -----------------------------------------------------------

func _physics_process(delta: float) -> void:
	step(delta)


# ---- Internal -----------------------------------------------------------

func _rebuild_team_order() -> void:
	_ordered_teams.clear()
	# Human teams first (S06-D03 tie-breaker).
	for t in teams:
		if t != null and t.is_human:
			_ordered_teams.append(t)
	for t in teams:
		if t != null and not t.is_human:
			_ordered_teams.append(t)


func _try_pickup() -> void:
	# Gate 0: post-release lockout — block re-pickup so the launch
	# velocity has time to carry the ball out of the carrier's radius.
	if _pickup_lockout_remaining_s > 0.0:
		return
	# Gate 1: ball must be slow enough to grab.
	if ball.linear_velocity.length_squared() > PICKUP_MAX_BALL_SPEED_SQ:
		return
	# Gate 2: ball must not already be possessed (defensive — set_possessed
	# would have set _carrier above, but a bare BallPhysics.set_possessed
	# call from a test would skip our flag).
	if ball.is_possessed():
		return
	var ball_pos: Vector3 = ball.global_position
	var nearest_dist_sq: float = INF
	var nearest: Player = null
	for team in _ordered_teams:
		for p in team.players:
			if p == null or p.is_goalkeeper:
				continue  ## Sprint 7 GK doesn't pick up — Sprint 8 logic
			var dx: float = p.global_position.x - ball_pos.x
			var dz: float = p.global_position.z - ball_pos.z
			var d_sq: float = dx * dx + dz * dz
			if d_sq < nearest_dist_sq:
				nearest_dist_sq = d_sq
				nearest = p
			if d_sq <= PICKUP_RADIUS_SQ:
				if debug_log:
					print("[BallController] PICKUP %s @ d=%.2fm (radius=%.2fm)" % [
						p.name, sqrt(d_sq), PICKUP_RADIUS_M,
					])
				_assign_carrier(p)
				_last_log_pickup_dist_sq = INF
				return  ## tie-breaker: first hit wins (humans iterated first)
	# No pickup this tick — log progress when the nearest player gets
	# meaningfully closer than the previous best (every 0.5 m bracket).
	if debug_log and nearest != null:
		var bracket: float = floor(sqrt(nearest_dist_sq) / 0.5) * 0.5
		var prev_bracket: float = floor(sqrt(_last_log_pickup_dist_sq) / 0.5) * 0.5
		if bracket < prev_bracket:
			print("[BallController] near miss: %s @ d=%.2fm (need ≤ %.2fm), ball|v|=%.2f" % [
				nearest.name, sqrt(nearest_dist_sq), PICKUP_RADIUS_M,
				ball.linear_velocity.length(),
			])
		_last_log_pickup_dist_sq = nearest_dist_sq




func _assign_carrier(player: Player) -> void:
	if _carrier != null:
		_clear_carrier_flag()
	_clear_collision_exception()
	_carrier = player
	_carrier.has_ball = true
	# Reception facing warp (R09-F04): orient the receiver TOWARD the
	# incoming ball (= -ball.linear_velocity) over ~110-150 ms — fast
	# enough that the carry offset (in the player's local forward, -Z)
	# doesn't visibly drag the ball through their old forward, slow
	# enough that it reads as a natural turn rather than a scatto.
	# Gates:
	#   - ball at rest → no warp (first pickup, dead-ball restarts).
	#   - ball moving AWAY from the player → no warp (carrier chasing
	#     their own touch from S08-T02 dribble; warp would face them
	#     backwards). Detected via dot(ball_vel, player_pos - ball_pos).
	var ball_vel: Vector3 = ball.linear_velocity
	if ball_vel.length_squared() > 0.01:
		var to_player: Vector3 = player.global_position - ball.global_position
		to_player.y = 0.0
		if ball_vel.dot(to_player) > 0.0:
			player.start_facing_warp(-ball_vel)
	ball.set_possessed(player)
	# Add a collision exception so the carrier can walk THROUGH the
	# ball — without this the CharacterBody3D capsule (radius 0.4)
	# blocks at 0.51 m from the ball centre, the carrier's velocity
	# drops to ~0, the dribble impulse never fires (touch_min_speed
	# gate), and the ball ends up an unmovable boulder. Other players
	# stay solid against the ball — only THIS carrier passes through.
	ball.add_collision_exception_with(player)
	_exception_carrier = player
	# No prime impulse needed in continuous-tracking mode — the per-tick
	# position+velocity lerp converges to the carry target within
	# ~3 frames at 60 fps regardless of the initial geometry.
	_kick_lockout_remaining_s = 0.0


func _clear_collision_exception() -> void:
	if ball == null or _exception_carrier == null:
		return
	if is_instance_valid(_exception_carrier):
		ball.remove_collision_exception_with(_exception_carrier)
	_exception_carrier = null


func _clear_carrier_flag() -> void:
	if _carrier != null:
		if _carrier.has_method("on_possession_lost"):
			_carrier.on_possession_lost()
		_carrier.has_ball = false
	_last_kick_direction = Vector3.ZERO
	_last_carry_dir = Vector3.ZERO
