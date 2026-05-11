extends GutTest

## Sprint 3 numerical locks for Cross-2002 spin transfer, variable
## normal restitution, and the dry / wet surface toggle.

var ball: BallPhysics
var cfg: PhysicsConfig


func before_each() -> void:
	cfg = (load("res://resources/PhysicsConfig.tres") as PhysicsConfig).duplicate(true)
	# Default: Cross + variable on, grass off (deterministic), drag off
	cfg.grass_roughness_enabled = false
	cfg.drag_coeff = 0.0
	cfg.surface_wet = false
	ball = BallPhysics.new()
	ball.config = cfg
	add_child(ball)


func after_each() -> void:
	if is_instance_valid(ball):
		ball.queue_free()
	ball = null
	cfg = null


# --- Variable restitution -------------------------------------------------

func test_variable_restitution_decreases_with_velocity() -> void:
	cfg.variable_restitution_enabled = true
	var e_slow: float = ball._restitution_at_velocity(2.0)
	var e_fast: float = ball._restitution_at_velocity(20.0)
	assert_lt(e_fast, e_slow, "e_n must decrease with |v_n| (got slow %.3f, fast %.3f)" % [e_slow, e_fast])
	assert_almost_eq(e_slow, cfg.restitution_base * exp(-2.0 / cfg.restitution_v_ref), 1e-6,
		"e_n at slow speed must follow the exponential formula")


func test_variable_restitution_disabled_returns_base() -> void:
	cfg.variable_restitution_enabled = false
	assert_eq(ball._restitution_at_velocity(20.0), cfg.restitution_base,
		"When disabled, e_n must equal e_base")


# --- Cross-2002 -----------------------------------------------------------

func test_cross_backspin_loses_forward_speed() -> void:
	# Ball moving +X with strong backspin (top axis = -Z, ω around +Z?
	# For dir +X, top_axis = UP × dir = (0,0,-1); backspin = -ω along
	# top_axis, so ω = (0, 0, +k) with k > 0). Friction at contact
	# opposes the contact-point velocity, which for backspin points
	# FORWARD relative to motion (v_t plus −r·(ω×n) where n=+Y).
	# Friction therefore decelerates the linear v_t.
	cfg.cross_2002_enabled = true
	cfg.bounce_e_t = 0.5
	cfg.bounce_mu_s = 0.4
	var v_in: Vector3 = Vector3(20.0, -5.0, 0.0)
	var omega_in: Vector3 = Vector3(0.0, 0.0, 30.0)   # heavy backspin
	var out: Dictionary = ball._bounce_cross_2002(v_in, omega_in, Vector3.UP)
	var v_out: Vector3 = out.velocity
	assert_lt(v_out.x, v_in.x,
		"Backspin must remove forward speed at the bounce (v_in.x %.2f, v_out.x %.2f)" % [v_in.x, v_out.x])
	assert_gt(v_out.y, 0.0, "Outgoing y must be positive (ball leaves the ground)")


func test_cross_topspin_keeps_or_gains_forward_speed() -> void:
	# Topspin (ω around -Z for +X motion) → contact-point velocity is
	# REDUCED relative to v_t (or even reversed). Friction at contact
	# opposes a smaller (or backwards) v_c, so the linear forward speed
	# is barely reduced — and with strong topspin can even gain.
	cfg.cross_2002_enabled = true
	var v_in: Vector3 = Vector3(20.0, -5.0, 0.0)
	# Top axis for +X motion = (0,0,-1). Pure topspin → ω = (0,0,-k)
	# enough that r·|ω| >> |v_t|, so v_c flips sign and friction pushes
	# forward.
	var omega_in: Vector3 = Vector3(0.0, 0.0, -200.0)
	var out: Dictionary = ball._bounce_cross_2002(v_in, omega_in, Vector3.UP)
	var v_out: Vector3 = out.velocity
	assert_gt(v_out.x, v_in.x * 0.95,
		"Heavy topspin should not slow the forward speed below 95%% (in %.2f, out %.2f)" % [v_in.x, v_out.x])


func test_cross_spin_changes_omega() -> void:
	# Any bounce with v_c ≠ 0 must produce some Δω.
	cfg.cross_2002_enabled = true
	var v_in: Vector3 = Vector3(15.0, -10.0, 0.0)
	var omega_in: Vector3 = Vector3.ZERO
	var out: Dictionary = ball._bounce_cross_2002(v_in, omega_in, Vector3.UP)
	var omega_out: Vector3 = out.angular_velocity
	assert_gt(omega_out.length(), 0.0,
		"A purely tangential incoming velocity must transfer some spin to the ball")


# --- Surface toggle -------------------------------------------------------

func test_wet_surface_reduces_friction() -> void:
	cfg.surface_wet = false
	var mu_dry: float = ball._mu_s()
	cfg.surface_wet = true
	var mu_wet: float = ball._mu_s()
	assert_lt(mu_wet, mu_dry,
		"Wet μ_s must be lower than dry (dry %.3f, wet %.3f)" % [mu_dry, mu_wet])


func test_wet_surface_reduces_rolling_friction() -> void:
	cfg.surface_wet = false
	var roll_dry: float = ball._rolling_friction()
	cfg.surface_wet = true
	var roll_wet: float = ball._rolling_friction()
	assert_lt(roll_wet, roll_dry, "Wet rolling friction must be lower than dry")
