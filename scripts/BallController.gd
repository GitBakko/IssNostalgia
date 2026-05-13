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

# ---- Tunables ------------------------------------------------------------
## Horizontal pickup radius. 0.8 m matches the project spec.
const PICKUP_RADIUS_M: float = 0.8
const PICKUP_RADIUS_SQ: float = PICKUP_RADIUS_M * PICKUP_RADIUS_M
## Ball relative-speed gate. Above this the ball is "going too fast" to
## be cleanly picked up — 12 m/s matches the project spec.
const PICKUP_MAX_BALL_SPEED: float = 12.0
const PICKUP_MAX_BALL_SPEED_SQ: float = PICKUP_MAX_BALL_SPEED * PICKUP_MAX_BALL_SPEED
## Carry offset in player-local space. 0.5 m FORWARD (-Z, Godot model
## convention), 0.7 m below the capsule centre so the ball sits at ~ankle
## height (capsule is 1.8 m tall, centre at y=0.9). S07-D03 / R02-F06.
const CARRY_OFFSET_LOCAL: Vector3 = Vector3(0.0, -0.7, -0.5)

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


func _ready() -> void:
	_rebuild_team_order()


# ---- Public API ----------------------------------------------------------

func get_carrier() -> Player:
	return _carrier


func is_carried() -> bool:
	return _carrier != null


## Proxy for shoot / pass triggers. Shoots the ball and clears the
## carrier flag in the same call so the next pickup-scan tick sees a
## clean slate. No-op if nobody currently carries the ball.
func request_release(velocity: Vector3, angular: Vector3 = Vector3.ZERO) -> void:
	if _carrier == null or ball == null:
		return
	if debug_log:
		print("[BallController] RELEASE by %s, |v|=%.2f m/s, |ω|=%.2f rad/s" % [
			_carrier.name, velocity.length(), angular.length(),
		])
	_clear_carrier_flag()
	_carrier = null
	_pickup_lockout_remaining_s = post_release_lockout_s
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
	else:
		_sync_carry_position()


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


func _sync_carry_position() -> void:
	if _carrier == null:
		return
	# Player-local carry offset → world. basis * vec rotates the offset
	# with the player so the ball stays "in front of" them as they turn.
	var world_offset: Vector3 = _carrier.transform.basis * CARRY_OFFSET_LOCAL
	var target: Vector3 = _carrier.global_position + world_offset
	# CRITICAL: while the ball is KINEMATIC-frozen, `_integrate_forces` does
	# NOT run, so `teleport_to` (which stages _pending_teleport for the
	# integrator) silently no-ops. In KINEMATIC freeze the engine accepts
	# direct `global_position` writes — we use those instead. The pending
	# pipeline is only for unfrozen-launch flows.
	ball.global_position = target


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
	# No-op when the ball is at rest (first pickup, dead-ball restarts).
	var ball_vel: Vector3 = ball.linear_velocity
	if ball_vel.length_squared() > 0.01:
		player.start_facing_warp(-ball_vel)
	ball.set_possessed(player)


func _clear_carrier_flag() -> void:
	if _carrier != null:
		_carrier.has_ball = false
