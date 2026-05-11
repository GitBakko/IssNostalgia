# SPRINT 02 — Magnus & Spin System: Plan di Esecuzione

**Progetto:** IssNostalgia
**Fase:** 1 — Physics Sandbox
**Sprint:** 02 — Magnus & Spin System
**Branch:** `sprint/02-magnus`
**Workflow:** Auto mode — Task → Commit `[S02-Txx]` → continua. Checkpoint solo a sprint completato.

---

## 🎯 Obiettivo

Calci a giro, foglia morta, knuckleball — effetti spin visibili e fisicamente coerenti.
Visualizzatore traiettoria passata + predittiva.

---

## 🧱 Decisioni Locked (round 2 round 3 questionnaire)

| ID  | Decisione | Locked in |
|-----|-----------|-----------|
| M01 | Magnus: `Cl(S) = S / (S + 0.5)` saturation, `S_cap = 1.5` | B.1 / B.2 |
| M02 | Magnus formula: `F = 0.5 × ρ × A × Cl(S) × |v| × (ω̂ × v̂)` | round 2 #3.4 |
| M03 | Knuckleball stochastic source: seeded Simplex noise (deterministic) | 4.1 |
| M04 | Knuckleball perturbazione perpendicolare a `v` (no axial) | 4.2 |
| M05 | Knuckleball frequenza `[0.3, 1.5]` Hz, resampled per oscillation | 4.3 |
| M06 | Predictor reuse `integrate_step_pure` (DRY) | H.1 |
| M07 | Predictor includes ground collisions | H.2 |
| M08 | Predictor update rate 15 Hz (every 4 render frames at 60fps) | H.3 |
| M09 | Trajectory ribbon: `SurfaceTool` circular buffer (zero alloc) | G.1 |
| M10 | Ribbon width decrescente verso coda + gradient `rosso→giallo→blu` by speed | G.2 / G.3 |
| M11 | Spin vector `ω` in world space (x=topspin/backspin, y=sidespin, z=rifling) | 2.4 |

---

## 📋 Task

### T01 — Magnus Force
- `BallPhysics._magnus_force(v, ω)` with the locked saturating Cl model
- Gate via `config.magnus_enabled` — default flipped to `true`
- Pure: integrate into `compute_force` so the predictor sees it too

### T02 — Knuckleball
- `BallPhysics._knuckle_force(v, ω, sub_dt)` with seeded `FastNoiseLite` (SIMPLEX)
- Active iff `|ω| < knuckle_threshold_spin` AND `|v| > knuckle_threshold_speed`
- Perpendicular-to-`v` perturbation, noise frequency drawn from `[0.3, 1.5]` Hz per oscillation
- Seed exposed (`config.knuckle_seed`) so a replay reproduces exactly

### T03 — Launcher with full 3-axis Spin
- `BallLauncher.launch_with_spin(velocity, spin_world)` primitive
- Macro shots (kinematic + spin only — Magnus / drag will shape them):
    * **1** — Tiro a giro: 25 m/s, sidespin 8 rad/s, light topspin
    * **2** — Foglia morta: 22 m/s, backspin 6 rad/s, mild sidespin
    * **3** — Rasoterra forte: 30 m/s, topspin 4 rad/s, low arc
    * **4** — Knuckleball: 28 m/s, near-zero spin
- HUD instructions extended
- LMB lob preserved

### T04 — Trajectory Past Ribbon
- `scripts/TrajectoryVisualizer.gd` — Node3D with `ImmediateMesh`
- Ring buffer of `N = 600` recent positions sampled at physics tick (5 s @ 120 Hz)
- Width-decreasing ribbon + speed-gradient material (vertex colors)

### T05 — Forward Predictor
- `BallPhysics.predict_forward(steps, dt)` reusing `integrate_step_pure` (M06)
- Includes `resolve_static_collisions` per step (M07)
- `TrajectoryVisualizer.update_prediction()` called every 4 frames (M08)
- Rendered semi-transparent ahead of ball

### T06 — GUT Tests
- `test_magnus_zero_spin_zero_force` — `|ω|=0` ⇒ `F_magnus = 0`
- `test_magnus_curve_direction` — sidespin produces lateral curvature consistent with `ω × v̂`
- `test_knuckle_deterministic_with_seed` — same seed ⇒ same trajectory bytewise
- `test_predictor_matches_simulation` — predictor and real integrator stay within ε for a deterministic launch

### T07 — Closeout
- PHYSICS_LOG.md updated
- PR `sprint/02-magnus → main`, merge commit
- Tag `v0.2.0-sprint02` on main

---

## 🚪 Exit Criteria

- [ ] Sidespin sinistro curva sinistra visibile e coerente
- [ ] Backspin forte → rimbalzo che rallenta o arretra
- [ ] Topspin → palla che accelera in avanti al rimbalzo
- [ ] Knuckleball percepibile ma non caotico con spin quasi zero
- [ ] Traiettoria passata visibile come ribbon
- [ ] Predictor visibile e coerente con simulazione reale
- [ ] GUT 4 + 4 = 8 tests, all PASS

---

## 📦 Out of Scope (rimangono Sprint 3+)

- Spin transfer al rimbalzo (Cross 2002) — Sprint 3
- Variable restitution `e(v_n)` — Sprint 3
- Surface zones — Sprint 3
- Audio rimbalzo — Sprint 3
- Squash visivo — Sprint 3
- ImGui debug UI — Sprint 4
- APK Android — Sprint 5
