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
| S01-A11 | `debug_visual_scale` on `BallPhysics`, default 4.0 in the sandbox | At the chosen camera (0, 20, 40) the real 0.11 m ball is ~7 px wide — too small to read the spin. The scale enlarges the `MeshInstance3D` only; the `CollisionShape3D` and every physics formula keep the FIFA 0.11 m radius. Cosmetic, sandbox-only, set to 1.0 once a near-camera follow system exists |
| S01-A12 | Angular kinematic update inside `_integrate_substep` | With `custom_integrator = true` Godot does not rotate the transform from `angular_velocity`. The substep therefore applies `Basis(omega.normalized(), |omega| * sub_dt) * t.basis`. Sprint 1 never **modifies** angular_velocity (no torques); Sprint 3 will, via Cross-2002 spin transfer at bounce |
| S01-A13 | Soccer ball SVG texture (`ball_pentagons.svg`) at 1024×512, equirectangular | 12 dark "pentagons" placed at icosahedron vertices (2 polar caps + 5 upper ring at lat +26.5° + 5 lower ring at lat −26.5°), ellipses sized to compensate for equirectangular horizontal stretch. Faint meridians + equator added for spin readability around any axis |

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

_(to be populated per session — date, focus, before / after values, observations)_

---

## Sprint 02 — Magnus & Spin
_(reserved)_

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
