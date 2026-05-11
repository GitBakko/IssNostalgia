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

# Normal-impact speed cut-off (m/s) that separates a real bounce
# from a soft / resting contact.
#   |v_n| >= threshold  → bounce: reflect normal × (-e), dampen tangent × (1-μ)
#                          and emit the `bounced` signal
#   |v_n| <  threshold  → soft contact: kill the normal component, leave the
#                          tangent untouched (rolling friction handles it
#                          continuously inside _integrate_substep)
const BOUNCE_SIGNAL_MIN_SPEED: float = 0.8

# A ball is considered "rolling on the ground" — and therefore subject to
# rolling resistance — when it sits within this height tolerance of the
# resting altitude (ground + radius) AND its vertical speed is below the
# vertical-rolling tolerance. Both are kept small so that a ball mid-bounce
# is never treated as rolling.
const ROLLING_HEIGHT_TOL: float = 5e-3   # m above resting altitude
const ROLLING_VY_TOL: float = 0.5        # m/s

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
var _sim_time: float = 0.0
var _knuckle_noise_a: FastNoiseLite
var _knuckle_noise_b: FastNoiseLite


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
	_init_knuckle_noise()
	if initial_velocity != Vector3.ZERO:
		linear_velocity = initial_velocity
	if initial_angular_velocity != Vector3.ZERO:
		angular_velocity = initial_angular_velocity


func _init_knuckle_noise() -> void:
	_knuckle_noise_a = FastNoiseLite.new()
	_knuckle_noise_a.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_knuckle_noise_a.seed = config.knuckle_seed
	_knuckle_noise_a.frequency = config.knuckle_noise_frequency
	_knuckle_noise_b = FastNoiseLite.new()
	_knuckle_noise_b.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_knuckle_noise_b.seed = config.knuckle_seed + 1
	_knuckle_noise_b.frequency = config.knuckle_noise_frequency


## Resets the knuckle noise streams to a known starting time. Useful for
## the launcher (every shot replays from t=0 of its own noise channel)
## and for unit tests.
func reset_knuckle_clock() -> void:
	_sim_time = 0.0


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
	_sim_time += sub_dt
	var v: Vector3 = state.linear_velocity
	var p: Vector3 = state.transform.origin
	var omega: Vector3 = state.angular_velocity
	var step: Dictionary = integrate_step_pure(p, v, sub_dt, omega)
	p = step.position
	v = step.velocity

	# Knuckleball perturbation. Time-dependent (Simplex noise), so it
	# lives outside `compute_force` and gets applied as a velocity delta.
	if config.knuckle_enabled:
		v += knuckle_acceleration(state.linear_velocity, omega, _sim_time) * sub_dt

	# Resolve static-world collision (ground + perimeter walls).
	var collision: Dictionary = resolve_static_collisions(p, v)
	if collision.collided:
		p = collision.position
		v = collision.velocity
		if collision.impact_speed >= BOUNCE_SIGNAL_MIN_SPEED:
			bounced.emit(collision.impact_speed, collision.normal, p)

	# Rolling resistance (continuous, ground-contact only).
	v = apply_rolling_resistance(p, v, sub_dt)

	state.linear_velocity = v
	var t: Transform3D = state.transform
	t.origin = p

	# Angular kinematic update. Sprint 1 applies no torques, so spin is
	# constant unless modified externally; but with `custom_integrator=true`
	# Godot does NOT auto-rotate the transform from `angular_velocity`, we
	# must do it ourselves. Sprint 3 (Cross-2002) will start *modifying*
	# angular_velocity at bounces; for now we just integrate the kinematic
	# rotation so the mesh visibly spins.
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
		v = _resolve_contact(v, Vector3.UP, vn)
		collided = true

	# East wall (x = +WALL_MAX_X, normal = -X)
	if p.x > WALL_MAX_X - r and v.x > 0.0:
		var vn: float = v.x
		if vn > impact_speed:
			impact_speed = vn
			impact_normal = Vector3.LEFT
		p.x = WALL_MAX_X - r
		v = _resolve_contact(v, Vector3.LEFT, vn)
		collided = true

	# West wall (x = -WALL_MAX_X, normal = +X)
	if p.x < -WALL_MAX_X + r and v.x < 0.0:
		var vn: float = -v.x
		if vn > impact_speed:
			impact_speed = vn
			impact_normal = Vector3.RIGHT
		p.x = -WALL_MAX_X + r
		v = _resolve_contact(v, Vector3.RIGHT, vn)
		collided = true

	# North wall (z = -WALL_MAX_Z, normal = +Z = Vector3.BACK)
	if p.z < -WALL_MAX_Z + r and v.z < 0.0:
		var vn: float = -v.z
		if vn > impact_speed:
			impact_speed = vn
			impact_normal = Vector3.BACK
		p.z = -WALL_MAX_Z + r
		v = _resolve_contact(v, Vector3.BACK, vn)
		collided = true

	# South wall (z = +WALL_MAX_Z, normal = -Z = Vector3.FORWARD)
	if p.z > WALL_MAX_Z - r and v.z > 0.0:
		var vn: float = v.z
		if vn > impact_speed:
			impact_speed = vn
			impact_normal = Vector3.FORWARD
		p.z = WALL_MAX_Z - r
		v = _resolve_contact(v, Vector3.FORWARD, vn)
		collided = true

	return {
		"collided": collided,
		"position": p,
		"velocity": v,
		"impact_speed": impact_speed,
		"normal": impact_normal,
	}


## Resolve a single contact against a plane.
##   `normal`         — unit vector pointing AWAY from the surface
##   `impact_speed`   — |v_normal| BEFORE the contact (always positive)
## For impact_speed >= BOUNCE_SIGNAL_MIN_SPEED we treat this as a real
## bounce and apply `_bounce_velocity` (normal × -e, tangent × (1-μ)).
## For softer / resting contacts we only kill the normal component; the
## tangential component is preserved here and decayed continuously by
## `apply_rolling_resistance` in the next substep. This is what fixes
## the unrealistically fast horizontal slow-down that showed up the
## first time T05 was tested with the H key.
func _resolve_contact(v: Vector3, normal: Vector3, impact_speed: float) -> Vector3:
	if impact_speed >= BOUNCE_SIGNAL_MIN_SPEED:
		return _bounce_velocity(v, normal)
	# Soft contact: cancel the incoming normal component only.
	var v_n_scalar: float = v.dot(normal)
	return v - normal * v_n_scalar


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


## Continuous rolling resistance. Applies an opposing-to-motion deceleration
## of `μ_r · g` to the horizontal velocity ONLY when the ball is in ground
## contact at near-zero vertical speed. Pure function: takes (position,
## velocity, sub_dt) and returns the new velocity.
##
## This is the right place for the slow-down that real grass produces on a
## rolling soccer ball; the per-bounce tangential `friction` term only fires
## on hard bounces (slip loss at impact), preventing the compounding
## per-substep dampening that made horizontal launches die unrealistically
## fast.
func apply_rolling_resistance(p: Vector3, v: Vector3, sub_dt: float) -> Vector3:
	if config.rolling_friction_coeff <= 0.0:
		return v
	var r: float = config.ball_radius
	if p.y > GROUND_Y + r + ROLLING_HEIGHT_TOL:
		return v
	if absf(v.y) > ROLLING_VY_TOL:
		return v
	var v_t: Vector3 = Vector3(v.x, 0.0, v.z)
	var speed_t: float = v_t.length()
	if speed_t < 1e-4:
		return v
	var decel: float = config.rolling_friction_coeff * config.gravity
	var dv: float = min(decel * sub_dt, speed_t)
	var scale: float = (speed_t - dv) / speed_t
	return Vector3(v_t.x * scale, v.y, v_t.z * scale)


## Pure-function integrator. Given a position/velocity (+ optional spin),
## returns the next position/velocity after `sub_dt` seconds. No side
## effects, no engine state. Used by `_integrate_substep`, by the
## forward predictor (Sprint 2 T05) and by the GUT tests.
func integrate_step_pure(position: Vector3, velocity: Vector3, sub_dt: float,
		omega: Vector3 = Vector3.ZERO) -> Dictionary:
	var f: Vector3 = compute_force(velocity, omega)
	var a: Vector3 = f / config.ball_mass
	# semi-implicit Euler: velocity first, then position with the new velocity
	var v_new: Vector3 = velocity + a * sub_dt
	var p_new: Vector3 = position + v_new * sub_dt
	return {"position": p_new, "velocity": v_new}


## Sum of all active forces on the ball.
## Sprint 1: gravity + drag.
## Sprint 2: + Magnus when `config.magnus_enabled` (T01); knuckle
## perturbation is applied separately inside `_integrate_substep`
## because it needs simulation time (T02).
func compute_force(velocity: Vector3, omega: Vector3 = Vector3.ZERO) -> Vector3:
	var f: Vector3 = _gravity_force() + _drag_force(velocity)
	if config.magnus_enabled:
		f += _magnus_force(velocity, omega)
	return f


## Knuckleball acceleration (m/s²), perpendicular to the velocity.
## Active only when `|ω| < knuckle_threshold_spin` AND `|v| > knuckle_threshold_speed`.
## Two independent Simplex streams (seeded with `config.knuckle_seed` and
## `config.knuckle_seed + 1`) drive the two perpendicular axes. The result
## is deterministic for a given seed — replays match bytewise.
func knuckle_acceleration(velocity: Vector3, omega: Vector3, time: float) -> Vector3:
	if _knuckle_noise_a == null:
		return Vector3.ZERO
	var v_mag: float = velocity.length()
	if v_mag < config.knuckle_threshold_speed:
		return Vector3.ZERO
	if omega.length() > config.knuckle_threshold_spin:
		return Vector3.ZERO
	var v_hat: Vector3 = velocity / v_mag
	var lateral: Vector3 = v_hat.cross(Vector3.UP)
	if lateral.length_squared() < 1e-6:
		# velocity nearly vertical — pick any horizontal reference
		lateral = v_hat.cross(Vector3.RIGHT)
	lateral = lateral.normalized()
	var transverse: Vector3 = lateral.cross(v_hat).normalized()
	var n_a: float = _knuckle_noise_a.get_noise_1d(time)
	var n_b: float = _knuckle_noise_b.get_noise_1d(time)
	return config.knuckle_amplitude * (lateral * n_a + transverse * n_b)


## Magnus lift force.
##   F_M = 0.5 · ρ · A · Cl(S) · |v|² · (ω̂ × v̂)
## with the saturating lift coefficient Cl(S) = S / (S + 0.5), spin
## parameter S = r·|ω| / |v|, capped at `magnus_spin_param_cap`.
##
## The locked formula in SPRINT_02_PLAN (M02) reads `|v|` instead of
## `|v|²` — a units check shows that produces kg/s, not Newton, so the
## correct factor is `|v|²`. PHYSICS_LOG S02-A01 records the correction.
func _magnus_force(velocity: Vector3, omega: Vector3) -> Vector3:
	var v_mag: float = velocity.length()
	if v_mag < config.magnus_min_speed:
		return Vector3.ZERO
	var w_mag: float = omega.length()
	if w_mag < 1e-6:
		return Vector3.ZERO
	var s: float = (config.ball_radius * w_mag) / v_mag
	s = min(s, config.magnus_spin_param_cap)
	var cl: float = s / (s + 0.5)
	var area: float = PI * config.ball_radius * config.ball_radius
	var dir: Vector3 = (omega / w_mag).cross(velocity / v_mag)
	return 0.5 * config.air_density * area * cl * v_mag * v_mag * dir


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


## Forward predictor (Sprint 2 T05). Simulates the ball forward from the
## given state by `steps` substeps of `sub_dt` seconds each, applying the
## same gravity + drag + Magnus + knuckle + ground + walls + rolling
## resistance as the live integrator (M06 / M07). Returns the array of
## positions sampled at every step. Pure: no engine state read or written.
func predict_forward(p0: Vector3, v0: Vector3, omega0: Vector3,
		time0: float, steps: int, sub_dt: float) -> PackedVector3Array:
	var out: PackedVector3Array = PackedVector3Array()
	out.resize(steps)
	var p: Vector3 = p0
	var v: Vector3 = v0
	var t: float = time0
	for i in steps:
		t += sub_dt
		var step: Dictionary = integrate_step_pure(p, v, sub_dt, omega0)
		p = step.position
		v = step.velocity
		if config.knuckle_enabled:
			v += knuckle_acceleration(v0, omega0, t) * sub_dt
		var col: Dictionary = resolve_static_collisions(p, v)
		if col.collided:
			p = col.position
			v = col.velocity
		v = apply_rolling_resistance(p, v, sub_dt)
		out[i] = p
	return out


## Convenience for tests / launcher: theoretical terminal velocity for a
## freely falling ball in the current air density (no spin, no walls).
func terminal_velocity() -> float:
	var area: float = PI * config.ball_radius * config.ball_radius
	var k: float = 0.5 * config.air_density * config.drag_coeff * area
	return sqrt(config.ball_mass * config.gravity / k)
