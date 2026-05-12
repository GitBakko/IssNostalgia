extends GutTest

## Sprint 5 T01 — Bounce energy audit.
##
## Goal: detect the "schizzo" bug reported on the LMB lob — the second
## bounce occasionally appearing to gain velocity. Without drag and grass
## (deterministic), the ball's TOTAL mechanical energy can only decrease
## across a bounce: real-world bounces dissipate, the model must too.
##
## Because both the height at every bounce point is identical (y = r) and
## gravity is conservative, the mechanical-energy check collapses to a
## kinetic-energy check between consecutive post-bounce states:
##
##     KE_post(i+1) <= KE_post(i) · (1 + ε)
##
## where KE_post = ½·m·|v|² + ½·I·|ω|² (hollow shell I = (2/3)·m·r²).
##
## ε = 1e-2 absorbs the semi-implicit Euler integration noise across
## hundreds of substeps per flight phase.

const INERTIA_FACTOR: float = 2.0 / 3.0   ## hollow shell
const ENERGY_TOL: float = 1e-2            ## 1% relative
const SIM_DT: float = 1.0 / 480.0         ## 480 Hz, ~4× the live tick
const MAX_SIM_TIME: float = 5.0           ## seconds
## High-speed shots get fewer hard bounces because the angle-aware
## restitution from S02-A10 collapses e_eff toward zero on grazing hits
## — the ball transitions to rolling sooner. Two bounces is enough to
## detect a "schizzo" (an energy gain between any consecutive pair).
const MIN_BOUNCES: int = 2

var ball: BallPhysics
var cfg: PhysicsConfig


func before_each() -> void:
	cfg = (load("res://resources/PhysicsConfig.tres") as PhysicsConfig).duplicate(true)
	# Strip every stochastic / dissipative channel except the bounce
	# itself so the energy bookkeeping is unambiguous.
	cfg.grass_roughness_enabled = false
	cfg.drag_coeff = 0.0
	cfg.surface_wet = false
	cfg.knuckle_enabled = false
	cfg.magnus_enabled = false   # Magnus is conservative but we don't
	                             # need it for the bounce check, and the
	                             # spin-velocity coupling adds noise
	ball = BallPhysics.new()
	ball.config = cfg
	add_child(ball)


func after_each() -> void:
	if is_instance_valid(ball):
		ball.queue_free()
	ball = null
	cfg = null


## Helper: simulate the ball forward, return the list of bounce events.
## Each event records pre- and post-bounce state so the energy check
## can compare the *closing* KE of consecutive bounces.
func _simulate_bounces(p0: Vector3, v0: Vector3, omega0: Vector3) -> Array:
	var bounces: Array = []
	var p: Vector3 = p0
	var v: Vector3 = v0
	var omega: Vector3 = omega0
	var t: float = 0.0
	var bounce_cooldown: float = 0.0   ## avoid double-counting micro-bounces
	while t < MAX_SIM_TIME:
		var step: Dictionary = ball.integrate_step_pure(p, v, SIM_DT, omega)
		p = step.position
		v = step.velocity
		var col: Dictionary = ball.resolve_static_collisions(p, v, omega)
		if col.collided:
			p = col.position
			if col.impact_speed >= 0.8 and bounce_cooldown <= 0.0:
				bounces.append({
					"t": t,
					"impact_speed": col.impact_speed,
					"v_pre": v,
					"omega_pre": omega,
					"v_post": col.velocity,
					"omega_post": col.angular_velocity,
				})
				bounce_cooldown = 0.05   ## 50 ms minimum gap
			v = col.velocity
			omega = col.angular_velocity
		v = ball.apply_rolling_resistance(p, v, SIM_DT)
		bounce_cooldown = maxf(bounce_cooldown - SIM_DT, 0.0)
		t += SIM_DT
	return bounces


func _kinetic_energy(v: Vector3, omega: Vector3) -> float:
	var r: float = cfg.ball_radius
	var m: float = cfg.ball_mass
	var inertia: float = INERTIA_FACTOR * m * r * r
	return 0.5 * m * v.length_squared() + 0.5 * inertia * omega.length_squared()


func _assert_monotone_energy(bounces: Array, label: String) -> void:
	assert_gte(bounces.size(), MIN_BOUNCES,
		"%s: expected at least %d bounces, got %d" % [label, MIN_BOUNCES, bounces.size()])
	var ke_prev: float = _kinetic_energy(bounces[0].v_post, bounces[0].omega_post)
	for i in range(1, bounces.size()):
		var b: Dictionary = bounces[i]
		var ke_now: float = _kinetic_energy(b.v_post, b.omega_post)
		var rel_gain: float = (ke_now - ke_prev) / maxf(ke_prev, 1e-9)
		assert_lte(ke_now, ke_prev * (1.0 + ENERGY_TOL),
			"%s: bounce %d KE grew from %.3f J to %.3f J (Δ=%.2f%%)" % [
				label, i, ke_prev, ke_now, rel_gain * 100.0])
		ke_prev = ke_now


# ---- Shot-shape test cases -----------------------------------------------

## Spinless lob — reproduces the LMB lob the user reported as "schizza".
func test_energy_spinless_lob() -> void:
	var p0: Vector3 = Vector3(0.0, cfg.ball_radius, 0.0)
	var v0: Vector3 = Vector3(10.0, 5.0, 0.0)
	var omega0: Vector3 = Vector3.ZERO
	var bounces: Array = _simulate_bounces(p0, v0, omega0)
	_assert_monotone_energy(bounces, "spinless lob")


## Topspin curve — Cross-2002 grip case converts ω→v at the contact.
## Energy must still drop overall.
func test_energy_topspin_curve() -> void:
	var p0: Vector3 = Vector3(0.0, cfg.ball_radius, 0.0)
	var v0: Vector3 = Vector3(20.0, 5.0, 0.0)
	var omega0: Vector3 = Vector3(0.0, 0.0, -15.0)
	var bounces: Array = _simulate_bounces(p0, v0, omega0)
	_assert_monotone_energy(bounces, "topspin curve")


## Backspin drop — opposite spin sign, similar test.
func test_energy_backspin_drop() -> void:
	var p0: Vector3 = Vector3(0.0, cfg.ball_radius, 0.0)
	var v0: Vector3 = Vector3(15.0, 5.0, 0.0)
	var omega0: Vector3 = Vector3(0.0, 0.0, 20.0)
	var bounces: Array = _simulate_bounces(p0, v0, omega0)
	_assert_monotone_energy(bounces, "backspin drop")


## Strong topspin — pushes the Cross-2002 model toward the slip case
## (J_t_grip > μ_s·J_n) and stresses the largest spin-to-linear energy
## conversion. This is the closest analytical match for the user's
## "schizzo" report: heavy spin acquired or imparted at the first
## bounce that could in principle make the second bounce gain linear
## velocity. Energy total must still drop.
func test_energy_strong_topspin() -> void:
	var p0: Vector3 = Vector3(0.0, cfg.ball_radius, 0.0)
	var v0: Vector3 = Vector3(18.0, 5.0, 0.0)
	var omega0: Vector3 = Vector3(0.0, 0.0, -50.0)
	var bounces: Array = _simulate_bounces(p0, v0, omega0)
	_assert_monotone_energy(bounces, "strong topspin")
