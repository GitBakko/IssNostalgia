class_name PassingController
extends Node

## Sprint 7 T04 — E key auto-target pass.
##
## Selects a teammate in the active player's forward 90° cone (R03-F05
## dot > 0.707), computes the lob arc via the existing
## `BallLauncher.compute_velocity_to_point` (R03-F06 — the same iterative
## drag-aware solver the LMB sandbox lob uses), overrides spin by distance
## (S07-D06 / S06-D28: backspin grounder < 8 m, topspin lob > 15 m, zero
## in-between), and routes the release through `BallController.request_release`
## so the freeze toggle stays consistent.
##
## Public API:
##   try_pass()                      — explicit-args entry (used by tests
##                                      AND by `_physics_process`)
##   select_pass_target(active)      — returns Player or null
##   compute_pass_target_position(...) — Vector3 in world space; falls
##                                      back to "10 m forward" when the
##                                      cone is empty
##
## Signal:
##   pass_fired(target_position, distance, target_player)

# ---- Tunables ------------------------------------------------------------
@export var team_controller: TeamController
@export var ball_controller: BallController
@export var ball_launcher: BallLauncher

## Print every try_pass with reject reason. Off by default.
@export var debug_log: bool = false

@export_group("Target selection")
## cos(45°) ≈ 0.707 — R03-F05 cone half-angle. Teammates with a forward
## projection above this are eligible passes. Tighter values (0.866 = 30°)
## make the player's facing more demanding; looser (0.5 = 60°) is too lax.
@export var cone_dot_threshold: float = 0.707
## When no teammate sits in the cone, the pass goes to a fallback point
## this many metres in front of the active player.
@export var fallback_pass_distance_m: float = 10.0

@export_group("Spin (S07-D06 / S06-D28)")
@export var grounder_distance_max_m: float = 8.0
@export var lob_distance_min_m: float = 15.0
@export var grounder_backspin_rad_s: float = 3.0
@export var lob_topspin_rad_s: float = 4.0

@export_group("Animation")
## Per S06 spec A2 — auto-switch is gated for 100 ms after a pass fires.
@export var pass_anim_duration_s: float = 0.1

# ---- Signals -------------------------------------------------------------
signal pass_fired(target_position: Vector3, distance: float, target_player: Player)

# ---- Runtime state -------------------------------------------------------
var _pass_anim_remaining_s: float = 0.0


# ---- Public API ----------------------------------------------------------

## Attempt a pass NOW. Returns true on success, false on rejection
## (no carrier, no active player). Tests drive this directly; production
## `_physics_process` calls it on a buffered E press.
func try_pass() -> bool:
	if ball_controller == null or team_controller == null or ball_launcher == null:
		if debug_log: print("[PassingController] reject: missing wiring")
		return false
	var active: Player = _active_player()
	if active == null:
		if debug_log: print("[PassingController] reject: no active player")
		return false
	if ball_controller.get_carrier() != active:
		if debug_log:
			var carrier_name: String = "<none>" if ball_controller.get_carrier() == null \
				else ball_controller.get_carrier().name
			print("[PassingController] reject: active %s != carrier %s" % [active.name, carrier_name])
		return false

	var target_player: Player = select_pass_target(active)
	var target_pos: Vector3 = compute_pass_target_position(active, target_player)
	var dir: Vector3 = _xz_dir(active.global_position, target_pos)
	var distance: float = _xz_distance(active.global_position, target_pos)
	if distance < 0.5:
		if debug_log: print("[PassingController] reject: degenerate distance %.2f" % distance)
		return false  ## degenerate — can't pass to yourself

	var velocity: Vector3 = ball_launcher.compute_velocity_to_point(target_pos)
	if velocity == Vector3.ZERO:
		if debug_log: print("[PassingController] reject: launcher returned ZERO velocity")
		return false
	if debug_log:
		var tname: String = "<fallback>" if target_player == null else target_player.name
		print("[PassingController] PASS to %s @ d=%.2fm |v|=%.2f m/s" % [tname, distance, velocity.length()])

	var spin: Vector3 = _resolve_pass_spin(dir, distance)
	ball_controller.request_release(velocity, spin)

	# Pass-anim auto-switch gate (S06 spec A2)
	_pass_anim_remaining_s = pass_anim_duration_s
	if team_controller.controller != null:
		team_controller.controller.is_passing = true
	active.state = Player.State.PASSING

	pass_fired.emit(target_pos, distance, target_player)
	return true


## Select a teammate in the 90° forward cone of `active`. Returns the
## NEAREST eligible teammate, or null if the cone is empty.
##   - excludes the active player itself
##   - excludes the goalkeeper (Sprint 7 keeps the GK out of pass targets;
##     Sprint 8 may revisit)
##   - eligibility = `forward.dot(dir_to_t) > cone_dot_threshold`
func select_pass_target(active: Player) -> Player:
	if team_controller == null:
		return null
	var facing: Vector3 = -active.transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 1.0e-4:
		facing = Vector3.FORWARD
	else:
		facing = facing.normalized()
	var best: Player = null
	var best_dist_sq: float = INF
	for p in team_controller.players:
		if p == null or p == active or p.is_goalkeeper:
			continue
		var to_p: Vector3 = p.global_position - active.global_position
		to_p.y = 0.0
		var d_sq: float = to_p.length_squared()
		if d_sq < 1.0e-4:
			continue
		var dir_to: Vector3 = to_p / sqrt(d_sq)
		if facing.dot(dir_to) <= cone_dot_threshold:
			continue
		if d_sq < best_dist_sq:
			best_dist_sq = d_sq
			best = p
	return best


## Compute the world-space target the pass should aim at. Uses the
## selected teammate's position; falls back to a point `fallback_pass_distance_m`
## metres ahead of the active player's facing when the cone is empty.
func compute_pass_target_position(active: Player, target: Player) -> Vector3:
	if target != null:
		return target.global_position
	var facing: Vector3 = -active.transform.basis.z
	facing.y = 0.0
	if facing.length_squared() < 1.0e-4:
		facing = Vector3.FORWARD
	else:
		facing = facing.normalized()
	return active.global_position + facing * fallback_pass_distance_m


# ---- Lifecycle -----------------------------------------------------------

func _physics_process(delta: float) -> void:
	if team_controller == null:
		return
	# Tick down the pass anim — releases the auto-switch gate.
	if _pass_anim_remaining_s > 0.0:
		_pass_anim_remaining_s -= delta
		if _pass_anim_remaining_s <= 0.0:
			_pass_anim_remaining_s = 0.0
			if team_controller.controller != null:
				team_controller.controller.is_passing = false
			var p: Player = _active_player()
			if p != null and p.state == Player.State.PASSING:
				p.state = Player.State.IDLE
	# Trigger on a buffered E press from the team's controller.
	if team_controller.controller == null:
		return
	if team_controller.controller.consume_buffered(&"pass_ball"):
		try_pass()


# ---- Internal -----------------------------------------------------------

func _active_player() -> Player:
	if team_controller == null or team_controller.controller == null:
		return null
	return team_controller.controller.player


func _resolve_pass_spin(dir: Vector3, distance: float) -> Vector3:
	# S07-D06 / S06-D28 / R03-F05:
	#   distance < 8 m   → backspin grounder (compose_spin topspin = -3)
	#   distance > 15 m  → topspin lob       (compose_spin topspin = +4)
	#   else             → ZERO
	if distance < grounder_distance_max_m:
		return BallLauncher.compose_spin(dir, -grounder_backspin_rad_s, 0.0, 0.0)
	if distance > lob_distance_min_m:
		return BallLauncher.compose_spin(dir, lob_topspin_rad_s, 0.0, 0.0)
	return Vector3.ZERO


static func _xz_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


static func _xz_dir(from: Vector3, to: Vector3) -> Vector3:
	var d: Vector3 = Vector3(to.x - from.x, 0.0, to.z - from.z)
	if d.length_squared() < 1.0e-6:
		return Vector3.FORWARD
	return d.normalized()
