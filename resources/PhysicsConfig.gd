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
@export var variable_restitution_enabled: bool = true   ## e_n(v_n) = e_base · exp(-|v_n|/v_ref)
@export var cross_2002_enabled: bool = true     ## Use the Cross-2002 spin
                                                ## transfer model at hard bounces.
                                                ## Falls back to the simple
                                                ## tangent-dampening bounce when off.
@export var friction: float = 0.3               ## tangential slip loss applied
                                                ## ONLY at hard bounces when the
                                                ## simple bounce model is selected.
                                                ## Cross-2002 uses bounce_mu_s.
@export var rolling_friction_coeff: float = 0.3 ## μ_r, dimensionless. Decel of a
                                                ## rolling ball is μ_r·g (m/s²). 0.3
                                                ## on dry natural grass produces
                                                ## a ~2.9 m/s² deceleration: a 20 m/s
                                                ## roll covers ~68 m before stopping
@export var grass_roughness_enabled: bool = true
@export var grass_roughness_min_speed: float = 5.0   ## m/s of tangential speed
                                                     ## below which grass is "still"
                                                     ## and bumps don't fire
@export var grass_roughness_threshold: float = 0.30  ## noise output > this triggers
                                                     ## a micro-bump on rising edge
@export var grass_roughness_kick: float = 0.9        ## m/s vertical kick at full
                                                     ## speed (linearly scaled by
                                                     ## (v_t - min_speed) / 20).
                                                     ## At v_t = 25 m/s peak height
                                                     ## ~4 cm, matching the user
                                                     ## "rasoterra max ~4 cm" target
@export var grass_roughness_frequency: float = 0.6   ## bumps per metre of travel
                                                     ## (FastNoiseLite frequency on
                                                     ## the 2D position sample)
@export var restitution_v_ref: float = 8.0      ## v_ref in exp decay (Sprint 3)
@export var bounce_e_t: float = 0.5             ## Cross 2002 tangential restitution
@export var bounce_mu_s: float = 0.4            ## Cross 2002 static friction (dry)
@export_group("Surface")
@export var surface_wet: bool = false           ## global toggle (Sprint 3); Sprint 4+
                                                ## may add per-zone surfaces
@export var bounce_mu_s_wet: float = 0.22       ## ~half of dry on wet grass
@export var rolling_friction_wet: float = 0.15  ## ~half of dry rolling
@export var restitution_base_wet: float = 0.55  ## slightly absorbent vs dry
@export var grass_roughness_kick_wet: float = 0.5 ## wet turf is smoother

# ---- Magnus (activated in Sprint 2) --------------------------------------
@export_group("Magnus")
@export var magnus_enabled: bool = true                  ## flipped on Sprint 2
@export var magnus_spin_param_cap: float = 1.5           ## cap on S = r*|ω|/|v|
@export var magnus_min_speed: float = 0.5                ## skip Magnus when |v| below
                                                         ## this (would explode S = r|ω|/|v|)

# ---- Knuckleball (activated in Sprint 2) ---------------------------------
@export_group("Knuckleball")
@export var knuckle_enabled: bool = true              ## flipped on Sprint 2
@export var knuckle_threshold_spin: float = 2.0       ## rad/s — gate, only when
                                                      ## |ω| below this
@export var knuckle_threshold_speed: float = 15.0     ## m/s — gate, only when
                                                      ## |v| above this
@export var knuckle_amplitude: float = 8.0            ## m/s² peak smooth wobble
                                                      ## (Asai et al. measured ~10 N
                                                      ## at 30 m/s → ~23 m/s² on a
                                                      ## 0.43 kg ball; 8 is the
                                                      ## tunable arcade DRAFT)
@export var knuckle_seed: int = 1337                  ## Simplex seed
@export var knuckle_noise_frequency: float = 1.2      ## base wobble freq (peaks/s)
@export var knuckle_spike_frequency_mul: float = 4.5  ## spike layer freq = base × this
@export var knuckle_spike_threshold: float = 0.45     ## |spike noise| > this triggers
                                                      ## a transient boost (the "snap"
                                                      ## events that make the ball
                                                      ## suddenly veer in real life)
@export var knuckle_spike_amplitude_mul: float = 1.8  ## extra acceleration multiplier
                                                      ## applied above threshold
