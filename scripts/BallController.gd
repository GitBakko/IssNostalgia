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
## Carry offset in player-local space. 0.5 m forward, 0.2 m below the
## capsule centre — approximates the player's feet (S07-D03 / R02-F06).
const CARRY_OFFSET_LOCAL: Vector3 = Vector3(0.0, -0.2, 0.5)

# ---- Exports -------------------------------------------------------------
@export var ball: BallPhysics
## All TeamControllers participating in this match. The order is
## significant for the tie-breaker — controllers are sorted by
## `is_human` (true first) at _ready.
@export var teams: Array[TeamController] = []

# ---- Runtime state -------------------------------------------------------
var _carrier: Player = null
var _ordered_teams: Array[TeamController] = []


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
	_clear_carrier_flag()
	_carrier = null
	ball.release(velocity, angular)


## Pure-on-instance step. Tests drive this directly with explicit player
## / ball positions instead of going through `_physics_process`.
func step(_delta: float) -> void:
	if ball == null:
		return
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
	# Gate 1: ball must be slow enough to grab.
	if ball.linear_velocity.length_squared() > PICKUP_MAX_BALL_SPEED_SQ:
		return
	# Gate 2: ball must not already be possessed (defensive — set_possessed
	# would have set _carrier above, but a bare BallPhysics.set_possessed
	# call from a test would skip our flag).
	if ball.is_possessed():
		return
	var ball_pos: Vector3 = ball.global_position
	for team in _ordered_teams:
		for p in team.players:
			if p == null or p.is_goalkeeper:
				continue  ## Sprint 7 GK doesn't pick up — Sprint 8 logic
			var dx: float = p.global_position.x - ball_pos.x
			var dz: float = p.global_position.z - ball_pos.z
			if dx * dx + dz * dz <= PICKUP_RADIUS_SQ:
				_assign_carrier(p)
				return  ## tie-breaker: first hit wins (humans iterated first)


func _sync_carry_position() -> void:
	if _carrier == null:
		return
	# Player-local carry offset → world. basis * vec rotates the offset
	# with the player so the ball stays "in front of" them as they turn.
	var world_offset: Vector3 = _carrier.transform.basis * CARRY_OFFSET_LOCAL
	var target: Vector3 = _carrier.global_position + world_offset
	# Stage via teleport_to so the change goes through the integrator
	# pipeline (consistent with how reset / debug-move write the ball).
	ball.teleport_to(target)


func _assign_carrier(player: Player) -> void:
	if _carrier != null:
		_clear_carrier_flag()
	_carrier = player
	_carrier.has_ball = true
	ball.set_possessed(player)


func _clear_carrier_flag() -> void:
	if _carrier != null:
		_carrier.has_ball = false
