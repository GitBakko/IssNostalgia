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

## Sprint 03 — Ground Interaction & Spin Transfer
_(reserved)_

## Sprint 04 — Debug UI & Runtime Parameters
_(reserved)_

## Sprint 05 — Validation & Mobile Export
_(reserved)_

---

## References

- Cross, R. (2002). *Grip-slip behavior of a bouncing ball*. American Journal of Physics, 70(11).
- Asai, T., Seo, K., Kobayashi, O., Sakashita, R. (2007). *Fundamental aerodynamics of the soccer ball*. Sports Engineering, 10.
- Carré, M.J., Asai, T., Akatsuka, T., Haake, S.J. (2002). *The curve kick of a football II: flight through the air*. Sports Engineering, 5.
