extends GutTest

## Sprint 5 T03 — Knuckleball drift measurement + lock.
##
## Standard "tiro 4" launch: 28 m/s @ 10° elevation along +X, zero spin.
## With magnus disabled (no spin → no Magnus anyway) and the seeded
## SIMPLEX streams, the lateral (Z) drift over the first 1.5 s of
## flight is fully deterministic. Target arcade-feeling band for the
## ISS-Pro-Evolution-2 inspired sim: **|Δz| ∈ [0.8 m, 1.5 m]**
## (Carré 2004 measures real-world drift ~0.3–0.6 m at this speed;
## we want exaggerated arcade values).
##
## This test (a) reports the measured drift so calibration can see the
## current number, and (b) locks it inside [0.5, 2.0] m as a regression
## boundary. If the lock fails, retune via the F1 debug UI then update
## the measured-value section of PHYSICS_LOG S05-A03.

const LAUNCH_SPEED: float = 28.0
const LAUNCH_ELEVATION_DEG: float = 10.0
const FLIGHT_TIME: float = 1.5
const SIM_DT: float = 1.0 / 480.0          ## 4× live tick for precision

const TARGET_MIN: float = 0.5
const TARGET_MAX: float = 2.0
const SWEET_MIN: float = 0.8               ## reported, not asserted
const SWEET_MAX: float = 1.5               ## reported, not asserted

var ball: BallPhysics
var cfg: PhysicsConfig


func before_each() -> void:
	cfg = (load("res://resources/PhysicsConfig.tres") as PhysicsConfig).duplicate(true)
	cfg.knuckle_enabled = true
	cfg.magnus_enabled = false           # zero spin → Magnus is zero anyway
	cfg.grass_roughness_enabled = false  # flight only, no ground
	ball = BallPhysics.new()
	ball.config = cfg
	add_child(ball)


func after_each() -> void:
	if is_instance_valid(ball):
		ball.queue_free()
	ball = null
	cfg = null


## Simulate the ball forward without ground contact (we want only the
## flight portion). Returns the final position.
func _simulate_flight(v0: Vector3, omega0: Vector3, duration: float) -> Vector3:
	var p: Vector3 = Vector3(0.0, 1.0, 0.0)  # 1 m initial altitude
	var v: Vector3 = v0
	var omega: Vector3 = omega0
	var t: float = 0.0
	ball.reset_knuckle_clock()
	while t < duration:
		var step: Dictionary = ball.integrate_step_pure(p, v, SIM_DT, omega)
		p = step.position
		v = step.velocity
		if cfg.knuckle_enabled:
			v += ball.knuckle_acceleration(v0, omega, t) * SIM_DT
		t += SIM_DT
	return p


func test_knuckle_drift_within_arcade_band() -> void:
	var rad: float = deg_to_rad(LAUNCH_ELEVATION_DEG)
	var v0: Vector3 = Vector3(LAUNCH_SPEED * cos(rad), LAUNCH_SPEED * sin(rad), 0.0)
	var p_end: Vector3 = _simulate_flight(v0, Vector3.ZERO, FLIGHT_TIME)
	var drift: float = absf(p_end.z)
	var sweet: bool = drift >= SWEET_MIN and drift <= SWEET_MAX
	var sweet_label: String = "INSIDE" if sweet else "OUTSIDE"
	print("[knuckle drift] %.3f m over %.2fs at %.1f m/s @ %.1f° — sweet [%.2f, %.2f] %s" % [
		drift, FLIGHT_TIME, LAUNCH_SPEED, LAUNCH_ELEVATION_DEG,
		SWEET_MIN, SWEET_MAX, sweet_label])
	assert_gte(drift, TARGET_MIN,
		"Knuckle drift below regression floor (%.3f m < %.2f m)" % [drift, TARGET_MIN])
	assert_lte(drift, TARGET_MAX,
		"Knuckle drift above regression ceiling (%.3f m > %.2f m)" % [drift, TARGET_MAX])


## Deterministic seed sanity — same launch must produce the same drift.
func test_knuckle_drift_deterministic() -> void:
	var rad: float = deg_to_rad(LAUNCH_ELEVATION_DEG)
	var v0: Vector3 = Vector3(LAUNCH_SPEED * cos(rad), LAUNCH_SPEED * sin(rad), 0.0)
	var p_end_1: Vector3 = _simulate_flight(v0, Vector3.ZERO, FLIGHT_TIME)
	var p_end_2: Vector3 = _simulate_flight(v0, Vector3.ZERO, FLIGHT_TIME)
	assert_almost_eq(p_end_1.z, p_end_2.z, 1e-6,
		"Same seed must produce identical drift (got %.6f vs %.6f)" % [p_end_1.z, p_end_2.z])
