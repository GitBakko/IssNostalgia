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
	var next: Dictionary = integrate_step_pure(p, v, sub_dt)
	state.linear_velocity = next.velocity
	var t: Transform3D = state.transform
	t.origin = next.position
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
