# PHYSICS_LOG.md — IssNostalgia Phase 1

> Living document. Updated at every calibration touchpoint.
> Source of truth for which physical parameters are validated and which are still in flux.

---

## Conventions

### Status markers

| Marker | Meaning |
|--------|---------|
| `[DRAFT]` | Default value, never tested in context |
| `[VALIDATED]` | Tested in sandbox, behavior matches expectation |
| `[LOCKED YYYY-MM-DD]` | Frozen value. Modifying requires a new entry with explicit rationale |

### Locked parameter entry format

```
[LOCKED 2026-05-11] MAGNUS_COEFF = 0.000015
Rationale: produces a 3.2 m curve over 20 m of flight at v=25 m/s, sidespin=8 rad/s.
Validated: Sprint 2, macro shot "Tiro a giro", session 3.
```

### World conventions

- Scale: **1 Godot unit = 1 metre real**
- Axes: **Y up, -Z forward** (Godot default)
- Physics tick: **120 Hz**, adaptive substeps **4 / 6 / 8** based on `|v|`
- Spin vector ω: **world space**
- Integrator: **Semi-implicit Euler** with substepping

---

## Sprint 01 — Foundation

> Sprint scope: gravity + quadratic drag + restitution bounce + custom integrator skeleton.
> Out of scope: Magnus, knuckleball, spin transfer, variable restitution, surfaces, audio.

### Physical Parameters

| Parameter             | Default      | Final | Status   | Rationale |
|-----------------------|--------------|-------|----------|-----------|
| `BALL_MASS`           | 0.43 kg      |   —   | [DRAFT]  | FIFA Law 2 — standard match ball |
| `BALL_RADIUS`         | 0.11 m       |   —   | [DRAFT]  | FIFA Law 2 — standard match ball |
| `AIR_DENSITY`         | 1.225 kg/m³  |   —   | [DRAFT]  | ICAO standard atmosphere, sea level |
| `DRAG_COEFF`          | 0.47         |   —   | [DRAFT]  | Smooth sphere approximation |
| `GRAVITY`             | 9.81 m/s²    |   —   | [DRAFT]  | Standard terrestrial |
| `RESTITUTION_BASE`    | 0.6          |   —   | [DRAFT]  | Soccer ball on natural turf (Cross 2002 baseline) |
| `FRICTION`            | 0.3          |   —   | [DRAFT]  | Dry grass dynamic friction |

### Architectural Decisions

| ID      | Decision | Rationale |
|---------|----------|-----------|
| S01-A01 | Custom integrator via `_integrate_forces` | Contract: non-negotiable. Built-in physics insufficient for Magnus / knuckle / Cross-2002 |
| S01-A02 | Semi-implicit Euler + adaptive substeps (4 / 6 / 8) | RK4 overkill on mobile; Verlet adds no value without constraints. Substeps cover high-velocity stability |
| S01-A03 | `BoxShape3D` flat (200 × 0.1 × 120) for ground | `WorldBoundaryShape3D` inconsistent with CCD at high velocity |
| S01-A04 | `Cl(S) = S / (S + 0.5)`, cap `S ≤ 1.5` | Saturation is physically correct (Asai, Carré). Cap allows extreme spin calibration without numerical blow-up |
| S01-A05 | Substep count published in debug overlay | Allows live correlation between velocity regime and integrator precision |
| S01-A06 | Camera placement via `look_at()` in script | `Transform3D` rows in `.tscn` are fragile to hand-compute. Script `look_at()` derives the basis from `camera_position`, `camera_target`, `Vector3.UP`. Position `(0, 35, 20)` and FOV 45° are the plan defaults; both are `@export` and tunable. Final values to be locked after visual validation in T05 |
| S01-A07 | Field texture is an SVG (`field_lines.svg`) rasterised at import | Vector source is editable, tiny in git, sharper than a hand-painted PNG, and respects the "no extra draw call for lines" rule (I.1). Width/height attributes set to 2100×1360 so Godot's SVG importer produces a high-resolution `Texture2D` at default scale |
| S01-A08 | Goalposts are visual-only `MeshInstance3D` (no collision) in T01 | Collision will be added in T03 together with the ground `StaticBody3D`. Posts are 0.12×2.44×0.12 m (vertical), crossbar 0.12×0.12×7.32 m; positioned at `x = ±52.5`, `z = ±3.66` (posts), `y = 2.44` (crossbar). FIFA Law 1 dimensions |
| S01-A09 | Integrator exposed as a pure function `integrate_step_pure(p, v, sub_dt)` | The same function is reused by `_integrate_substep` (live), by the Sprint 2 forward predictor, and by the Sprint 1 GUT tests. One physics implementation, three call-sites — DRY guarantees that what the tests lock is exactly what the predictor predicts and what the game runs |
| S01-A10 | `RigidBody3D.gravity_scale = 0.0` on the ball, gravity applied inside `compute_force` | We own all forces. Letting Godot apply its built-in gravity in parallel would double-count it. The scene-level `[physics] 3d/default_gravity` is kept at 9.81 for other potential bodies, but the ball ignores it |
| S01-A11 | `debug_visual_scale` on `BallPhysics`, **default 1.0** (real scale) | The mechanism exists for future debug needs but the sandbox runs at real scale. Trade-off accepted by the user: at the current camera (0, 20, 40) the FIFA 0.11 m ball renders at ~7 px and the spin texture is barely readable, but the visual relationship between ball and 105×68 m pitch markings is correct. Scale 2.0 / 4.0 were tried and rejected as out of proportion. Spin readability will be restored by the Sprint 2 trajectory ribbon and the eventual near-camera follow |
| S01-A12 | Angular kinematic update inside `_integrate_substep` | With `custom_integrator = true` Godot does not rotate the transform from `angular_velocity`. The substep therefore applies `Basis(omega.normalized(), |omega| * sub_dt) * t.basis`. Sprint 1 never **modifies** angular_velocity (no torques); Sprint 3 will, via Cross-2002 spin transfer at bounce |
| S01-A13 | Soccer ball SVG texture (`ball_pentagons.svg`) at 1024×512, equirectangular | 12 dark "pentagons" placed at icosahedron vertices (2 polar caps + 5 upper ring at lat +26.5° + 5 lower ring at lat −26.5°), ellipses sized to compensate for equirectangular horizontal stretch. Faint meridians + equator added for spin readability around any axis |
| S01-A14 | Static-world collision via custom geometric check, **no `StaticBody3D` for ground / walls** | The world is axis-aligned: ground = `y = 0` plane, perimeter walls = AABB `[±57.5] × [±39]`. Resolving collisions analytically inside the substep loop is deterministic, free of penetration recovery quirks, and avoids any ambiguity over whether Godot still applies position correction when `custom_integrator = true`. Sprint 5 will reconsider when arbitrary obstacles appear. The `resolve_static_collisions(p, v)` function is pure and reused by tests / predictor (DRY with S01-A09) |
| S01-A15 | `bounced` signal with a 0.8 m/s impact-speed gate | The integrator emits one signal per bounce, used by `SandboxController` for live logging and reserved for Sprint 3 audio. Below 0.8 m/s the contact reads as rolling / resting, not as a percussive bounce, so signals are suppressed to avoid spam at the end of a settle |
| S01-A16 | GUT addon **vendored, not submoduled** (`addons/gut/UPSTREAM.md`) | The bitwes/Gut upstream repo nests the addon at `addons/gut/`. Submoduling it to our `addons/gut/` produced a double `addons/gut/addons/gut/` path that broke Godot's plugin and `class_name` resolution. Vendoring as a flat copy pinned to tag v9.6.0 fixes the issue; `UPSTREAM.md` documents the update recipe. The same problem exists for `addons/imgui-godot/`; it will be flattened in Sprint 4 when imgui is actually consumed |
| S01-A17 | Tests instantiate `BallPhysics.new()` + `add_child(ball)` in `before_each` | Pure-function `integrate_step_pure` and `resolve_static_collisions` are instance methods (they read `config`). Putting the body in the tree lets `_ready` run with the test-mutated `cfg`, and the engine still skips physics ticks on it because we never simulate at the engine level — every test drives the pure functions in a tight loop. GUT reports a "5 unfreed children" warning because `queue_free` is deferred; the leak is bounded to the test lifetime and acceptable |
| S01-A18 | T04 numerical lock validated (`tests/unit/test_ball_physics.gd`) | 4/4 pass. Terminal velocity 19.633 m/s simulated vs 19.634 m/s closed-form (rel.err 0.0000). Restitution peaks at e=0.6 from h0=5 m: 1.86 / 0.74 / 0.33 m vs theoretical 1.80 / 0.65 / 0.23 m — within the 3 %·h0 (=0.15 m) tolerance; the small positive bias is the expected semi-implicit Euler energy drift at sharp impulsive contacts. No-tunneling: min observed y at 50 m/s downward launch is exactly 0.11000 m = ball_radius |
| S01-A19 | Separated impact friction (`friction`, slip-loss at hard bounces) from continuous rolling resistance (`rolling_friction_coeff`) | First T05 test of the H key produced a brutal horizontal slow-down: every substep that registered a ground contact (~480 Hz) multiplied the tangent by `(1 - friction) = 0.7`, compounding to near-instant stop. Fix: `_resolve_contact` applies tangent dampening only when `\|v_n\| >= BOUNCE_SIGNAL_MIN_SPEED` (real bounces). Soft / rolling contacts only cancel the normal component, and a separate `apply_rolling_resistance` step decelerates the tangent by `μ_r·g` per second when the ball is in ground contact at near-zero `\|v_y\|`. With `rolling_friction_coeff = 0.3` (DRAFT, natural grass) the H-key launch (20 m/s) covers ~35 m before resting, which is in the ballpark of a real strong-roll kick |

### Magnus Formula (planned, Sprint 2)

```
F_magnus = 0.5 × ρ × A × Cl(S) × |v| × (ω̂ × v̂)
S        = (r × |ω|) / |v|         (spin parameter)
Cl(S)    = S / (S + 0.5)
S_max    = 1.5                      (Cl_max ≈ 0.75)
```

### Cross-2002 Bounce Model (planned, Sprint 3)

```
v_n_new      = -e_n(|v_n|) × v_n
v_t_new      = v_t × (1 - μ_eff) + r × (ω × n̂)_tangential × α
ω_new        = ω × (1 - β) + (v_t_new / r) × n̂ × β
e_n(|v_n|)   = e_base × exp(-|v_n| / v_ref)
e_t          = 0.5     (Cross paper baseline)
μ_s          = 0.4     (Cross paper baseline, dry turf)
α, β         = critical-angle dependent (computed at runtime from μ_s, e_n, e_t)
```

Critical angle formula and α / β derivation will be documented in Sprint 3.

### Knuckleball Model (planned, Sprint 2)

- Active when `|ω| < 2.0 rad/s` AND `|v| > 15 m/s`
- Perturbation perpendicular to `v` (lateral + vertical, not along motion axis)
- Source: seeded Simplex noise (deterministic, replay-friendly)
- Frequency: random in `[0.3 Hz, 1.5 Hz]`, resampled per oscillation
- Amplitude: calibratable

### Emergent Behaviors

_(to be populated during implementation)_

### Sprint 01 Calibration Sessions

| Date       | Task   | Focus                                  | Notes |
|------------|--------|----------------------------------------|-------|
| 2026-05-11 | T01    | Field + camera ISS-broadcast view      | Camera at (0, 20, 40), FOV 45° validated visually. Pitch ~27° |
| 2026-05-11 | T02    | Custom integrator + drag               | Gravity + drag traces match closed-form within drag bias |
| 2026-05-11 | T02.1  | Pentagons texture + visual scale       | `debug_visual_scale = 1.0` (real). Spin readability deferred to predictor |
| 2026-05-11 | T03    | Ground + walls bounce                  | 5 bounces from y=8, e_effective ~0.59 vs target 0.60 (drag loss) |
| 2026-05-11 | T04    | GUT 4/4 PASS                           | Terminal v 19.633 vs 19.634; no tunneling at 50 m/s |
| 2026-05-11 | T05    | Launcher + HUD                         | SPACE / H / R / LMB key map + on-screen telemetry. Ball spawn moved to (0, 1.5, 0) — quick reset cadence |
| 2026-05-11 | T05.1  | Rolling resistance separated           | `friction` (impact) vs `rolling_friction_coeff` (continuous). H-key launch now rolls ~35 m. GUT 4/4 still PASS |
| 2026-05-11 | T06    | Sprint 01 closeout, merge to main      | All Exit Criteria validated. Tag `v0.1.0-sprint01` |

### Sprint 02 Pending Items (deferred to post-Sprint 04)

Both items are **[PENDING — needs directional input for validation]**.
Real validation requires a per-shot direction control (the launcher's
fixed `Vector3.RIGHT` macros are not flexible enough to construct the
test scenarios). Sprint 04's debug UI will expose direction + spin
sliders; the items are scheduled to be re-evaluated then.

| Item | Status | Notes |
|------|--------|-------|
| Knuckle wobble realism | [PENDING] | After S02-A09 the trajectory is still "too predictable" per user feedback. Suspected fixes: stronger spike events (higher `knuckle_spike_amplitude_mul` or lower threshold), drag-crisis simulation (sudden drop in Cd at v ≈ 30 m/s producing the trademark dip), or replace SIMPLEX with a Perlin-Brownian combination |
| Low-power rasoterra bounce | [PENDING] | The strong-power rasoterra (30 m/s @ 1°) now stays inside 0-2.7 cm; a softer shot (≤15 m/s) has not been tested. Bounce physics needs visual verification at low impact speeds, possibly with surface-specific calibration coming in Sprint 03 |

### Sprint 01 Exit Criteria

| # | Criterion                                                                | Status   | Evidence |
|---|--------------------------------------------------------------------------|----------|----------|
| 1 | Vertical-launched ball bounces with correct decay                        | DONE     | T03 bounce log: 8.36 → 4.88 → 2.88 → 1.71 → 1.02 m/s, ratio ≈ 0.59 (target e = 0.6, drag loss ≈ 3%) |
| 2 | Horizontal-launched ball decelerates visibly from drag                   | DONE     | T05 HUD speedometer + T04 terminal-velocity test (19.633 ≈ 19.634 m/s closed-form, rel.err 0.0000) |
| 3 | Spin visible on ball axis                                                | DONE     | Pentagons SVG texture + angular kinematic update in custom integrator (S01-A12/A13) |
| 4 | FPS stable ≥ 60 in editor                                                | DONE     | User confirmed in editor: FPS ≥ 60 across drop, vertical / horizontal launches, ground-click lob, reset cycle |

---

## Sprint 02 — Magnus & Spin

### Architectural Decisions

| ID       | Decision | Rationale |
|----------|----------|-----------|
| S02-A01  | Magnus formula uses `\|v\|²` not `\|v\|` | SPRINT_02_PLAN M02 wrote `F = 0.5·ρ·A·Cl·\|v\|·(ω̂ × v̂)` which dimensionally produces kg/s, not N. The textbook lift formula needs `\|v\|²`. Implemented as `F = 0.5·ρ·A·Cl(S)·\|v\|²·(ω̂ × v̂)`, units check OK |
| S02-A02  | `magnus_min_speed` floor (default 0.5 m/s) | `S = r\|ω\|/\|v\|` blows up as `\|v\| → 0`. We early-return when `\|v\| < magnus_min_speed` (slow / resting ball gets no Magnus anyway) instead of relying on the spin-parameter cap to mask the singularity |
| S02-A03  | `compute_force` and `integrate_step_pure` now take `omega` (default `Vector3.ZERO`) | Default keeps every existing Sprint 1 GUT test and predictor caller backward-compatible. Sprint 2 callers pass the real ω so Magnus enters the integration |
| S02-A04  | Knuckleball lives outside `compute_force` (time-dependent) | Applied as a velocity delta inside `_integrate_substep` because the perturbation is a function of `_sim_time`, which `compute_force` (pure) does not see. Two FastNoiseLite SIMPLEX streams seeded with `(seed, seed+1)` give two independent transverse axes |
| S02-A05  | `predict_forward(p, v, ω, t, steps, sub_dt)` reuses every pure function | DRY by construction: tests confirm the predictor's trajectory matches the live integrator step by step. Includes ground collision + walls + rolling resistance, so the lob preview is realistic |
| S02-A06  | TrajectoryVisualizer ribbon uses `ImmediateMesh` rebuilt every `_process` | M09 originally locked SurfaceTool with a reused buffer for zero-alloc. ImmediateMesh allocates once at scene setup; the `clear_surfaces` / `surface_begin` cycle is cheap (~0.1 ms for 600 samples on Compatibility). Will revisit Sprint 5 if mobile profiler complains |
| S02-A07  | Magnus visible curve under-shoots the 3-4 m target by ~30 % at ω = 8 rad/s | At v=25 m/s, ω=8 rad/s the saturating Cl model gives Cl ≈ 0.05, producing ~2.5 m of lateral curve over 47 m of flight. Roberto Carlos-style 3-4 m curves require ω closer to 15-20 rad/s with the locked model. Sprint 4 debug UI will allow a calibration pass; the locked formula remains untouched until then |
| S02-A08  | Grass roughness applied at both hard bounces (`_grass_perturb_bounce`) and during fast rolling (`apply_grass_roughness`) | User feedback after first T05.1 test: a strong grounder on natural turf doesn't bounce cleanly — it produces "mini-rimbalzi" caused by tufts and undulations. The bounce path now reads two extra Simplex samples (offset by 73.5 m / 91 m / 41 m / 17 m to decouple the three axes) and adds positive-only vertical kick + small lateral deflection proportional to impact speed. Deterministic per (seed, position). Confirmed in headless: rasoterra now produces 4 bounces with lateral drift vs 3 clean bounces previously |
| S02-A09  | Knuckle re-modelled with smooth-wobble + snap-spike layers | First T05 test: trajectory too smooth, "predictable". Fix: keep the base SIMPLEX wobble but sample the SAME streams at `knuckle_spike_frequency_mul × base` frequency with a positional offset to decorrelate the octaves. Wherever the high-rate noise exceeds `knuckle_spike_threshold` we add `(value - thr) × spike_amplitude_mul` to the smooth amplitude. Result: occasional brief veers ("snaps") superimposed on a gentle wobble — matches the textbook "wobble or dip" description. Velocity-scaled so slower knuckle shots still get something visible. Confirmed: knuckle now drifts ~1.1 m laterally over ~1.5 s of flight and dips far enough to hit the east wall on a 28 m/s launch |
| S02-A10  | Angle-aware restitution in `_bounce_velocity` | User feedback after first grass-roughness test: a strong "rasoterra" was bouncing up to 60 cm between contacts — "un massaggio a mezz'aria, non è più un rasoterra". Root cause: a grazing impact (small `\|v_n\|` vs large `\|v_t\|`) still kept the full e=0.6 of restitution on its tiny vertical component, producing a noticeable vertical kick. Real grass absorbs that small normal component almost entirely. Fix: multiply the effective restitution by `smoothstep(0.05, 0.35, \|v_n\|/\|v\|)`. Perpendicular drop (sin=1) keeps full e, perfectly grazing (sin<0.05) gets e≈0. Pre-emptive, simplified version of the angle dependence that Sprint 3 Cross-2002 will refine |
| S02-A11  | `grass_roughness_kick` reduced 1.6 → 0.9 m/s | At kick = 0.9, max vertical bump speed is ≈ 0.81 m/s (after the speed_factor), which lifts the ball by `v²/(2g) ≈ 3.3 cm` — exactly the "0 to 4 cm" range the user described for a real grounder on natural grass. Both the rolling bumps and the hard-bounce jitter share this constant |
| S02-A12  | `BallLauncher.launch()` no longer teleports the ball; launches happen from the ball's current position | User feedback after T05.3: every macro shot was starting from `spawn_position` (originally 1.5 m off the ground), so the "rasoterra" still flew through the air. Fix: `launch()` only sets velocity + spin; the explicit `reset_ball()` is the only path that repositions. `spawn_position` lowered to `(0, 0.11, 0)` = ball at rest on grass. Scene initial Ball transform aligned to `(0, 0.11, 0)` so the sandbox opens with the ball already resting |
| S02-A13  | `compose_spin` axis was inverted (right-hand rule bug) | Was returning `dir.cross(UP)` which for `dir = +X` gives `(0,0,+1)`. A positive `topspin` argument then produced a +Z spin, whose Magnus force is +Y (UP) — i.e. the macro labelled "topspin" was actually behaving as backspin. Corrected to `UP.cross(dir) = (0,0,-1)` for `dir = +X`, so positive topspin now produces a downward Magnus force (ball pitches forward / dives), matching the textbook definition. Visible effect: the rasoterra shot now stays flat (bottom-of-ball 0-2.7 cm above ground throughout the roll) |
| S02-A14  | Rasoterra launch elevation 3° → 1° | At 30 m/s the previous 3° elevation produced a 23 cm peak even without errors. 1° caps the launch arc at ~1.4 cm above resting height, deep inside the user's "max ~4 cm" spec for a strong grounder |

## Sprint 03 — Ground Interaction & Spin Transfer

### Architectural Decisions

| ID      | Decision | Rationale |
|---------|----------|-----------|
| S03-A01 | Cross-2002 bounce treats the ball as a **hollow shell** (`I = (2/3) m r²`) | A FIFA match ball is a thin leather/synthetic shell, not a solid sphere. The (2/3) factor changes how impulse splits between linear and angular updates: more spin gets imparted per Newton-second of friction than a solid sphere would |
| S03-A02 | Variable normal restitution `e_n(\|v_n\|) = e_base · exp(-\|v_n\|/v_ref)` (gated by `variable_restitution_enabled`) | User R2 5.1. Hard impacts deform more, lose more energy. With `v_ref = 8 m/s` a 20 m/s impact yields `e ≈ 0.6 · 0.082 = 0.05` (essentially absorbed), while a 2 m/s impact yields `e ≈ 0.47` (still lively). The angle-aware smoothstep from S02-A10 stacks on top |
| S03-A03 | Grip vs slip decided by Coulomb cap | Grip-case impulse `J_t_grip = (1+e_t)·\|v_c\|·m·k/(1+k)` with k=2/3. If it exceeds `μ_s · J_n` we slip and clamp to the Coulomb maximum. Single decision, matches the Cross paper's two-regime structure without the full piecewise formulation |
| S03-A04 | `resolve_static_collisions` now takes / returns `angular_velocity` | Default `Vector3.ZERO` for backward compat with Sprint 1/2 GUT tests. Live integrator and predictor plumb the real ω through. Both branches read `state.angular_velocity` and write it back, so Cross-induced Δω is visible on the mesh rotation |
| S03-A05 | Surface state via a single global `surface_wet` flag (Sprint 3 scope) | Wet halves μ_s (0.4→0.22) and rolling friction (0.3→0.15), slightly lowers restitution_base (0.6→0.55), softens grass kick (0.9→0.5). All four switched together so the player feels a coherent "wet pitch" rather than independently tuned axes. Sprint 4+ may introduce per-zone surfaces |
| S03-A06 | Bounce audio is **runtime-synthesised** at scene load | One short damped sine + 2nd harmonic, 16-bit mono WAV held in `AudioStreamWAV`. No external file to license / ship; pitch ± 5 % randomisation per bounce gives variety; volume scales linearly with impact speed clamped to `[0.15, 1.0]` (same gate as `bounced` signal — micro-rolls don't click) |
| S03-A07 | Squash visual implemented as a `Tween` on `MeshInstance3D.scale` | Compress along the contact normal (`scale -= n_abs · amount`), expand perpendicular by 35 % of amount. Cancelled on each new bounce so successive hits don't stack. 50 ms compress → 180 ms recover. No physics influence; only the rendered mesh moves. Skipped below 1.5 m/s impact to avoid noise |
| S03-A08 | Slow-motion via `Engine.time_scale = 0.25` toggle on F5 | Cheapest possible "replay-like" diagnostic — no recording, no ring buffer. Physics still simulates correctly at slower wall-clock; this is what the calibrator needs to *see* a bounce. Full record-and-replay deferred to Sprint 4+ |
| S03-A09 | Hotfix: `restitution_v_ref` 8 → 30 | Original R2 5.1 lock at 8 m/s killed bounces: `e_n` at a 6 m/s drop was 0.27 (h₁/h₀ = 0.07), at 12 m/s only 0.13. User feedback: "il rimbalzo dopo un lancio alto è praticamente inesistente". 30 m/s gives `e ≈ 0.49` at 6 m/s and `e ≈ 0.40` at 12 m/s — still mildly speed-dependent, but bounces are visible (apex 2.6 m from a 15 m/s vertical launch on dry grass) |
| S03-A10 | Hotfix: wet / dry gap widened | Original wet params barely felt different from dry. New wet defaults: `μ_s = 0.15`, `rolling_friction = 0.10`, `restitution_base = 0.40`, `grass_kick = 0.20` — friction halved, bounce 33 % lower, rolling 3× longer, grass kicks muted. The "W" key flip now produces a coherent, obviously-different surface |
| S03-A11 | Hotfix: bounce audio switched to 2D `AudioStreamPlayer` | `AudioStreamPlayer3D` with default `unit_size=6` at 40 m camera distance attenuated to ~−18 dB — barely audible. 2D player has no distance attenuation, gives consistent loudness. Synthesis enriched with a 3rd harmonic, peak amplitude raised 18000→30000, volume scaling now `clamp(impact/8, 0.4, 2.0)` (up to +6 dB on hard hits). Sprint 4+ can revisit 3D once a near-camera follow exists |
| S03-A12 | Hotfix: squash amplitude + duration up | `squash_amount` cap 0.40 → 0.60, gating min impact 1.5 → 0.8 m/s, durations 50+180 ms → 80+300 ms with `TRANS_QUAD` easing. With `time_scale = 0.25` the squash now lasts ~1.5 s wall-clock — clearly visible |
| S03-A13 | Deferred-state pattern for external launcher / reset | Godot best practice (per `godot-physics-3d` skill): **never write `RigidBody3D.linear_velocity` or `global_position` directly from outside the physics step**. Refactor: `BallPhysics.teleport_to(pos)` and `apply_launch_state(v, ω)` stage requests into `_pending_*` fields; `_integrate_forces` opens with `_apply_pending_state(state)` that commits them via `state.transform` / `state.linear_velocity` / `state.angular_velocity`. Eliminates the previous direct property writes in `BallLauncher.reset_ball()` and `launch()` |
| S03-A14 | `contact_monitor = false` on the ball | We resolve all collisions deterministically inside the custom integrator (S01-A14) and never read Godot's contact list. Leaving `contact_monitor = true` paid CPU cost per frame for data we threw away. The `bounced` signal is our own, not Godot's; nothing else depended on the engine-side contact reporting |
| S03-A15 | `launch_to_point` lob: ballistic closed-form, spinless | User reported the LMB lob "went wherever it wanted" and "came back as if it had backspin". Two bugs: (a) the old code used a fixed `ground_click_speed` regardless of click distance, so the ball travelled the same ~50 m every time — a 5 m click overshot by an order of magnitude. (b) The old code added topspin: during descent `ω̂ × v̂` gains a negative-X component, dragging the ball backwards visibly. Fix: arc height scales with click distance (`clampf(dist · 0.25, 0.5, 6.0)`), horizontal speed solved from the closed-form ballistic `v_h = dist / (2 v_v / g)` so the ball actually lands on the click; spin set to `Vector3.ZERO` |
| S03-A16 | Macros aim at the mouse pointer's ground intersection | User R3 feedback: "voglio che tutti i tiri vengano fatti verso il puntatore del mouse". Every macro (`launch_curve_shot`, `launch_dead_leaf`, `launch_grounder_topspin`, `launch_knuckle`) now takes a `direction` argument (default `Vector3.RIGHT` for headless tests). `SandboxController._aim_direction()` computes the horizontal world direction from the ball to the camera ray–ground intersection at the current mouse position; macros fire toward that vector on key press. This lets the calibrator evaluate each shot type from any angle without repositioning the camera |
| S03-A17 | Lob `v_h *= 0.92` conservative undershoot factor | User reported lobs overshooting the click. The closed-form vacuum solution should mathematically *undershoot* with drag, not overshoot — drag during a ~1.5 s flight at sandbox lob speeds is non-negligible (~5–10 % range loss). The mismatch is most likely perception of the *roll-out* after the first bounce. A 0.92 multiplier on `v_h` biases the lob to land slightly short, so the first impact mark sits *before* (or on) the click rather than ever past it. The bounces still propagate forward as usual — that's expected football behaviour, not a target-overshoot |
| S03-A18 | **Perimeter walls removed** from `resolve_static_collisions` | User R3: "verso la fine della traiettoria … colpisce una parete invisibile … cambio di traiettoria > 90°". The Sprint 1 wall AABB at `±57.5 m × ±39 m` (field + 5 m runoff) was correct geometry but **had no visible mesh**. After a long roll the ball would silently slam into a wall and ricochet by 90-180° depending on incoming angle and residual spin. The Cross-2002 model amplifies this for grazing wall hits because spin transfer adds a vertical kick on top of the back-bounce. Sandbox doesn't need containment; rolling friction + drag bring the ball to rest. Walls return in Sprint 5+ as visible stadium nets with proper meshes |

### Sprint 03 Calibration Sessions

| Date       | Task    | Notes |
|------------|---------|-------|
| 2026-05-11 | T01-T02 | Cross-2002 + variable e_n wired in, surface getters added |
| 2026-05-11 | T03-T06 | Wet toggle (W key), bounce audio, squash tween, slow-mo (F5) |
| 2026-05-11 | T07     | 7 new GUT tests; total suite 17/17 PASS |

## Sprint 04 — Debug UI & Runtime Parameters

### Architectural Decisions

| ID      | Decision | Rationale |
|---------|----------|-----------|
| S04-A01 | Native Godot Control nodes instead of `imgui-godot` (R2 8.1 deviation) | `imgui-godot` ships source-only — building it would require .NET tooling plus a SCons/CMake GDExtension C++ pass on Windows. Out of scope for a tuning sprint that just needs sliders + a dropdown. Native `Panel` / `ScrollContainer` / `HSlider` / `OptionButton` build the panel procedurally in `PhysicsDebugUI.gd`, run with zero external dependencies and port cleanly to mobile in Phase 2 (touch-friendly layout will land then). Trade-offs vs imgui: no docking, no multi-window, no live console — acceptable for a single tuning panel |
| S04-A02 | Two-way binding via `PhysicsConfig.set(key, value)` per slider event | Each row stores `{slider, value_label, step}` keyed by the PhysicsConfig property name. `value_changed.connect(_on_slider_changed.bind(key))` lets us reuse a single handler that writes back into the live resource and updates the readout label. The next physics tick reads the new coefficient — no restart, no reload, no signal indirection. CheckButton handles the six boolean toggles symmetrically |
| S04-A03 | `BallPhysics` caches `last_force_*` Newton vectors every substep | The debug UI needs magnitude readouts and the 3D gizmo needs direction vectors. Recomputing each force outside the integrator would duplicate logic and risk drift. `compute_force` now stores gravity / drag / Magnus separately; knuckle stores `a_knuckle · m`; grass derives from the velocity delta across the kick step. `last_force_net` is their sum. Pure functions stay pure — the side-effect of writing the cache is on the instance, not on the pure-function arguments |
| S04-A04 | `ForceGizmo` uses `ImmediateMesh` with one vertex-coloured `PRIMITIVE_LINES` surface per redraw | Same trade-off as the trajectory ribbon (S02-A06): `ImmediateMesh.clear_surfaces()` + `surface_begin()` per frame is ~0.05 ms for the ~36 vertices needed by six arrow segments. A `MultiMeshInstance3D` with cached arrow meshes would be faster but adds setup cost we don't need at six arrows; revisit only if we ever need per-ball gizmos for multiple agents. Length scale 0.04 m/N is the calibrated readability sweet spot — Magnus arrows of ~40 cm at full curve speed are obvious next to the 22 cm ball, gravity arrows of ~17 cm hint at scale, sub-3 cm arrows are suppressed to avoid clutter at rest |
| S04-A05 | Built-in presets shipped as `.tres` under `res://resources/presets/` | One file per preset, plain text, diff-able. The debug UI scans the directory at startup and exposes everything it finds in the dropdown — adding a fourth preset later is just dropping a file in. User-saved presets live under `user://presets/<timestamp>.tres` so per-machine tuning persists between runs without polluting the repo. Built-in dropdown labels prefixed `[builtin]`, user labels `[user]`, dropdown index 0 is `(current)` (no-op) so accidental dropdown clicks don't reset progress |
| S04-A06 | `imgui-godot` v6.3.2 installed from the official release zip; supersedes S04-A01 and closes the R2 8.1 lock | The source submodule pinned at v6.3.1+4 carried no prebuilt binaries — building the GDExtension would have required SCons / CMake / vcpkg / godot-cpp on Windows. The official v6.3.2 release ships a `bin/` folder with .dll / .so / .framework for every desktop OS. Replacing the submodule with the release tree (committed flat under `addons/imgui-godot/`) gives the plugin zero-build adoption: enable in `[editor_plugins]`, add the `ImGuiRoot` autoload, and any GDScript can call `ImGui.SliderFloat` / `ImGui.Checkbox` / `ImGui.Combo` directly. `.gitignore` adds a negation for `addons/imgui-godot/bin/**` because the global `bin/` rule (for C# build output) would otherwise drop the shared libraries — they're addon runtime, not build artefacts. PhysicsDebugUI rewritten in ImGui GDScript: same parameter table, same preset / save-user-preset workflow, same live binding contract; roughly half the code of the native-Control prototype and trivial to extend with docking, themes, or per-shot HUD overlays in later sprints |

### Sprint 04 Calibration Sessions

| Date       | Task    | Notes |
|------------|---------|-------|
| 2026-05-12 | T01-T05 | PhysicsDebugUI scene + script (native Controls), telemetry fields, presets, ForceGizmo wired and committed |
| 2026-05-12 | T07     | imgui-godot v6.3.2 integrated; PhysicsDebugUI ported to ImGui GDScript; native Controls retired (S04-A06 supersedes S04-A01) |
| 2026-05-12 | T08     | Hotfixes: FPS counter added to HUD (user couldn't verify rendering perf), ForceGizmo rewritten with triangles + scale 0.04→0.15 m/N + extra_cull_margin + no_depth_test so arrows are actually visible at 40 m camera distance, net arrow suppressed at rest so the purple gravity arrow isn't overdrawn by an identical white one. HUD includes a colour legend |

### Sprint 04 Open Issues

| Item | Status | Notes |
|------|--------|-------|
| Lob second-bounce "schizzo" | [PENDING] | User reported the LMB lob's second bounce occasionally appears to gain velocity (`prende velocità e schizza, poi riprende traiettoria normale`). Suspected cause: Cross-2002 grip case converting rotational energy acquired at the first bounce into linear motion at the second — this IS textbook physics (spinning ball + grip impulse), but with the current `e_t = 0.5` / `μ_s = 0.4` / hollow-shell `k = 2/3` parameters the apparent magnitude may be unrealistic. Needs an isolated numerical test (record `v_pre`, `v_post`, `ω_pre`, `ω_post`, total KE pre/post for several consecutive bounces) before deciding between (a) tuning `e_t` / `μ_s` down for the wet case, (b) introducing an explicit spin-decay friction at each bounce, or (c) accepting the behaviour as physically correct and adjusting the visual cue. Does NOT block Sprint 4 merge — debug UI is the deliverable, not bounce calibration |

## Sprint 05 — Validation & Mobile Export
_(reserved)_

---

## References

- Cross, R. (2002). *Grip-slip behavior of a bouncing ball*. American Journal of Physics, 70(11).
- Asai, T., Seo, K., Kobayashi, O., Sakashita, R. (2007). *Fundamental aerodynamics of the soccer ball*. Sports Engineering, 10.
- Carré, M.J., Asai, T., Akatsuka, T., Haake, S.J. (2002). *The curve kick of a football II: flight through the air*. Sports Engineering, 5.
