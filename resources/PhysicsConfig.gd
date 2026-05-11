class_name PhysicsConfig
extends Resource

## Physics parameters Resource for the IssNostalgia ball.
## All coefficients live here. `BallPhysics` and any predictor read this
## resource — never hardcode physical constants in scripts.
##
## See docs/PHYSICS_LOG.md for the validated values per sprint.

# ---- Universal physical constants (rarely tuned) -------------------------
@export_group("Universe")
@export var air_density: float = 1.225          ## kg/m^3, ICAO sea-level
@export var gravity: float = 9.81               ## m/s^2, terrestrial

# ---- Ball properties (FIFA Law 2 standard) -------------------------------
@export_group("Ball")
@export var ball_mass: float = 0.43             ## kg
@export var ball_radius: float = 0.11           ## m

# ---- Aerodynamic drag (active Sprint 1+) ---------------------------------
@export_group("Drag")
@export var drag_coeff: float = 0.47            ## Cd, smooth sphere

# ---- Ground interaction (Sprint 3 will activate variable model) ----------
@export_group("Ground")
@export var restitution_base: float = 0.6       ## e_base in e_n(|v_n|)
@export var friction: float = 0.3               ## tangential slip loss applied
                                                ## ONLY at hard bounces (see
                                                ## BallPhysics.BOUNCE_SIGNAL_MIN_SPEED).
                                                ## Soft / rolling contacts use
                                                ## `rolling_friction_coeff` instead.
@export var rolling_friction_coeff: float = 0.3 ## μ_r, dimensionless. Decel of a
                                                ## rolling ball is μ_r·g (m/s²). 0.3
                                                ## on dry natural grass produces
                                                ## a ~2.9 m/s² deceleration: a 20 m/s
                                                ## roll covers ~68 m before stopping
@export var restitution_v_ref: float = 8.0      ## v_ref in exp decay (Sprint 3)
@export var bounce_e_t: float = 0.5             ## Cross 2002 tangential restitution
@export var bounce_mu_s: float = 0.4            ## Cross 2002 static friction

# ---- Magnus (activated in Sprint 2) --------------------------------------
@export_group("Magnus")
@export var magnus_enabled: bool = false
@export var magnus_spin_param_cap: float = 1.5  ## cap on S = r*|omega|/|v|

# ---- Knuckleball (activated in Sprint 2) ---------------------------------
@export_group("Knuckleball")
@export var knuckle_enabled: bool = false
@export var knuckle_threshold_spin: float = 2.0   ## rad/s
@export var knuckle_threshold_speed: float = 15.0 ## m/s
@export var knuckle_amplitude: float = 0.3
