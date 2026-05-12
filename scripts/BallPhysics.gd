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

# ---- Static world geometry ------------------------------------------------
# Ground plane at y = 0. The sandbox no longer has perimeter walls:
# the previous invisible AABB walls at the field edges produced an
# "invisible wall" bug — the ball would slam into them at the end of a
# long roll and ricochet by >90°. Sandbox doesn't need containment;
# Sprint 5+ stadium nets will be visible MeshInstance3D bodies anyway.
const GROUND_Y: float = 0.0

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

# Telemetry — last computed force vectors (Newton). Read by the debug UI
# and the force gizmo. Updated every physics substep.
var last_force_gravity: Vector3 = Vector3.ZERO
var last_force_drag: Vector3 = Vector3.ZERO
var last_force_magnus: Vector3 = Vector3.ZERO
var last_force_knuckle: Vector3 = Vector3.ZERO
var last_force_grass: Vector3 = Vector3.ZERO
var last_force_net: Vector3 = Vector3.ZERO
var last_spin_param: float = 0.0
var _knuckle_noise_a: FastNoiseLite
var _knuckle_noise_b: FastNoiseLite
var _grass_noise: FastNoiseLite
var _last_grass_sample: float = 0.0
var _audio_player: AudioStreamPlayer
var _audio_stream: AudioStreamWAV
var _mesh_node: MeshInstance3D
var _base_mesh_scale: Vector3 = Vector3.ONE
var _squash_tween: Tween

# Deferred state changes (applied inside `_integrate_forces`).
# Godot best practice — see `godot-physics-3d` skill: never write
# `linear_velocity` or `global_position` on a RigidBody3D from outside
# the physics step. Callers stage their intent here; the integrator
# commits it on the next physics tick via `state.transform` etc.
var _pending_teleport: Variant = null
var _pending_linear: Variant = null
var _pending_angular: Variant = null


func _ready() -> void:
	if config == null:
		config = load("res://resources/PhysicsConfig.tres") as PhysicsConfig
		if config == null:
			push_error("BallPhysics: PhysicsConfig.tres not found")
			return
	custom_integrator = true
	continuous_cd = true
	# We resolve collisions via a deterministic AABB check inside
	# `_integrate_substep`, so we don't need Godot to report contacts.
	# `contact_monitor = false` saves the per-frame CPU cost of
	# collision reporting we'd just throw away.
	contact_monitor = false
	max_contacts_reported = 0
	mass = config.ball_mass
	gravity_scale = 0.0
	_apply_debug_visual_scale()
	_init_knuckle_noise()
	_init_grass_noise()
	_init_audio()
	_init_squash()
	bounced.connect(_on_self_bounce)
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


func _init_grass_noise() -> void:
	_grass_noise = FastNoiseLite.new()
	_grass_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_grass_noise.seed = config.knuckle_seed + 100   ## decoupled stream
	_grass_noise.frequency = config.grass_roughness_frequency


# ---- Audio (T04) ---------------------------------------------------------

func _init_audio() -> void:
	_audio_stream = _build_bounce_wav(0.18, 110.0, 22050.0, 14.0)
	# 2D player so distance attenuation never silences the bounce.
	# Sprint 4+ may swap to 3D once a near-camera follow exists.
	_audio_player = AudioStreamPlayer.new()
	_audio_player.stream = _audio_stream
	_audio_player.bus = &"Master"
	add_child(_audio_player)


## Synthesise a short damped sine "thunk". Deterministic so replays
## sound the same.
func _build_bounce_wav(duration: float, base_freq: float, sample_rate: float,
		decay: float) -> AudioStreamWAV:
	var sample_count: int = int(duration * sample_rate)
	var data: PackedByteArray = PackedByteArray()
	data.resize(sample_count * 2)  ## 16-bit mono
	var two_pi_f: float = TAU * base_freq
	for i in sample_count:
		var t: float = float(i) / sample_rate
		# Mix a couple of harmonics for body, exponential decay envelope.
		var env: float = exp(-decay * t)
		var s: float = env * (sin(two_pi_f * t) + 0.45 * sin(two_pi_f * 2.0 * t)
			+ 0.18 * sin(two_pi_f * 3.0 * t))
		var sample: int = clampi(int(s * 30000.0), -32767, 32767)
		data.encode_s16(i * 2, sample)
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(sample_rate)
	stream.stereo = false
	return stream


# ---- Squash visual (T05) -------------------------------------------------

func _init_squash() -> void:
	_mesh_node = get_node_or_null("MeshInstance3D") as MeshInstance3D
	if _mesh_node != null:
		_base_mesh_scale = _mesh_node.scale


func _on_self_bounce(impact_speed: float, normal: Vector3, _pos: Vector3) -> void:
	_play_bounce_audio(impact_speed)
	_play_squash(impact_speed, normal)


func _play_bounce_audio(impact_speed: float) -> void:
	if _audio_player == null:
		return
	_audio_player.pitch_scale = randf_range(0.95, 1.05)
	# 0.4 minimum so every bounce is clearly audible; cap above 0 dB
	# (+6 dB) so really hard hits still pop without distortion.
	var loudness: float = clampf(impact_speed / 8.0, 0.4, 2.0)
	_audio_player.volume_db = linear_to_db(loudness)
	_audio_player.play()


func _play_squash(impact_speed: float, normal: Vector3) -> void:
	if _mesh_node == null:
		return
	if impact_speed < 0.8:
		return
	if _squash_tween and _squash_tween.is_valid():
		_squash_tween.kill()
	# Up to 60 % compression along the contact normal; expand
	# perpendicular by 45 % of the squash so the silhouette is
	# unambiguous from any angle.
	var squash_amount: float = clampf(impact_speed / 12.0, 0.10, 0.60)
	var n_abs: Vector3 = normal.abs()
	var compress: Vector3 = _base_mesh_scale * (Vector3.ONE - n_abs * squash_amount)
	var expand: Vector3 = _base_mesh_scale * ((Vector3.ONE - n_abs) * (squash_amount * 0.45))
	var target: Vector3 = compress + expand
	_squash_tween = create_tween()
	_squash_tween.set_trans(Tween.TRANS_QUAD)
	_squash_tween.tween_property(_mesh_node, "scale", target, 0.08)
	_squash_tween.tween_property(_mesh_node, "scale", _base_mesh_scale, 0.30)


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
	_apply_pending_state(state)
	var dt: float = state.step
	var speed: float = state.linear_velocity.length()
	_current_substeps = compute_substeps(speed)
	var sub_dt: float = dt / float(_current_substeps)
	for i in _current_substeps:
		_integrate_substep(state, sub_dt)


# Commit deferred-state requests (teleport / launch) into the physics
# state. Called at the top of `_integrate_forces` so external systems
# (BallLauncher, SandboxController, tests) can stage intent without
# touching `RigidBody3D` properties directly.
func _apply_pending_state(state: PhysicsDirectBodyState3D) -> void:
	if _pending_teleport != null:
		var t: Transform3D = state.transform
		t.origin = _pending_teleport as Vector3
		state.transform = t
		_pending_teleport = null
	if _pending_linear != null:
		state.linear_velocity = _pending_linear as Vector3
		_pending_linear = null
	if _pending_angular != null:
		state.angular_velocity = _pending_angular as Vector3
		_pending_angular = null


# ---- Public API for the launcher / tests --------------------------------

## Stage a teleport. Position is applied at the start of the next
## physics step inside the custom integrator.
func teleport_to(pos: Vector3) -> void:
	_pending_teleport = pos


## Stage linear + angular velocity. Both are applied at the start of
## the next physics step. Pass `null` for either argument to skip
## that axis.
func apply_launch_state(linear: Variant, angular: Variant = null) -> void:
	if linear != null:
		_pending_linear = linear
	if angular != null:
		_pending_angular = angular


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
		var a_kn: Vector3 = knuckle_acceleration(state.linear_velocity, omega, _sim_time)
		last_force_knuckle = a_kn * config.ball_mass
		v += a_kn * sub_dt
	else:
		last_force_knuckle = Vector3.ZERO

	# Resolve static-world collision (ground + perimeter walls).
	var collision: Dictionary = resolve_static_collisions(p, v, omega)
	if collision.collided:
		p = collision.position
		v = collision.velocity
		omega = collision.angular_velocity
		state.angular_velocity = omega
		if collision.impact_speed >= BOUNCE_SIGNAL_MIN_SPEED:
			bounced.emit(collision.impact_speed, collision.normal, p)

	# Rolling resistance (continuous, ground-contact only).
	v = apply_rolling_resistance(p, v, sub_dt)
	# Grass micro-bumps (position-driven, fires on rising threshold).
	var v_pre_grass: Vector3 = v
	v = apply_grass_roughness(p, v, sub_dt)
	last_force_grass = (v - v_pre_grass) * config.ball_mass / maxf(sub_dt, 1e-6)
	last_force_net = (
		last_force_gravity + last_force_drag + last_force_magnus
		+ last_force_knuckle + last_force_grass
	)

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
##   collided          (bool)
##   position          (Vector3, corrected to keep the ball outside the surface)
##   velocity          (Vector3, after bounce + tangential friction)
##   angular_velocity  (Vector3, possibly modified by Cross-2002 spin transfer)
##   impact_speed      (float, |v_normal| at impact, used for audio + telemetry)
##   normal            (Vector3, surface normal of the dominant contact)
## Pure function — no engine state, safe to reuse in tests and predictor.
func resolve_static_collisions(p_in: Vector3, v_in: Vector3,
		omega_in: Vector3 = Vector3.ZERO) -> Dictionary:
	var r: float = config.ball_radius
	var p: Vector3 = p_in
	var v: Vector3 = v_in
	var omega: Vector3 = omega_in
	var collided: bool = false
	var impact_speed: float = 0.0
	var impact_normal: Vector3 = Vector3.ZERO

	# Ground (normal = +Y). Only contact this sandbox handles —
	# perimeter walls were removed (S03-A18) because they were
	# invisible to the user and caused surprise ricochets at the
	# end of long rolls.
	if p.y < GROUND_Y + r and v.y < 0.0:
		var vn: float = -v.y
		if vn > impact_speed:
			impact_speed = vn
			impact_normal = Vector3.UP
		p.y = GROUND_Y + r
		var out: Dictionary = _resolve_contact_full(v, omega, Vector3.UP, vn)
		v = out.velocity
		omega = out.angular_velocity
		if vn >= BOUNCE_SIGNAL_MIN_SPEED:
			v = _grass_perturb_bounce(p, v, vn)
		collided = true

	return {
		"collided": collided,
		"position": p,
		"velocity": v,
		"angular_velocity": omega,
		"impact_speed": impact_speed,
		"normal": impact_normal,
	}


## Cross-2002 + soft-contact dispatcher.
## Hard impact: branch on `config.cross_2002_enabled` — either Cross
## (which updates angular_velocity too) or the legacy Sprint 2 model.
## Soft impact: cancel normal component, leave tangent and ω alone.
func _resolve_contact_full(v: Vector3, omega: Vector3, normal: Vector3,
		impact_speed: float) -> Dictionary:
	if impact_speed >= BOUNCE_SIGNAL_MIN_SPEED:
		if config.cross_2002_enabled:
			return _bounce_cross_2002(v, omega, normal)
		return {
			"velocity": _bounce_velocity(v, normal),
			"angular_velocity": omega,
		}
	# Soft contact
	var v_n_scalar: float = v.dot(normal)
	return {
		"velocity": v - normal * v_n_scalar,
		"angular_velocity": omega,
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


## Legacy Sprint 2 bounce model — kept around for the GUT tests that
## lock the pre-Cross behaviour, and for `cross_2002_enabled = false`.
## Angle-aware (S02-A10) and uses the per-surface restitution base.
func _bounce_velocity(v: Vector3, normal: Vector3) -> Vector3:
	var v_n_scalar: float = v.dot(normal)
	var v_normal: Vector3 = normal * v_n_scalar
	var v_tangent: Vector3 = v - v_normal
	var speed: float = v.length()
	var sin_impact: float = 0.0 if speed < 1e-3 else absf(v_n_scalar) / speed
	var angle_factor: float = smoothstep(0.05, 0.35, sin_impact)
	var e_eff: float = _restitution_base() * angle_factor
	var v_normal_new: Vector3 = -e_eff * v_normal
	var v_tangent_new: Vector3 = v_tangent * (1.0 - config.friction)
	return v_normal_new + v_tangent_new


## Cross-2002 grip-slip bounce. Treats the ball as a hollow shell
## (`I = (2/3) m r²`). Computes the tangential velocity AT the contact
## point (linear + spin) and the impulse needed to reduce it by
## `(1 + e_t)` (grip case). Coulomb's friction caps the impulse at
## `μ_s · J_n` (slip case). Both linear velocity and angular velocity
## change as a consequence — the spin transfer the user asked for.
##
## Variable normal restitution (S03-A02): `e_n` decreases with `|v_n|`
## following `e_base · exp(-|v_n|/v_ref)` when enabled, modelling the
## extra deformation losses at hard impacts. Surface state (dry / wet)
## chooses the underlying `e_base` and `μ_s`.
##
## The angle-aware smoothstep from S02-A10 is preserved on top — for a
## grazing impact the effective `e_n` collapses to ~0 so the ball keeps
## sliding, while the friction logic still kicks the spin around the
## contact-point velocity.
func _bounce_cross_2002(v: Vector3, omega: Vector3, normal: Vector3) -> Dictionary:
	var r: float = config.ball_radius
	var m: float = config.ball_mass
	var inertia_factor: float = 2.0 / 3.0  ## hollow sphere shell
	var I: float = inertia_factor * m * r * r

	var v_n_scalar: float = v.dot(normal)
	var v_normal: Vector3 = normal * v_n_scalar
	var v_tangent: Vector3 = v - v_normal

	# Velocity AT the contact point (linear + spin contribution).
	var r_contact: Vector3 = -normal * r
	var v_contact: Vector3 = v + omega.cross(r_contact)
	var v_c_t: Vector3 = v_contact - normal * v_contact.dot(normal)
	var v_c_mag: float = v_c_t.length()

	# Normal restitution (variable + angle-aware).
	var e_n: float = _restitution_at_velocity(absf(v_n_scalar))
	var speed: float = v.length()
	var sin_impact: float = 0.0 if speed < 1e-3 else absf(v_n_scalar) / speed
	var angle_factor: float = smoothstep(0.05, 0.35, sin_impact)
	e_n *= angle_factor
	var v_normal_new: Vector3 = -e_n * v_normal
	var J_n_mag: float = (1.0 + e_n) * absf(v_n_scalar) * m

	if v_c_mag < 1e-6:
		return {
			"velocity": v_normal_new + v_tangent,
			"angular_velocity": omega,
		}

	# Grip case impulse magnitude. For an impulse J_t applied at the
	# contact point, the contact-point tangential velocity changes by
	# Δv_c = J_t · (1/m + r²/I) = J_t · (1 + 1/k) / m   (k = inertia_factor).
	# To go from v_c to −e_t · v_c we need Δv_c = -(1 + e_t)·|v_c| in
	# the direction opposing v_c. Hence:
	#   J_t_grip = (1 + e_t) · |v_c| · m · k / (1 + k)
	var J_t_grip: float = (1.0 + config.bounce_e_t) * v_c_mag * m * inertia_factor / (1.0 + inertia_factor)
	var J_t_max: float = _mu_s() * J_n_mag
	var J_t_mag: float = minf(J_t_grip, J_t_max)
	var J_t: Vector3 = (-v_c_t / v_c_mag) * J_t_mag

	# Apply impulse.
	var dv_linear: Vector3 = J_t / m
	var v_tangent_new: Vector3 = v_tangent + dv_linear
	var d_omega: Vector3 = r_contact.cross(J_t) / I
	var omega_new: Vector3 = omega + d_omega

	return {
		"velocity": v_normal_new + v_tangent_new,
		"angular_velocity": omega_new,
	}


## Variable normal restitution e_n(|v_n|).
func _restitution_at_velocity(v_n_mag: float) -> float:
	var e_base: float = _restitution_base()
	if not config.variable_restitution_enabled:
		return e_base
	return e_base * exp(-v_n_mag / config.restitution_v_ref)


## Surface-sensitive parameter getters.
func _restitution_base() -> float:
	return config.restitution_base_wet if config.surface_wet else config.restitution_base


func _mu_s() -> float:
	return config.bounce_mu_s_wet if config.surface_wet else config.bounce_mu_s


func _rolling_friction() -> float:
	return config.rolling_friction_wet if config.surface_wet else config.rolling_friction_coeff


func _grass_kick_amount() -> float:
	return config.grass_roughness_kick_wet if config.surface_wet else config.grass_roughness_kick


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
	var decel: float = _rolling_friction() * config.gravity
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
	var fg: Vector3 = _gravity_force()
	var fd: Vector3 = _drag_force(velocity)
	var fm: Vector3 = _magnus_force(velocity, omega) if config.magnus_enabled else Vector3.ZERO
	last_force_gravity = fg
	last_force_drag = fd
	last_force_magnus = fm
	var v_mag: float = velocity.length()
	last_spin_param = 0.0 if v_mag < 1e-3 else minf(
		config.ball_radius * omega.length() / v_mag, config.magnus_spin_param_cap)
	return fg + fd + fm


## Knuckleball acceleration (m/s²), perpendicular to the velocity.
## Active only when `|ω| < knuckle_threshold_spin` AND `|v| > knuckle_threshold_speed`.
##
## Two-layer noise model so the trajectory feels unpredictable, matching
## the textbook definition ("high-speed strike with little to no spin,
## causing the ball to move unpredictably — wobble or dip — through the
## air"):
##   - **Smooth wobble**: two independent SIMPLEX streams (seeded with
##     `knuckle_seed` and `knuckle_seed + 1`) at `knuckle_noise_frequency`.
##   - **Snap layer**: the same streams sampled at a much higher rate
##     (`knuckle_spike_frequency_mul ×` base freq) — wherever the
##     high-rate noise exceeds `knuckle_spike_threshold` we add an
##     additional impulse scaled by `knuckle_spike_amplitude_mul`. This
##     produces the brief, hard-to-anticipate veers that knuckle
##     specialists exploit in real life, without crossing into chaotic
##     behaviour.
## Result is deterministic for a given seed.
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
		lateral = v_hat.cross(Vector3.RIGHT)
	lateral = lateral.normalized()
	var transverse: Vector3 = lateral.cross(v_hat).normalized()
	# Smooth wobble (base layer)
	var smooth_a: float = _knuckle_noise_a.get_noise_1d(time)
	var smooth_b: float = _knuckle_noise_b.get_noise_1d(time)
	# Snap layer — same streams sampled at a higher rate plus an offset
	# so the two octaves don't lock-phase.
	var t_fast: float = time * config.knuckle_spike_frequency_mul
	var spike_a: float = _knuckle_noise_a.get_noise_1d(t_fast + 137.0)
	var spike_b: float = _knuckle_noise_b.get_noise_1d(t_fast + 263.0)
	var thr: float = config.knuckle_spike_threshold
	var spike_mul: float = config.knuckle_spike_amplitude_mul
	if absf(spike_a) > thr:
		smooth_a += signf(spike_a) * (absf(spike_a) - thr) * spike_mul
	if absf(spike_b) > thr:
		smooth_b += signf(spike_b) * (absf(spike_b) - thr) * spike_mul
	# Velocity-scale: real knuckle effect grows with |v|^2 (drag-driven).
	# Use a soft factor so slow knuckle shots still get something.
	var speed_factor: float = clampf((v_mag - config.knuckle_threshold_speed) / 12.0, 0.2, 1.4)
	return config.knuckle_amplitude * speed_factor * (lateral * smooth_a + transverse * smooth_b)


## Grass jitter on a hard ground bounce. Adds a positive vertical kick
## (turf pushes the ball back up) plus a small lateral deflection,
## both sampled deterministically from the position-noise stream so
## the same patch of grass always behaves the same way. Magnitude
## scales linearly with how hard the bounce was, capped at 8 m/s.
func _grass_perturb_bounce(p: Vector3, v: Vector3, vn: float) -> Vector3:
	if not config.grass_roughness_enabled or _grass_noise == null:
		return v
	var n_y: float = _grass_noise.get_noise_2d(p.x, p.z)
	var n_x: float = _grass_noise.get_noise_2d(p.x + 73.5, p.z - 41.0)
	var n_z: float = _grass_noise.get_noise_2d(p.x - 91.0, p.z + 17.0)
	var speed_factor: float = clampf((vn - BOUNCE_SIGNAL_MIN_SPEED) / 8.0, 0.0, 1.0)
	var kick: float = _grass_kick_amount() * speed_factor
	v.y += absf(n_y) * kick * 0.7   ## always upward (turf pushes up)
	v.x += n_x * kick * 0.45
	v.z += n_z * kick * 0.45
	return v


## Grass micro-bumps. When the ball is rolling on the ground at high
## tangential speed, a position-sampled Simplex noise produces small
## vertical kicks on rising-edge crossings of `grass_roughness_threshold`,
## modelling tufts and natural undulations. Deterministic per position
## (the same patch of grass always behaves the same way).
##
## Returns the velocity AFTER the kick has been applied (if any).
func apply_grass_roughness(p: Vector3, v: Vector3, sub_dt: float) -> Vector3:
	if not config.grass_roughness_enabled or _grass_noise == null:
		return v
	var r: float = config.ball_radius
	if p.y > GROUND_Y + r + ROLLING_HEIGHT_TOL:
		_last_grass_sample = 0.0
		return v
	if absf(v.y) > ROLLING_VY_TOL:
		_last_grass_sample = 0.0
		return v
	var v_t: float = Vector3(v.x, 0.0, v.z).length()
	if v_t < config.grass_roughness_min_speed:
		_last_grass_sample = 0.0
		return v
	var sample: float = _grass_noise.get_noise_2d(p.x, p.z)
	var thr: float = config.grass_roughness_threshold
	var crossed: bool = _last_grass_sample < thr and sample >= thr
	_last_grass_sample = sample
	if crossed:
		var speed_factor: float = clampf(
			(v_t - config.grass_roughness_min_speed) / 20.0, 0.0, 1.0,
		)
		var kick: float = _grass_kick_amount() * speed_factor * sample
		v.y += kick
	return v


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
	var omega: Vector3 = omega0
	var t: float = time0
	for i in steps:
		t += sub_dt
		var step: Dictionary = integrate_step_pure(p, v, sub_dt, omega)
		p = step.position
		v = step.velocity
		if config.knuckle_enabled:
			v += knuckle_acceleration(v0, omega0, t) * sub_dt
		var col: Dictionary = resolve_static_collisions(p, v, omega)
		if col.collided:
			p = col.position
			v = col.velocity
			omega = col.angular_velocity
		v = apply_rolling_resistance(p, v, sub_dt)
		v = apply_grass_roughness(p, v, sub_dt)
		out[i] = p
	return out


## Convenience for tests / launcher: theoretical terminal velocity for a
## freely falling ball in the current air density (no spin, no walls).
func terminal_velocity() -> float:
	var area: float = PI * config.ball_radius * config.ball_radius
	var k: float = 0.5 * config.air_density * config.drag_coeff * area
	return sqrt(config.ball_mass * config.gravity / k)
