class_name BallPhysics
extends RigidBody3D

## Custom-integrated ball.
##
## Sprint 1 scope: gravity + quadratic drag + (T03) restitution bounce.
## Sprint 2 will activate Magnus and knuckleball via `config.magnus_enabled`
## and `config.knuckle_enabled`. Sprint 3 will swap the constant-restitution
## bounce for the Cross-2002 model with spin transfer.
##
## Integration scheme: semi-implicit Euler with velocity-adaptive substepping
## (4 / 6 / 8 substeps in <15 / [15,25) / >=25 m/s regimes). See
## PHYSICS_LOG.md S01-A02 for rationale.
##
## The integrator is exposed as a *pure function* (`integrate_step_pure`)
## so the forward predictor (Sprint 2) and the GUT unit tests (T04) can
## simulate trajectories without spinning up a `PhysicsDirectBodyState3D`.

const SUBSTEPS_LOW: int = 4
const SUBSTEPS_MID: int = 6
const SUBSTEPS_HIGH: int = 8
const SPEED_THRESHOLD_MID: float = 15.0
const SPEED_THRESHOLD_HIGH: float = 25.0
const MIN_SPEED_FOR_DRAG: float = 0.001

# ---- Static world geometry (Sprint 1 axis-aligned containment) ------------
# Ground plane at y = 0. Perimeter walls form an AABB just outside the
# regulation pitch (105 x 68 m, half-extents 52.5 x 34) with a 5 m runoff.
# Sprint 5 will revisit when arbitrary obstacles enter the scene.
const GROUND_Y: float = 0.0
const FIELD_HALF_X: float = 52.5
const FIELD_HALF_Z: float = 34.0
const WALL_BUFFER: float = 5.0
const WALL_MAX_X: float = FIELD_HALF_X + WALL_BUFFER
const WALL_MAX_Z: float = FIELD_HALF_Z + WALL_BUFFER

# Below this normal-impact speed (m/s) we treat the contact as rolling /
# resting rather than a bounce, so we don't emit a `bounced` signal for
# every micro-jitter. Audio (Sprint 3) will use the same threshold.
const BOUNCE_SIGNAL_MIN_SPEED: float = 0.8

signal bounced(impact_speed: float, normal: Vector3, position: Vector3)

@export var config: PhysicsConfig
@export var initial_velocity: Vector3 = Vector3.ZERO
@export var initial_angular_velocity: Vector3 = Vector3.ZERO

## Debug-only visual scale applied to the MeshInstance3D, NOT to the
## collision shape. With a 42 m camera distance the real 11 cm ball is
## only ~7 px wide, which makes the spin axis impossible to read in the
## sandbox. The physics radius stays at `config.ball_radius` so all
## formulas remain correct; only the rendered mesh is enlarged.
## Set to 1.0 once a proper near-camera / zoom system is in place.
@export var debug_visual_scale: float = 1.0

var _current_substeps: int = SUBSTEPS_LOW


func _ready() -> void:
	if config == null:
		config = load("res://resources/PhysicsConfig.tres") as PhysicsConfig
		if config == null:
			push_error("BallPhysics: PhysicsConfig.tres not found")
			return
	custom_integrator = true
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	mass = config.ball_mass
	gravity_scale = 0.0
	_apply_debug_visual_scale()
	if initial_velocity != Vector3.ZERO:
		linear_velocity = initial_velocity
	if initial_angular_velocity != Vector3.ZERO:
		angular_velocity = initial_angular_velocity


func _apply_debug_visual_scale() -> void:
	if is_equal_approx(debug_visual_scale, 1.0):
		return
	var mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")
	if mesh == null:
		return
	mesh.scale = Vector3.ONE * debug_visual_scale


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	var dt: float = state.step
	var speed: float = state.linear_velocity.length()
	_current_substeps = compute_substeps(speed)
	var sub_dt: float = dt / float(_current_substeps)
	for i in _current_substeps:
		_integrate_substep(state, sub_dt)


func _integrate_substep(state: PhysicsDirectBodyState3D, sub_dt: float) -> void:
	var v: Vector3 = state.linear_velocity
	var p: Vector3 = state.transform.origin
	var step: Dictionary = integrate_step_pure(p, v, sub_dt)
	p = step.position
	v = step.velocity

	# Resolve static-world collision (ground + perimeter walls).
	var collision: Dictionary = resolve_static_collisions(p, v)
	if collision.collided:
		p = collision.position
		v = collision.velocity
		if collision.impact_speed >= BOUNCE_SIGNAL_MIN_SPEED:
			bounced.emit(collision.impact_speed, collision.normal, p)

	state.linear_velocity = v
	var t: Transform3D = state.transform
	t.origin = p

	# Angular kinematic update. Sprint 1 applies no torques, so spin is
	# constant unless modified externally; but with `custom_integrator=true`
	# Godot does NOT auto-rotate the transform from `angular_velocity`, we
	# must do it ourselves. Sprint 3 (Cross-2002) will start *modifying*
	# angular_velocity at bounces; for now we just integrate the kinematic
	# rotation so the mesh visibly spins.
	var omega: Vector3 = state.angular_velocity
	if omega.length_squared() > 1e-12:
		var axis: Vector3 = omega.normalized()
		var angle: float = omega.length() * sub_dt
		t.basis = Basis(axis, angle) * t.basis
	state.transform = t


## Resolve collisions against the (axis-aligned) static world: ground plane
## and the four perimeter walls. Returns a Dictionary with keys:
##   collided     (bool)
##   position     (Vector3, corrected to keep the ball outside the surface)
##   velocity     (Vector3, after bounce + tangential friction)
##   impact_speed (float, |v_normal| at impact, used for audio + telemetry)
##   normal       (Vector3, surface normal of the dominant contact)
## Pure function — no engine state, safe to reuse in tests and predictor.
func resolve_static_collisions(p_in: Vector3, v_in: Vector3) -> Dictionary:
	var r: float = config.ball_radius
	var p: Vector3 = p_in
	var v: Vector3 = v_in
	var collided: bool = false
	var impact_speed: float = 0.0
	var impact_normal: Vector3 = Vector3.ZERO

	# Ground (normal = +Y)
	if p.y < GROUND_Y + r and v.y < 0.0:
		var vn: float = -v.y
		if vn > impact_speed:
			impact_speed = vn
			impact_normal = Vector3.UP
		p.y = GROUND_Y + r
		v = _bounce_velocity(v, Vector3.UP)
		collided = true

	# East wall (x = +WALL_MAX_X, normal = -X)
	if p.x > WALL_MAX_X - r and v.x > 0.0:
		var vn: float = v.x
		if vn > impact_speed:
			impact_speed = vn
			impact_normal = Vector3.LEFT
		p.x = WALL_MAX_X - r
		v = _bounce_velocity(v, Vector3.LEFT)
		collided = true

	# West wall (x = -WALL_MAX_X, normal = +X)
	if p.x < -WALL_MAX_X + r and v.x < 0.0:
		var vn: float = -v.x
		if vn > impact_speed:
			impact_speed = vn
			impact_normal = Vector3.RIGHT
		p.x = -WALL_MAX_X + r
		v = _bounce_velocity(v, Vector3.RIGHT)
		collided = true

	# North wall (z = -WALL_MAX_Z, normal = +Z = Vector3.BACK)
	if p.z < -WALL_MAX_Z + r and v.z < 0.0:
		var vn: float = -v.z
		if vn > impact_speed:
			impact_speed = vn
			impact_normal = Vector3.BACK
		p.z = -WALL_MAX_Z + r
		v = _bounce_velocity(v, Vector3.BACK)
		collided = true

	# South wall (z = +WALL_MAX_Z, normal = -Z = Vector3.FORWARD)
	if p.z > WALL_MAX_Z - r and v.z > 0.0:
		var vn: float = v.z
		if vn > impact_speed:
			impact_speed = vn
			impact_normal = Vector3.FORWARD
		p.z = WALL_MAX_Z - r
		v = _bounce_velocity(v, Vector3.FORWARD)
		collided = true

	return {
		"collided": collided,
		"position": p,
		"velocity": v,
		"impact_speed": impact_speed,
		"normal": impact_normal,
	}


## Reflect a velocity across a plane with `normal` (unit, pointing AWAY
## from the surface). Normal component is multiplied by `-e`, tangential
## component is dampened by `(1 - mu)`.
## Sprint 1 uses constant `restitution_base` and `friction`. Sprint 3 will
## swap these for the Cross-2002 model with velocity-dependent restitution
## and explicit spin transfer.
func _bounce_velocity(v: Vector3, normal: Vector3) -> Vector3:
	var v_n_scalar: float = v.dot(normal)
	var v_normal: Vector3 = normal * v_n_scalar
	var v_tangent: Vector3 = v - v_normal
	var v_normal_new: Vector3 = -config.restitution_base * v_normal
	var v_tangent_new: Vector3 = v_tangent * (1.0 - config.friction)
	return v_normal_new + v_tangent_new


## Pure-function integrator. Given a position/velocity, returns the next
## position/velocity after `sub_dt` seconds. No side effects, no engine
## state. Used by tests and by the forward predictor.
func integrate_step_pure(position: Vector3, velocity: Vector3, sub_dt: float) -> Dictionary:
	var f: Vector3 = compute_force(velocity)
	var a: Vector3 = f / config.ball_mass
	# semi-implicit Euler: velocity first, then position with the new velocity
	var v_new: Vector3 = velocity + a * sub_dt
	var p_new: Vector3 = position + v_new * sub_dt
	return {"position": p_new, "velocity": v_new}


## Sum of all active forces on the ball at the given velocity.
## Sprint 1: gravity + drag. Sprint 2 will add Magnus + knuckle perturbation.
func compute_force(velocity: Vector3) -> Vector3:
	return _gravity_force() + _drag_force(velocity)


func _gravity_force() -> Vector3:
	return Vector3(0.0, -config.gravity, 0.0) * config.ball_mass


func _drag_force(velocity: Vector3) -> Vector3:
	var speed: float = velocity.length()
	if speed < MIN_SPEED_FOR_DRAG:
		return Vector3.ZERO
	var area: float = PI * config.ball_radius * config.ball_radius
	var magnitude: float = 0.5 * config.air_density * config.drag_coeff * area * speed * speed
	return -velocity.normalized() * magnitude


static func compute_substeps(speed: float) -> int:
	if speed < SPEED_THRESHOLD_MID:
		return SUBSTEPS_LOW
	if speed < SPEED_THRESHOLD_HIGH:
		return SUBSTEPS_MID
	return SUBSTEPS_HIGH


func get_current_substeps() -> int:
	return _current_substeps


## Convenience for tests / launcher: theoretical terminal velocity for a
## freely falling ball in the current air density (no spin, no walls).
func terminal_velocity() -> float:
	var area: float = PI * config.ball_radius * config.ball_radius
	var k: float = 0.5 * config.air_density * config.drag_coeff * area
	return sqrt(config.ball_mass * config.gravity / k)
