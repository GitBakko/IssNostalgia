class_name BallLauncher
extends Node3D

## Parametric launcher for the sandbox.
##
## Sprint 1 (T05) exposes three keyboard launches (vertical, horizontal,
## reset) plus a "click the ground" mouse mode. Magnus and knuckle remain
## off this sprint; the spin set here only drives the kinematic rotation
## of the mesh, not curved trajectories.
## Sprint 2 will hand the launcher the predicted trajectory overlay and a
## proper sidespin / topspin / rifling decomposition.

@export var spawn_position: Vector3 = Vector3(0.0, 0.11, 0.0)  ## resting on ground
@export var ball_path: NodePath

@export_group("Defaults")
@export var vertical_speed: float = 15.0          ## m/s, upward
@export var vertical_spin_z: float = 4.0          ## rad/s, around Z so the
                                                  ## pentagons visibly rotate
@export var horizontal_speed: float = 20.0        ## m/s, along +X
@export var horizontal_topspin: float = 6.0       ## rad/s, around -Z so the
                                                  ## ball "rolls forward"
@export var ground_click_speed: float = 25.0      ## m/s magnitude
@export var ground_click_arc_height: float = 5.0  ## peak height above spawn

var _ball: BallPhysics


func _ready() -> void:
	_ball = _resolve_ball()
	if _ball == null:
		push_warning("BallLauncher: target ball not found (set ball_path or place a sibling 'Ball').")


func _resolve_ball() -> BallPhysics:
	if not ball_path.is_empty():
		return get_node_or_null(ball_path) as BallPhysics
	var sibling: Node = get_parent().get_node_or_null("Ball") if get_parent() else null
	return sibling as BallPhysics


## Hard reset: schedule a teleport + zero velocity / spin. The change
## is committed at the next physics tick by `BallPhysics._integrate_forces`
## (Godot best practice — never write RigidBody3D state directly).
func reset_ball() -> void:
	if _ball == null:
		return
	_ball.teleport_to(spawn_position)
	_ball.apply_launch_state(Vector3.ZERO, Vector3.ZERO)
	print("[launcher] reset to %s" % spawn_position)


## Primitive launch: stage linear + angular velocity for the next
## physics step. Ball stays at its current position. Resets the
## knuckle noise clock so the shot replays deterministically.
func launch(velocity: Vector3, spin: Vector3 = Vector3.ZERO) -> void:
	if _ball == null:
		return
	_ball.apply_launch_state(velocity, spin)
	if _ball.has_method("reset_knuckle_clock"):
		_ball.reset_knuckle_clock()
	print("[launcher] launch from %s v=%s |v|=%.2f m/s spin=%s |w|=%.2f rad/s" % [
		_ball.global_position, velocity, velocity.length(), spin, spin.length(),
	])


## Decompose a per-axis spin specification (topspin, sidespin, rifling)
## around the launch direction into a world-space ω vector.
##   topspin >0  → top of the ball rolls FORWARD along the direction
##                 of motion, producing a downward Magnus force (the
##                 ball dives — exactly what a "rasoterra forte" wants).
##                 <0 = backspin → lifts the ball.
##   sidespin >0 → rotation around world UP, curves the ball laterally
##                 (Magnus = ω̂ × v̂ → for +X motion the curve is -Z).
##   rifling >0  → rotation around the direction of motion itself
##                 (no Magnus contribution; pure visual rifling).
##
## Right-hand rule sanity check: for `dir = +X`,
## `top_axis = UP.cross(dir) = (0,1,0) × (1,0,0) = (0,0,-1)`. Positive
## topspin → ω = (0, 0, -topspin), Magnus = (0,0,-1) × (1,0,0) = (0,-1,0)
## = DOWN, which is the textbook topspin behaviour.
static func compose_spin(direction: Vector3, topspin: float,
		sidespin: float, rifling: float = 0.0) -> Vector3:
	var dir: Vector3 = direction.normalized()
	var top_axis: Vector3 = Vector3.UP.cross(dir)
	if top_axis.length_squared() < 1e-6:
		top_axis = Vector3.BACK   # fallback when dir is vertical
	top_axis = top_axis.normalized()
	return top_axis * topspin + Vector3.UP * sidespin + dir * rifling


## Launch at a given elevation angle (degrees) above the horizontal,
## with a world-space spin vector. Used by every macro shot below.
func launch_at_angle(direction: Vector3, speed: float,
		elevation_deg: float, spin: Vector3 = Vector3.ZERO) -> void:
	var dir: Vector3 = direction.normalized()
	var rad: float = deg_to_rad(elevation_deg)
	var v: Vector3 = dir * (speed * cos(rad)) + Vector3.UP * (speed * sin(rad))
	launch(v, spin)


# ---- Macro shots (Sprint 2 calibration targets, round-2 7.3) -------------

## Tiro a giro toward `direction`. 25 m/s @ 15°, sidespin 8 rad/s,
## light topspin 2 rad/s. Target: ~3-4 m of lateral curve over 20 m of flight.
func launch_curve_shot(direction: Vector3 = Vector3.RIGHT) -> void:
	var spin: Vector3 = compose_spin(direction, 2.0, 8.0, 0.0)
	launch_at_angle(direction, 25.0, 15.0, spin)


## Foglia morta toward `direction`. 22 m/s @ 20°, backspin 6 rad/s,
## mild sidespin 3 rad/s. Trajectory drops sharply in the last 5 m.
func launch_dead_leaf(direction: Vector3 = Vector3.RIGHT) -> void:
	var spin: Vector3 = compose_spin(direction, -6.0, 3.0, 0.0)
	launch_at_angle(direction, 22.0, 20.0, spin)


## Rasoterra forte toward `direction`. 30 m/s @ 1° low arc, topspin 4 rad/s.
## The 1° elevation keeps the launch flat; topspin gives a downward
## Magnus force that helps the ball glue to the surface.
func launch_grounder_topspin(direction: Vector3 = Vector3.RIGHT) -> void:
	var spin: Vector3 = compose_spin(direction, 4.0, 0.0, 0.0)
	launch_at_angle(direction, 30.0, 1.0, spin)


## Rasoterra medio toward `direction`. 15 m/s @ 3°, topspin 4 rad/s.
## Skips slightly higher than the strong variant but stays under the
## 6 cm ceiling locked in `test_rasoterra_levels.gd`.
func launch_grounder_medium(direction: Vector3 = Vector3.RIGHT) -> void:
	var spin: Vector3 = compose_spin(direction, 4.0, 0.0, 0.0)
	launch_at_angle(direction, 15.0, 3.0, spin)


## Rasoterra debole toward `direction`. 10 m/s @ 1°, topspin 4 rad/s.
## Slow enough to actually roll through wet patches and feel the
## friction drop — this is the variant to use to validate per-zone
## surfaces visually.
func launch_grounder_weak(direction: Vector3 = Vector3.RIGHT) -> void:
	var spin: Vector3 = compose_spin(direction, 4.0, 0.0, 0.0)
	launch_at_angle(direction, 10.0, 1.0, spin)


## Knuckleball toward `direction`. **30 m/s @ 6°**, near-zero spin.
##
## Trajectory intent (S05-A06): flat low parabola — the ball rises
## briefly, "floats" through the drag-crisis zone (14-24 m/s, where
## Cd ≈ 0.18 makes it look like it's hanging in the air), then drops
## sharply when it exits the crisis and the vertical-down knuckle
## flip kicks in. Apex sits at ~50 cm, total flight ~1.4 s. NOT a
## lob — knuckle free kicks like Ronaldo / Pirlo launch low and
## look "floaty" mid-air, then dive.
##
## Special skill — only this launch path arms the knuckle force;
## every other launcher clears it via `reset_knuckle_clock`.
func launch_knuckle(direction: Vector3 = Vector3.RIGHT) -> void:
	launch_at_angle(direction, 30.0, 6.0, Vector3.ZERO)
	if _ball != null:
		_ball.set_knuckle_active(true)


func launch_vertical(speed: float = -1.0, spin_z: float = INF) -> void:
	var v: float = speed if speed > 0.0 else vertical_speed
	var sz: float = vertical_spin_z if spin_z == INF else spin_z
	launch(Vector3(0.0, v, 0.0), Vector3(0.0, 0.0, sz))


func launch_horizontal(speed: float = -1.0, direction: Vector3 = Vector3.RIGHT,
		topspin: float = INF) -> void:
	var v: float = speed if speed > 0.0 else horizontal_speed
	var ts: float = horizontal_topspin if topspin == INF else topspin
	var dir: Vector3 = direction.normalized()
	# Topspin axis: perpendicular to direction in the horizontal plane.
	# For dir = +X, topspin axis = -Z so the ball rotates "forward" in flight.
	var spin_axis: Vector3 = Vector3.UP.cross(dir).normalized()
	launch(dir * v, spin_axis * ts)


## Aim the ball at `target_xz` (point on the ground plane). The arc
## height scales with launch distance (clamped to `[0.5 m, 6 m]`); the
## horizontal speed is then iteratively refined against the live
## integrator so the ball actually lands on the click.
##
## Spin is set to ZERO. A naïve "topspin lob" (S02-A12 fallback) caused
## Magnus to pull the ball backwards during descent: with ω̂ = (0,0,-1)
## and v̂ pointing down-and-forward, ω̂ × v̂ produces a negative-X
## component, decelerating and even reversing forward motion. A
## spinless lob lands cleanly on the click.
##
## Why iterative (S05-fix): at long range the vacuum solution overshoots
## by 10-30%. Horizontal speed enters the drag-crisis band (Cd≈0.18 for
## 14-24 m/s), so actual deceleration is far weaker than a single fixed
## undershoot factor can compensate. We bracket v_horizontal by running
## `predict_forward` (the same integrator the live ball uses), measuring
## the simulated landing distance, and rescaling. Converges in 3-4 iters.
func launch_to_point(target_xz: Vector3, _speed_unused: float = -1.0,
		arc_height_override: float = -1.0) -> void:
	if _ball == null:
		return
	var origin: Vector3 = _ball.global_position
	var horizontal: Vector3 = Vector3(target_xz.x - origin.x, 0.0,
		target_xz.z - origin.z)
	var dist: float = horizontal.length()
	if dist < 0.001:
		return
	var dir: Vector3 = horizontal / dist
	var h: float = arc_height_override if arc_height_override > 0.0 else clampf(dist * 0.25, 0.5, 6.0)
	var v_vertical: float = sqrt(2.0 * 9.81 * h)
	var t_flight: float = 2.0 * v_vertical / 9.81
	var v_horizontal: float = dist / t_flight   # vacuum guess
	print("[lob solver] origin=%s target=%s dist=%.2f h=%.2f vy=%.2f v_h_vacuum=%.2f knuckle_was=%s" % [
		origin, target_xz, dist, h, v_vertical, v_horizontal, _ball.is_knuckle_active()])
	for it in 4:
		var v0: Vector3 = dir * v_horizontal + Vector3.UP * v_vertical
		var landing: float = _simulated_landing_distance(origin, v0)
		print("[lob solver] iter %d v_h=%.3f predicted_landing=%.3f ratio=%.3f" % [
			it, v_horizontal, landing, dist / landing if landing > 0.1 else 0.0])
		if landing <= 0.5:
			break
		var ratio: float = dist / landing
		if absf(ratio - 1.0) < 0.01:
			break
		v_horizontal *= ratio
	print("[lob solver] FINAL v_h=%.3f vy=%.3f → launching" % [v_horizontal, v_vertical])
	launch(dir * v_horizontal + Vector3.UP * v_vertical, Vector3.ZERO)


## Drag-aware landing distance for the iterative lob solver. Uses
## `BallPhysics.predict_forward` so gravity, quadratic drag, Magnus and
## the drag-crisis Cd(v) curve all match the live integrator exactly.
## Returns the horizontal (XZ) distance from `p0` to the first descent
## crossing of ground level; falls back to the last simulated point if
## the trajectory hasn't landed within ~5 s.
##
## Knuckle state is forced OFF for the duration of the prediction:
## `_knuckle_active_for_shot` is sticky from the previous shot, so a
## prior KEY_4 launch would otherwise inject a stall-flip lateral force
## into the simulation, shorten the simulated landing, and trick the
## iterative solver into massively overshooting the click on the
## subsequent (spinless) live launch. The flag is restored before
## returning so the next live shot's intent is preserved.
func _simulated_landing_distance(p0: Vector3, v0: Vector3) -> float:
	if _ball == null:
		return 0.0
	const SUB_DT: float = 1.0 / 240.0
	const STEPS: int = 1200
	var prev_knuckle: bool = _ball.is_knuckle_active()
	_ball.set_knuckle_active(false)
	var positions: PackedVector3Array = _ball.predict_forward(
		p0, v0, Vector3.ZERO, 0.0, STEPS, SUB_DT)
	_ball.set_knuckle_active(prev_knuckle)
	var ground_y: float = p0.y
	var ascended: bool = false
	for i in STEPS:
		var p: Vector3 = positions[i]
		if not ascended:
			if p.y > ground_y + 0.3:
				ascended = true
			continue
		if p.y <= ground_y + 0.05:
			return Vector2(p.x - p0.x, p.z - p0.z).length()
	var p_end: Vector3 = positions[STEPS - 1]
	return Vector2(p_end.x - p0.x, p_end.z - p0.z).length()
