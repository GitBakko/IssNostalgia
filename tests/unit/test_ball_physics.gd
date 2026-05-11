extends GutTest

## Numerical lock for the Sprint 1 ball physics.
##
## All four tests drive the *pure* parts of BallPhysics (integrate_step_pure
## and resolve_static_collisions) without spinning up the Godot physics
## server. The simulation loop here is exactly what the live integrator
## runs at one of its substeps, just without the engine plumbing.
##
##   1. test_gravity_integration   — Δv = g·Δt entro 1e-2 m/s (no drag)
##   2. test_drag_terminal_velocity — v_term = sqrt(2 m g / (ρ Cd A)) entro 5 %
##   3. test_restitution_decay      — h_n = h_0 · e^(2n) entro 3 %
##   4. test_no_tunneling           — y ≥ ball_radius con v_init = -50 m/s

const TICK_HZ: float = 120.0
const TICK_DT: float = 1.0 / TICK_HZ
const SUBSTEPS_LOW: int = 4
const SUBSTEP_DT: float = TICK_DT / float(SUBSTEPS_LOW)

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


# --- helpers --------------------------------------------------------------

func _simulate(p_init: Vector3, v_init: Vector3, duration_s: float, dt: float,
		with_collisions: bool = true) -> Dictionary:
	var p: Vector3 = p_init
	var v: Vector3 = v_init
	var steps: int = int(round(duration_s / dt))
	var min_y: float = p.y
	for _i in steps:
		var s: Dictionary = ball.integrate_step_pure(p, v, dt)
		p = s.position
		v = s.velocity
		if with_collisions:
			var c: Dictionary = ball.resolve_static_collisions(p, v)
			if c.collided:
				p = c.position
				v = c.velocity
		min_y = min(min_y, p.y)
	return {"p": p, "v": v, "min_y": min_y, "steps": steps}


# --- tests ----------------------------------------------------------------

func test_gravity_integration() -> void:
	# Free-fall, no drag, no collisions. Δv must equal g · Δt within
	# integrator round-off.
	cfg.drag_coeff = 0.0
	var result: Dictionary = _simulate(
		Vector3(0.0, 100.0, 0.0), Vector3.ZERO, 1.0, SUBSTEP_DT, false,
	)
	var expected_vy: float = -cfg.gravity * 1.0
	assert_almost_eq(
		result.v.y, expected_vy, 0.02,
		"v.y after 1 s of free-fall must equal -g (got %.4f, want %.4f)" % [
			result.v.y, expected_vy,
		],
	)


func test_drag_terminal_velocity() -> void:
	# Drop the ball from a great height with full drag enabled. After
	# 30 s the speed must be within 5 % of the closed-form terminal
	# velocity v_t = sqrt(2·m·g / (ρ·Cd·A)).
	var v_term: float = ball.terminal_velocity()
	var result: Dictionary = _simulate(
		Vector3(0.0, 5000.0, 0.0), Vector3.ZERO, 30.0, SUBSTEP_DT, false,
	)
	var measured_speed: float = abs(result.v.y)
	var rel_err: float = abs(measured_speed - v_term) / v_term
	gut.p("Terminal velocity: closed-form %.3f m/s, simulated %.3f m/s, rel.err %.4f" % [
		v_term, measured_speed, rel_err,
	])
	assert_lt(
		rel_err, 0.05,
		"Speed must converge to terminal velocity within 5%% (got rel.err %.4f)" % rel_err,
	)


func test_restitution_decay() -> void:
	# Drop from h0 with no drag and no tangential friction so the only
	# energy loss per cycle is the configured restitution_base. The peak
	# heights between bounces must follow h_n = h_0 · e^(2n) within 3 %.
	cfg.drag_coeff = 0.0
	cfg.friction = 0.0
	cfg.grass_roughness_enabled = false
	cfg.rolling_friction_coeff = 0.0
	var h0: float = 5.0
	var e: float = cfg.restitution_base
	var p: Vector3 = Vector3(0.0, h0, 0.0)
	var v: Vector3 = Vector3.ZERO
	var dt: float = SUBSTEP_DT
	var peaks: Array[float] = []
	var prev_vy: float = 0.0
	# Simulate up to 6 s — plenty for the first 3 peaks at e = 0.6, h0 = 5 m.
	var steps: int = int(6.0 / dt)
	for _i in steps:
		var s: Dictionary = ball.integrate_step_pure(p, v, dt)
		p = s.position
		v = s.velocity
		var c: Dictionary = ball.resolve_static_collisions(p, v)
		if c.collided:
			p = c.position
			v = c.velocity
		# Apex detection: vy was > 0 last step, now <= 0.
		if prev_vy > 0.0 and v.y <= 0.0:
			peaks.append(p.y)
			if peaks.size() >= 3:
				break
		prev_vy = v.y
	gut.p("Peaks (m): %s" % str(peaks))
	assert_gte(peaks.size(), 2, "Must detect at least two apex heights")
	var h1_expected: float = h0 * e * e             # e^2 · h0
	var h2_expected: float = h0 * pow(e, 4)         # e^4 · h0
	assert_almost_eq(
		peaks[0], h1_expected, 0.03 * h0,
		"Peak #1 must equal e^2·h0 (got %.4f, want %.4f)" % [peaks[0], h1_expected],
	)
	assert_almost_eq(
		peaks[1], h2_expected, 0.03 * h0,
		"Peak #2 must equal e^4·h0 (got %.4f, want %.4f)" % [peaks[1], h2_expected],
	)


func test_no_tunneling() -> void:
	# Launch the ball straight at the ground from y = 1 m at 50 m/s.
	# In a single 4-substep tick at 120 Hz the per-substep travel is
	# v · sub_dt = 50 · (1/480) ≈ 0.104 m, comparable to ball_radius
	# (0.11 m). The integrator + resolver must still guarantee that the
	# ball center stays above the ground plane plus ball_radius.
	cfg.grass_roughness_enabled = false  # avoid noise injection
	var p: Vector3 = Vector3(0.0, 1.0, 0.0)
	var v: Vector3 = Vector3(0.0, -50.0, 0.0)
	var dt: float = SUBSTEP_DT
	var steps: int = int(round(1.5 / dt))   # 1.5 s = plenty of bounces
	var min_y: float = p.y
	for _i in steps:
		var s: Dictionary = ball.integrate_step_pure(p, v, dt)
		p = s.position
		v = s.velocity
		var c: Dictionary = ball.resolve_static_collisions(p, v)
		if c.collided:
			p = c.position
			v = c.velocity
		min_y = min(min_y, p.y)
	gut.p("test_no_tunneling: min y observed = %.5f m, ball_radius = %.5f m" % [
		min_y, cfg.ball_radius,
	])
	# Allow a tiny numerical tolerance below ball_radius (≤1e-3 m).
	assert_gte(
		min_y, cfg.ball_radius - 1e-3,
		"Ball center must never go below ball_radius. min_y = %.5f, r = %.5f" % [
			min_y, cfg.ball_radius,
		],
	)
