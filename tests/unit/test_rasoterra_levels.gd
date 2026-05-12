extends GutTest

## Sprint 5 T04 — Rasoterra low-power verification.
##
## Three power levels along +X with light topspin (~4 rad/s top axis).
## A real "rasoterra forte" stays bottom-low across the entire roll;
## no skip higher than ~4 cm. We assert a slightly looser 6 cm ceiling
## so per-position grass roughness noise doesn't false-fail the test.
##
##   strong   30 m/s @ 1° — validated visually Sprint 2 (S02-A14)
##   medium   15 m/s @ 3° — intermediate, not previously locked
##   low      10 m/s @ 1° — was [PENDING] from Sprint 2, this test
##                          closes the deferral
##
## We simulate 3 s of motion with the full live integrator pure
## functions: integrate_step_pure + resolve_static_collisions +
## apply_rolling_resistance + apply_grass_roughness. The metric we
## lock is `max( p.y - ball_radius )` after the first hard bounce —
## i.e. how high the BOTTOM of the ball gets above the grass.

const SIM_DT: float = 1.0 / 480.0
const FLIGHT_TIME: float = 3.0
const SKIP_CEILING: float = 0.06   ## 6 cm hard ceiling on bottom-above-ground
const TOPSPIN: float = 4.0         ## rad/s, around -Z axis (top axis for +X motion)

var ball: BallPhysics
var cfg: PhysicsConfig


func before_each() -> void:
	cfg = (load("res://resources/PhysicsConfig.tres") as PhysicsConfig).duplicate(true)
	cfg.surface_wet = false
	ball = BallPhysics.new()
	ball.config = cfg
	add_child(ball)


func after_each() -> void:
	if is_instance_valid(ball):
		ball.queue_free()
	ball = null
	cfg = null


## Returns the maximum bottom-above-ground height observed after the
## first hard bounce. Pre-bounce arc is ignored (we don't care about
## launch elevation, only about how high the ball skips back up).
func _max_skip(speed: float, elev_deg: float) -> float:
	var rad: float = deg_to_rad(elev_deg)
	var p: Vector3 = Vector3(0.0, cfg.ball_radius, 0.0)
	var v: Vector3 = Vector3(speed * cos(rad), speed * sin(rad), 0.0)
	# Top axis for +X motion = UP × dir = (0,0,-1); positive topspin = ω along that axis.
	var omega: Vector3 = Vector3(0.0, 0.0, -TOPSPIN)
	var t: float = 0.0
	var first_bounce: bool = false
	var max_bottom: float = 0.0
	while t < FLIGHT_TIME:
		var step: Dictionary = ball.integrate_step_pure(p, v, SIM_DT, omega)
		p = step.position
		v = step.velocity
		var col: Dictionary = ball.resolve_static_collisions(p, v, omega)
		if col.collided:
			p = col.position
			v = col.velocity
			omega = col.angular_velocity
			# ANY ground contact counts as "the ball is now on the field"
			# — rasoterra shots are grazing, often below the hard-bounce
			# threshold, but the skip metric still applies (grass bumps
			# can throw the ball off the ground even from a soft contact).
			first_bounce = true
		v = ball.apply_rolling_resistance(p, v, SIM_DT)
		v = ball.apply_grass_roughness(p, v, SIM_DT)
		if first_bounce:
			var bottom: float = p.y - cfg.ball_radius
			if bottom > max_bottom:
				max_bottom = bottom
		t += SIM_DT
	return max_bottom


func test_rasoterra_strong() -> void:
	var skip: float = _max_skip(30.0, 1.0)
	print("[rasoterra strong] max bottom-above-ground = %.3f m (cap %.2f m)" % [skip, SKIP_CEILING])
	assert_lte(skip, SKIP_CEILING,
		"Strong rasoterra (30 m/s @ 1°) skip %.3f m > %.2f m" % [skip, SKIP_CEILING])


func test_rasoterra_medium() -> void:
	var skip: float = _max_skip(15.0, 3.0)
	print("[rasoterra medium] max bottom-above-ground = %.3f m (cap %.2f m)" % [skip, SKIP_CEILING])
	assert_lte(skip, SKIP_CEILING,
		"Medium rasoterra (15 m/s @ 3°) skip %.3f m > %.2f m" % [skip, SKIP_CEILING])


func test_rasoterra_low() -> void:
	var skip: float = _max_skip(10.0, 1.0)
	print("[rasoterra low] max bottom-above-ground = %.3f m (cap %.2f m)" % [skip, SKIP_CEILING])
	assert_lte(skip, SKIP_CEILING,
		"Low rasoterra (10 m/s @ 1°) skip %.3f m > %.2f m" % [skip, SKIP_CEILING])
