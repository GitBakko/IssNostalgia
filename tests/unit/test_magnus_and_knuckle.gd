extends GutTest

## Sprint 2 numerical locks for Magnus, knuckleball, and the forward predictor.

const TICK_HZ: float = 120.0
const SUBSTEP_DT: float = 1.0 / TICK_HZ / 4.0

var ball: BallPhysics
var cfg: PhysicsConfig


func before_each() -> void:
	cfg = (load("res://resources/PhysicsConfig.tres") as PhysicsConfig).duplicate(true)
	ball = BallPhysics.new()
	ball.config = cfg
	add_child(ball)


func after_each() -> void:
	if is_instance_valid(ball):
		ball.queue_free()
	ball = null
	cfg = null


# --- Magnus ---------------------------------------------------------------

func test_magnus_zero_spin_zero_force() -> void:
	var v: Vector3 = Vector3(25.0, 0.0, 0.0)
	var f1: Vector3 = ball._magnus_force(v, Vector3.ZERO)
	assert_eq(f1, Vector3.ZERO, "Magnus must be zero when |omega| = 0")
	var f2: Vector3 = ball._magnus_force(Vector3(0.1, 0.0, 0.0), Vector3(0.0, 10.0, 0.0))
	assert_eq(f2, Vector3.ZERO, "Magnus must be zero when |v| < magnus_min_speed")


func test_magnus_curve_direction() -> void:
	cfg.magnus_enabled = true
	cfg.drag_coeff = 0.0
	cfg.knuckle_enabled = false
	var p: Vector3 = Vector3(0.0, 50.0, 0.0)
	var v: Vector3 = Vector3(25.0, 0.0, 0.0)
	var omega: Vector3 = Vector3(0.0, 10.0, 0.0)
	for _i in int(0.5 / SUBSTEP_DT):
		var s: Dictionary = ball.integrate_step_pure(p, v, SUBSTEP_DT, omega)
		p = s.position
		v = s.velocity
	assert_lt(p.z, -0.01, "Sidespin +Y on +X velocity curves toward -Z. z=%.4f" % p.z)
	assert_gt(p.x, 10.0, "Ball keeps forward speed")


# --- Knuckleball ----------------------------------------------------------

func test_knuckle_zero_below_threshold() -> void:
	var slow: Vector3 = Vector3(2.0, 0.0, 0.0)
	var a: Vector3 = ball.knuckle_acceleration(slow, Vector3.ZERO, 1.0, 1.0 / 120.0)
	assert_eq(a, Vector3.ZERO, "No knuckle below threshold_speed")
	var fast: Vector3 = Vector3(28.0, 0.0, 0.0)
	var a2: Vector3 = ball.knuckle_acceleration(fast, Vector3(0.0, 5.0, 0.0), 1.0, 1.0 / 120.0)
	assert_eq(a2, Vector3.ZERO, "No knuckle when |omega| > threshold_spin")


func test_knuckle_acceleration_deterministic() -> void:
	# S05-A04 stall-flip model: determinism is now at the SEQUENCE level
	# (same seed + same call sequence → identical trajectory), not at the
	# single-call level — every call advances the stall timer + ramp, so
	# back-to-back calls intentionally diverge. Reset between sequences
	# and check the final state matches.
	var v: Vector3 = Vector3(28.0, 0.0, 0.0)
	var omega: Vector3 = Vector3.ZERO
	var sub_dt: float = 1.0 / 120.0
	var a1: Vector3 = Vector3.ZERO
	var a2: Vector3 = Vector3.ZERO
	ball.reset_knuckle_clock()
	for i in 60:
		a1 = ball.knuckle_acceleration(v, omega, float(i) * sub_dt, sub_dt)
	ball.reset_knuckle_clock()
	for i in 60:
		a2 = ball.knuckle_acceleration(v, omega, float(i) * sub_dt, sub_dt)
	assert_eq(a1, a2, "Same seed + same call sequence must yield identical acceleration")
	assert_gt(a1.length(), 0.0, "Knuckle must be non-zero after 60 substeps in flight")


# --- Predictor ------------------------------------------------------------

func test_predictor_idempotent() -> void:
	# Calling predict_forward twice with identical inputs must yield
	# identical trajectories.
	cfg.knuckle_enabled = false
	var p: Vector3 = Vector3(0.0, 50.0, 0.0)
	var v: Vector3 = Vector3(20.0, 5.0, 0.0)
	var omega: Vector3 = Vector3(0.0, 6.0, 0.0)
	var a: PackedVector3Array = ball.predict_forward(p, v, omega, 0.0, 240, SUBSTEP_DT)
	var b: PackedVector3Array = ball.predict_forward(p, v, omega, 0.0, 240, SUBSTEP_DT)
	assert_eq(a.size(), b.size(), "Same length")
	for i in a.size():
		assert_eq(a[i], b[i], "Step %d must match" % i)


func test_predictor_endpoint_above_ground() -> void:
	# A 20 m/s level launch should not have predict_forward dropping the
	# ball below y = ball_radius at any sample (no tunneling in predictor).
	cfg.knuckle_enabled = false
	var p: Vector3 = Vector3(0.0, 5.0, 0.0)
	var v: Vector3 = Vector3(20.0, 0.0, 0.0)
	var omega: Vector3 = Vector3.ZERO
	var traj: PackedVector3Array = ball.predict_forward(p, v, omega, 0.0, 600, SUBSTEP_DT)
	var min_y: float = traj[0].y
	for q in traj:
		if q.y < min_y:
			min_y = q.y
	assert_gte(min_y, cfg.ball_radius - 1e-3,
		"Predictor must keep ball above ball_radius. min_y = %.5f" % min_y)
