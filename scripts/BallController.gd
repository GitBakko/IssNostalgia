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
## Sprint 8 T02 adds the touch-cycle dribble (R02-F05 Architecture C):
## while the carrier is moving the ball is periodically released forward
## (TOUCH kind) at `ball_speed_ratio_on_touch * carrier.velocity`, then
## re-picked up automatically when the carrier catches up. SHOOT and
## PASS releases keep the post-release pickup lockout from Sprint 7;
## TOUCH releases skip it (a 0.4 s sprint cadence < 0.3 s lockout).

enum ReleaseKind {
	SHOOT,    ## intentional shot — armed by ShootingController
	PASS,     ## intentional pass — armed by PassingController
	TOUCH,    ## dribble touch — emitted from inside step(); no lockout
}

# ---- Tunables ------------------------------------------------------------
## Horizontal pickup radius. 0.8 m matches the project spec.
const PICKUP_RADIUS_M: float = 0.8
const PICKUP_RADIUS_SQ: float = PICKUP_RADIUS_M * PICKUP_RADIUS_M
## Ball relative-speed gate. Above this the ball is "going too fast" to
## be cleanly picked up — 12 m/s matches the project spec.
const PICKUP_MAX_BALL_SPEED: float = 12.0
const PICKUP_MAX_BALL_SPEED_SQ: float = PICKUP_MAX_BALL_SPEED * PICKUP_MAX_BALL_SPEED

@export_group("Touch-cycle dribble (S08-T02 / R02-F05)")
## Touch interval at WALK speed (carrier velocity ≤ max_walk). Long
## enough that a slow build-up doesn't constantly tap the ball.
@export var touch_interval_walk_s: float = 0.6
## Touch interval at SPRINT speed. Short enough that a sprint dribble
## reads as continuous touches rather than one big launch.
@export var touch_interval_sprint_s: float = 0.4
## Minimum carrier speed to start the touch timer at all. Below this
## the carrier is essentially still and the ball stays glued.
@export var touch_min_speed_m_s: float = 1.5
## Multiplier applied to angular velocity on touch — small backspin
## that helps the ball feel "kicked" rather than "thrown". Pure visual
## (drag still dominates motion). 0 disables the spin entirely.
@export var touch_backspin_rad_s: float = 1.5

@export_group("Carry offset (S08-T01 / R02-F04)")
## Carry offset along the player's local forward (-Z) at REST (velocity 0).
## EA Pitch Notes (R02-F04): elite players keep the ball closer when slow,
## push it further when fast.
@export var carry_offset_min_m: float = 0.3
## Carry offset at FULL SPRINT speed. The interpolation uses
## `max_sprint_speed` as the denominator so walk speed produces an
## intermediate offset (~0.65 m at default 0.3/0.8 + 5.5/8.0 ratio),
## not the cap. Original R02-F04 lerp range was 0.3-0.5; bumped to 0.8
## here after playtest 2026-05-13 — the 0.5 cap was indistinguishable
## from walk because walk-speed already saturated the curve.
@export var carry_offset_max_m: float = 0.8
## Vertical offset from the capsule centre (always negative — capsule
## centre sits at y≈0.9, ball-target lands at ankle height).
@export var carry_offset_y_m: float = -0.7
## Ratio applied to the carrier's velocity when emitting a TOUCH release
## (S08-T02). Elite range from R02-F04 is 0.88-0.95; default 0.95.
## Unused in T01; declared here so T02 can land without further export
## reshuffling.
@export var ball_speed_ratio_on_touch: float = 0.95

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
## Last release kind — used by _assign_carrier to decide whether to
## arm a facing warp on pickup. TOUCH self-pickup must NOT warp
## (carrier chasing their own touch, ball moves AWAY from them).
var _last_release_kind: ReleaseKind = ReleaseKind.SHOOT


func _ready() -> void:
	_rebuild_team_order()


# ---- Public API ----------------------------------------------------------

func get_carrier() -> Player:
	return _carrier


func is_carried() -> bool:
	return _carrier != null


## Proxy for shoot / pass / touch triggers. Releases the ball and clears
## the carrier flag. SHOOT and PASS arm the post-release pickup lockout
## (anti re-grab safety from Sprint 7 fix2). TOUCH skips the lockout
## (touch interval ≤ lockout duration would deadlock the dribble).
func request_release(velocity: Vector3, angular: Vector3 = Vector3.ZERO,
		kind: ReleaseKind = ReleaseKind.SHOOT) -> void:
	if _carrier == null or ball == null:
		return
	if debug_log:
		print("[BallController] RELEASE (%s) by %s, |v|=%.2f m/s, |ω|=%.2f rad/s" % [
			ReleaseKind.keys()[kind], _carrier.name, velocity.length(), angular.length(),
		])
	_last_release_kind = kind
	_clear_carrier_flag()
	_carrier = null
	if kind != ReleaseKind.TOUCH:
		_pickup_lockout_remaining_s = post_release_lockout_s
	# Reset the touch timer so the next pickup starts fresh.
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
	else:
		_sync_carry_position()
		_tick_touch_cycle(delta)


## Touch-cycle dribble (R02-F05). While the carrier is moving above the
## min-speed gate, tick a timer; when it hits the speed-appropriate
## interval, emit a TOUCH release. Pure on-instance; tests drive it
## via explicit step(delta).
func _tick_touch_cycle(delta: float) -> void:
	if _carrier == null:
		return
	var carrier_speed: float = _carrier.velocity.length()
	if carrier_speed < touch_min_speed_m_s:
		_touch_timer_s = 0.0
		return
	_touch_timer_s += delta
	# Pick interval by speed regime — anything > max_walk_speed counts
	# as sprint cadence.
	var interval: float = touch_interval_walk_s
	if carrier_speed > _carrier.max_walk_speed:
		interval = touch_interval_sprint_s
	if _touch_timer_s >= interval:
		_emit_touch()
		_touch_timer_s = 0.0


## Emit a TOUCH release: ball gets the carrier's planar velocity scaled
## by `ball_speed_ratio_on_touch` plus a small backspin. Carrier will
## chase the ball and re-pickup automatically once within radius.
func _emit_touch() -> void:
	if _carrier == null or ball == null:
		return
	var planar: Vector3 = Vector3(_carrier.velocity.x, 0.0, _carrier.velocity.z)
	var touch_velocity: Vector3 = planar * ball_speed_ratio_on_touch
	var touch_angular: Vector3 = Vector3.ZERO
	if touch_backspin_rad_s > 0.0 and planar.length_squared() > 1.0e-4:
		# Backspin axis: (UP × forward_dir) — a touch grounder gets a
		# slight backwards roll like a real push pass. Magnitude small
		# enough that drag dominates motion.
		var dir: Vector3 = planar.normalized()
		touch_angular = Vector3.UP.cross(dir) * (-touch_backspin_rad_s)
	request_release(touch_velocity, touch_angular, ReleaseKind.TOUCH)


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
	# Speed-modulated forward offset (S08-D04 / R02-F04): walk → 0.3 m,
	# sprint → 0.5 m. Linear in carrier_speed/max_walk_speed, clamped at
	# the walk threshold so anything ≥ walk speed reads as "sprint" for
	# the offset curve.
	var offset_local: Vector3 = _compute_carry_offset_local(_carrier)
	# Use VisualRoot basis (S07-T06) so the ball follows the rendered
	# mesh, not the (always-identity) collision capsule.
	var world_offset: Vector3 = _carrier.get_visual_basis() * offset_local
	var target: Vector3 = _carrier.global_position + world_offset
	# CRITICAL: while the ball is KINEMATIC-frozen, `_integrate_forces` does
	# NOT run, so `teleport_to` (which stages _pending_teleport for the
	# integrator) silently no-ops. In KINEMATIC freeze the engine accepts
	# direct `global_position` writes — we use those instead. The pending
	# pipeline is only for unfrozen-launch flows.
	ball.global_position = target


## Player-local carry offset for the given carrier. Pure function — tests
## drive it directly with explicit Player state.
func _compute_carry_offset_local(carrier: Player) -> Vector3:
	# Use SPRINT speed as the denominator so walk speed produces an
	# intermediate offset (≈ 0.65 m with defaults), not the cap. The
	# Sprint 7 test fixture used max_walk; updated 2026-05-13 after
	# playtest reported "sprint feels same as walk".
	var max_speed: float = maxf(0.001, carrier.max_sprint_speed)
	var t: float = clampf(carrier.velocity.length() / max_speed, 0.0, 1.0)
	var z_offset: float = -lerpf(carry_offset_min_m, carry_offset_max_m, t)
	return Vector3(0.0, carry_offset_y_m, z_offset)


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
