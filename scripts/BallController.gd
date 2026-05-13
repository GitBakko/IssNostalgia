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

@export_group("Dribble impulses (S08-T02 / R02-F05 Arch B)")
## Touch interval at WALK speed. Time between successive nudges in the
## carrier's direction of travel.
@export var touch_interval_walk_s: float = 0.35
## Touch interval at SPRINT speed. Faster footstep cadence.
@export var touch_interval_sprint_s: float = 0.25
## Minimum carrier speed to start emitting impulses. Below this the
## carrier is essentially still — let drag + rolling friction stop the
## ball naturally near the player.
@export var touch_min_speed_m_s: float = 1.0
## Boost factor applied to carrier velocity when nudging the ball.
## Slightly > 1.0 so the ball stays a touch ahead of the carrier and
## drag can chew the boost down between impulses. R02-F04 says elite
## carriers retain 88-95 % of sprint speed with ball — equivalent to
## ball speed slightly ahead of the carrier on average. Default 1.10.
@export var touch_velocity_factor: float = 1.10
## Loss threshold (R02-F05). When the ball drifts beyond this distance
## from the carrier on the XZ plane, possession is automatically
## released — the carrier ran past it / got tackled / lost touch.
@export var loss_threshold_m: float = 1.6

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
var _touch_timer_s: float = 0.0


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
	_carrier = null
	_pickup_lockout_remaining_s = post_release_lockout_s
	_touch_timer_s = 0.0
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
		_carrier = null
		_touch_timer_s = 0.0
		return true
	return false


## Periodic touch impulse (R02-F05 Architecture B / R02-F04 emergent
## carry). Sets ball velocity to `carrier.velocity * touch_velocity_factor`
## every `touch_interval_walk_s` (or sprint variant) while the carrier
## is moving above the min-speed gate. Drag bleeds the impulse between
## ticks; the carrier catches up briefly between nudges.
func _tick_dribble_impulses(delta: float) -> void:
	if _carrier == null:
		return
	var carrier_v: Vector3 = _carrier.velocity
	var carrier_speed: float = carrier_v.length()
	if carrier_speed < touch_min_speed_m_s:
		_touch_timer_s = 0.0
		return
	_touch_timer_s += delta
	# Pick interval by speed regime — anything > max_walk_speed counts
	# as sprint cadence.
	var interval: float = touch_interval_walk_s
	if carrier_speed > _carrier.max_walk_speed:
		interval = touch_interval_sprint_s
	if _touch_timer_s < interval:
		return
	_touch_timer_s = 0.0
	_apply_touch_impulse(carrier_v)


## Set ball linear velocity to `carrier_v * touch_velocity_factor` on
## the XZ plane via the BallPhysics pending pipeline. Ball stays live —
## no freeze, no carrier flag changes.
func _apply_touch_impulse(carrier_v: Vector3) -> void:
	var planar: Vector3 = Vector3(carrier_v.x, 0.0, carrier_v.z)
	var target: Vector3 = planar * touch_velocity_factor
	# Preserve current Y velocity (e.g. a small bounce mid-roll) — only
	# overwrite XZ. We do this by reading the live velocity and patching
	# the X/Z components.
	var live: Vector3 = ball.linear_velocity
	target.y = live.y
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


func _clear_carrier_flag() -> void:
	if _carrier != null:
		_carrier.has_ball = false
