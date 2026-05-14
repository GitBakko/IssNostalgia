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
## Boost factor on the carrier velocity. > 1 = ball outruns carrier
## briefly between kicks. 1.10 = 10 % boost, ball flies ~1-2 m
## before drag brings it back below carrier speed. Lower = tighter
## control, higher = looser dribble.
@export var kick_velocity_factor: float = 1.10
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
		return  ## carrier still — no kick, ball settles via friction
	# Geometric trigger: carrier body reached the ball position.
	var dx: float = ball.global_position.x - _carrier.global_position.x
	var dz: float = ball.global_position.z - _carrier.global_position.z
	if dx * dx + dz * dz > kick_proximity_m * kick_proximity_m:
		return  ## not yet at the ball — let carrier chase
	# FIRE THE KICK — ball gets carrier_v * factor. Uses carrier
	# velocity direction (not ball direction) so ball always flies
	# in the player's current heading, even on hard turns.
	_apply_proximity_kick(carrier_v)
	_kick_lockout_remaining_s = kick_lockout_s


func _apply_proximity_kick(carrier_v: Vector3) -> void:
	var planar: Vector3 = Vector3(carrier_v.x, 0.0, carrier_v.z)
	if planar.length_squared() < 0.01:
		return
	var target: Vector3 = planar * kick_velocity_factor
	target.y = ball.linear_velocity.y  ## preserve Y (mid-bounce)
	ball.apply_launch_state(target)


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
		_carrier.has_ball = false
