# RESEARCH_INDEX.md

**Phase 0 — Knowledge Base Research** for IssNostalgia Phase 2 (Game Mechanics).
Generated 2026-05-13 by 9 Sonnet 4.6 research agents (R01–R09) running in parallel.
Findings stored in Ruflo AgentDB under namespace `IssNostalgia/research`, vector-indexed
via HNSW + ONNX embeddings (`Xenova/all-MiniLM-L6-v2`, 384-dim, L2-normalized).

---

## Summary

| # | Topic | Findings | HIGH priority | Status |
|---|-------|---------:|--------------:|--------|
| R01 | Player Movement in Football Games | 7 | 4 | ✅ |
| R02 | Ball Possession & Control System | 7 | 4 | ✅ |
| R03 | Shooting & Passing Feel | 7 | 5 | ✅ |
| R04 | Goalkeeper Behavior Patterns | 6 | 5 | ✅ |
| R05 | Static / Reactive Formation AI | 7 | 3 | ✅ |
| R06 | Camera Systems for Football | 7 | 4 | ✅ |
| R07 | Input & Controls for Mobile Sports | 7 | 4 | ✅ |
| R08 | Performance & Optimization (~10 entities) | 7 | 4 | ✅ |
| R09 | Tricks & Shortcuts from the Industry | 7 | 4 | ✅ |
| **TOTAL** |  | **62** | **37** | |

### AgentDB State

- Backend: `sql.js + HNSW`, version 3.0.0
- Embeddings: ONNX `Xenova/all-MiniLM-L6-v2`, 384-dim, euclidean, L2-norm = 1.0
- Coverage: 102 / 102 entries with embeddings (100 %)
- `IssNostalgia/research` namespace: **62 keys** (`research:R0X:finding-NN`)
- Sample search test: `"possession magnetic ball"` → top hit `research:R02:finding-07` (similarity 0.72), search time 8.86 ms ✅

### Phase 0 Exit Criteria

- [x] R01–R09 each ≥ 3 findings (min 6, mostly 7)
- [x] AgentDB Vectors > 0 (62 in namespace, 100 % embedding coverage)
- [x] `docs/RESEARCH_INDEX.md` created
- [x] ≥ 1 HIGH per topic (37 HIGH total)
- [x] Memory search smoke test passes (`possession magnetic ball` returns R02 cluster)

**Phase 0 COMPLETE.** Sprint 6 may begin.

---

## R01 — Player Movement in Football Games

| # | Source | Finding | Applicability | Priority | Used in Sprint |
|---|--------|---------|---------------|----------|----------------|
| 01 | RLBot Wiki — Useful Game Values (Psyonix / GDC 2018) | RL braking decel −35 m/s² (~6.7× accel), coasting −5.25 m/s²; max angular vel 5.5 rad/s; 90° turn ~0.775 s | Add `decel: float` to `PhysicsConfig.tres`, target ~40-60 m/s²; spec's single 20 m/s² will feel sluggish to stop | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 02 | EA Sports FC 26 Pitch Notes | FC 26 made decel "faster and snappier" across all archetypes; early-accel more responsive to reduce locked-in animation feel | Confirm decel > accel; sprint→walk transition resolves within first 120 Hz tick (8.3 ms), no animation state locking | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 03 | realtimecollisiondetection.net + Wayline Input Buffering | 100 ms = perceptible lag threshold; Android baseline 50-150 ms; over-buffering > 200 ms = "sticky" controls | Apply input in same `_physics_process()` tick it arrives; zero intentional delay; budget leaves no slack on low-end Android | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 04 | Godot Recipes 4.x — Smooth 3D Rotation | `transform.interpolate_with(target, speed * delta)` canonical Godot 4 method; rotation_speed 5-10 natural; Euler lerp = gimbal lock | Replace `rotation.y` lerp with `basis.slerp()` / `interpolate_with()`; weight per 120 Hz tick = speed/120 ≈ 0.042-0.083 | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 05 | eFootball 2025 attributes + patch notes v2.00 | Feinting speed decreases proportionally as stamina drops; small dir changes during dash-dribble no longer break sprint | On stamina exhaustion apply -10-20 % speed penalty (not hard cut); suppress sprint-break on dir changes < 15° | MEDIUM | **Sprint 9 / 10 (deferred — polish)** |
| 06 | Game Developer — Game Feel Tips II | Responsive games reach full speed in 60-100 ms; spec's 20 m/s² to 8 m/s = 400 ms (heavy end of 50-200 ms design space) | Two-phase ramp: first 100 ms at ~40 m/s² burst, then plateau at 20 m/s²; store curve in `PhysicsConfig.tres` as `Curve` resource | MEDIUM | **Sprint 9 / 10 (deferred — polish)** |
| 07 | FIFA 22 HyperMotion GDC Vault + FC 26 animation notes | FIFA solves foot-slip via ML procedural blending at runtime; root problem = velocity vector changing faster than animation can respond | Separate `visual_root` node from collision body; `interpolate_with()` on visual mesh with 1-3 frame lag on sharp dir changes — pure GDScript | MEDIUM | **Sprint 9 / 10 (deferred — polish)** |

**Notes**: foot-planting specifics thin (no published IK weights). Acceleration aggressiveness contradiction resolved by two-phase ramp (finding 06). Stamina ratios from sport science don't map cleanly to arcade values.

---

## R02 — Ball Possession & Control System

| # | Source | Finding | Applicability | Priority | Used in Sprint |
|---|--------|---------|---------------|----------|----------------|
| 01 | smish.dev — Rocket League Ball Simulation (GDC 2018) | RL dual-impulse model: standard inelastic + Psyonix bonus `J = m_b * ‖dv‖ * s(‖dv‖) * n` ball-only. Momentum intentionally non-conserved | On shot/pass release: `set_deferred("freeze", false)` + `apply_central_impulse(shot_vec * bonus_scale)`; snappy without disturbing BallPhysics | HIGH | **Phase 3 (deferred)** — `kick_bias_impulse` field on PhysicsConfig; PhysicsConfig is sacred in Phase 2 (S06-D06) |
| 02 | Godot RigidBody3D docs + Forum #65668 + GitHub #85371 | `freeze` STATIC fails silently in physics callbacks; **KINEMATIC mode is the only reliable freeze**; `set_deferred("freeze", true)` + `freeze_mode = FREEZE_MODE_KINEMATIC` | Pair `custom_integrator=true` with `freeze_mode=KINEMATIC`; never assign `freeze` directly inside `_integrate_forces` — always deferred | HIGH | **Sprint 7 T01** (`BallPhysics.set_possessed`) — VALIDATED |
| 03 | PhysicsFC arXiv 2504.21216 | Possession trigger: horizontal distance ≤ 2 m AND ball approaching. Loss at 3 m. Dribble→Kick instant on user input, no positional precondition | Spec's 0.8 m + 12 m/s gate validated. Use horizontal-only check `Vector2(dx, dz).length_squared() < 0.64` | HIGH | **Sprint 7 T02** (`BallController._try_pickup` 0.8 m + 12 m/s gates) — VALIDATED |
| 04 | EA Sports FIFA 23/FC 25/26 Pitch Notes | FIFA uses attribute-driven touch intervals (Dribbling + Ball Control), not fixed offset. Elite players retain 88-95 % sprint speed with ball | Spec's fixed 0.5 m carry offset = valid MVP. Polish: `carry_offset = lerp(0.3, 0.5, speed/max_speed)`. `ball_speed = player_speed * 0.88-0.95` | MEDIUM | **Sprint 8 T01** (Close Control: speed-modulated carry_offset + 0.88-0.95 player_speed coupling) |
| 05 | GameDev.tv + Unity forum dribbling | 3 architectures: A) parent/snap (breaks custom integrators), B) animation-event impulse, C) proximity + position-copy. Use `length_squared()` not `length()` | Architecture C matches spec exactly. Loss threshold 1.6 m (= 2 × 0.8) | MEDIUM | **Sprint 8 T02** (Touch-cycle dribble: arch C + 1.6 m loss threshold) |
| 06 | Kids Can Code — Godot 4 RigidBody Drag/Drop Recipe | Canonical Godot 4 toggle: `freeze=true / FREEZE_MODE_KINEMATIC` on pickup; position-copy each `_physics_process`; release with `apply_central_impulse(velocity_on_release)` | Auto-switch guard: expose `is_shooting: bool` on PlayerController. Carry offset `Vector3(0, -0.2, 0.5)` (forward + slight down). Clamp shot impulse to avoid tunneling | HIGH | **Sprint 7 T01-T05** (`BallPhysics` deferred-freeze, `BallController` carry-pos-copy, `release()` apply_launch_state pipeline; `is_shooting`/`is_passing` flags on PlayerController) — VALIDATED |
| 07 | eFootball Magnetic Feet skill + PES Mastery | "Magnetic Feet" = NOT physics suction; discrete skill flag tightening loss-threshold under press. Top games simulate magnetic feel via threshold + offset modulation, not IK | No foot-IK / suction needed for MVP. `carry_offset_mag = lerp(0.3, 0.5, speed/7.0)`. Future "Tight Control" skill: raise loss threshold 1.6→2.0 m | MEDIUM | **Sprint 8 T03** (`carry_offset_mag` curve + future "Tight Control" skill flag) |

**Notes**: foot-IK specifics unpublished. Carry speed ratio (0.85-0.95) inferred from biomechanics. **Auto-switch hysteresis** missing from spec — add 0.5 m dead zone or 3-frame minimum hold to prevent oscillation.

---

## R03 — Shooting & Passing Feel

| # | Source | Finding | Applicability | Priority | Used in Sprint |
|---|--------|---------|---------------|----------|----------------|
| 01 | Steve Swink *Game Feel* (2009) | Input lag < 100 ms unnoticeable; > 240 ms feels broken. ADSR envelope maps to hold-to-charge | Charge bar updates every `_process()` frame. 120 Hz physics + deferred `_pending_linear` → 8.3 ms — within budget | HIGH | **Sprint 7 T03** (re-validated: shoot/pass within budget) — VALIDATED |
| 02 | febucci.com — Easing Functions | Cubic EaseIn `f(t) = t³` recommended for charge/power — "weight-building" feel | `normalized_t = clamp((hold_s - 0.3)/1.2, 0, 1)`, `speed = lerp(min, max, t³)`. 50% hold → 12.5% power forces commit | HIGH | **Sprint 7 T03** (`ShootingController.charge_curve_exponent = 3.0`) — VALIDATED |
| 03 | gamedeveloper.com — Game Feel Tips II | Impact actions apply velocity instantly. Friction ≈ 25-30 % of accel for responsive feel. Iterate by doubling/halving, not nudging | On Spacebar release call `apply_launch_state()` immediately (deferred 1 tick, not ramped). Charge bar snaps — no ease-out on indicator | HIGH | **Sprint 7 T03** (`ShootingController.fire_shot` → `request_release` instant) — VALIDATED |
| 04 | gamedev.net FPS Recoil/Spread + EA FC precision shooting | Shot deviation = random scatter up to max angle. Lower power = wider scatter. Gaussian σ = max/2 common | `max_scatter_deg = lerp(5.0, 0.5, power_factor)`. Rotate launch dir by `randf_range(-max, +max)` around UP before `launch_at_angle()` | MEDIUM | **Sprint 9 polish** (shot scatter — feel pass) |
| 05 | Meta Community / Unity aim-assist + EA passing deep-dive | Dot-product cone: `argmax(dot(forward, dir_to_target))`, ignore dot < 0.707 (±45°). Power > 50 % selects farther receiver | E-pass: collect teammates inside 90° cone (dot > 0.707). Short < 8 m → backspin grounder, long > 15 m → topspin lob. Reuse `compose_spin()` | HIGH | **Sprint 7 T04** (`PassingController.cone_dot_threshold = 0.707` + auto-spin) — VALIDATED |
| 06 | `BallLauncher.gd` codebase analysis | Arc height already calibrated: `h = clamp(dist * 0.32, 1.2, 9.6) m`; 4-pass iterative drag-aware solver. Lob crossover natural at ~15 m | Reuse `launch_to_point()` for auto-pass arc. Override spin post-call: `compose_spin(dir, -3, 0)` grounder, `compose_spin(dir, +4, 0)` lob | HIGH | **Sprint 7 T04** (`PassingController` → `BallLauncher.compute_velocity_to_point` + `compose_spin`) — VALIDATED |
| 07 | FC Mobile Universe — Shooting Controls + EA FC Mobile power shot | EA FC Mobile: hold-duration controls power AND arc (chip shot). Charge bar + arc preview required for legibility. 60 FPS touch = floor | Charge bar updates in `_process()` not `_physics_process()`. Use `predict_forward()` for live arc preview during charge — API exists | MEDIUM | **Sprint 9 polish** (charge bar HUD + arc preview) |

**Notes**: power-curve exponent should be `@export` on PhysicsConfig (range 2.0-4.0). Shot deviation distribution (Gaussian vs uniform) is taste call. **Codebase strength**: `launch_to_point()` + `compose_spin()` already do heavy lifting → entire shooting can be a thin `ShootingController.gd`.

---

## R04 — Goalkeeper Behavior Patterns

| # | Source | Finding | Applicability | Priority | Used in Sprint |
|---|--------|---------|---------------|----------|----------------|
| 01 | calculatorcorp.com FIFA Reaction/Save Calculator | Reachability two-gate: `t_f = d_s / v_b`, `t_av = max(0, t_f - t_r - t_buf)`. If `t_av ≤ 0` reactive save impossible. `d_eff = max(0, d_lat - r)` | Call `predict_forward(t_f)` for ball X at goal line. If `d_eff/gk_speed > t_av` → teleport; if `t_av ≤ 0` → give up | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 02 | PMC8812381 — Penalty GK science | Total response budget ball-strike→goal-line ~600 ms. GKs commit 100-250 ms before contact. Trained directional accuracy ~50-52 % without cues | Teleport-on-trajectory cheat is physically motivated. Trigger when `d_eff/gk_speed > t_av`, not only `t_av ≤ 0` | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 03 | PMC3590836 — Biomechanical analysis elite/inexperienced GKs (handball) | Elite begin lateral movement 193 ± 67 ms before ball release; success 66.3 % vs 24.3 %. Lower variance is key | **Phase 3 target**: 0.1-0.2 s simulated reaction delay before teleport. Tune to 66 % saves of reachable shots. Phase 2 skips (cheat is intentional) | MEDIUM | **Sprint 9 / 10 (deferred — polish)** |
| 04 | gamedeveloper.com — Movement Prediction + Predictive Aim Math | 1-axis intercept: `intercept_x = ball_pos_x + ball_vel_x * t_flight`, `t_flight = (gk_z - ball_z) / ball_vel_z` | Use existing `predict_forward(t_flight)`. Clamp to `[-3.2, 3.2]`. No new math | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 05 | FIFA Training Centre + Keeperstop angle guides | GK idles at angle bisect ball→posts. 1-axis arcade: `idle_target_x = ball_x * 0.5`. Stays "2-3 yards off line" (~1.8-2.7 m) | Spec (speed 6.0, lerp 0.15) correct. `gk_idle_target_x = clamp(ball_x * 0.5, -3.2, 3.2)`. GK Z = goal_line + 1.0-1.5 m | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 06 | forrestthewoods + GDC arcade AI consensus | Three arcade GK cheats: teleport-on-trajectory; X-only shadow; **give-up gate** (skip when `abs(intercept_x) > post_width OR predicted_height > crossbar`) | Phase 2 = pattern 1 + give-up gate (`abs(intercept_x) > 3.2` OR `predicted_height > 2.44 m`). Play save anim even on teleport for readability | HIGH | **Sprint 8** (Close Control + Static AI / GK) |

**Notes**: Phase 2 spec only checks 2 m proximity — refine to use reachability formula (finding 01). **Add give-up gate to spec** (currently missing). Idle factor 0.5 not 1.0 prevents near-post exposure. `predict_forward()` already does the heavy work.

---

## R05 — Static / Reactive Formation AI

| # | Source | Finding | Applicability (Phase 2 Static AI) | Priority | Used in Sprint |
|---|--------|---------|-----------------------------------|----------|----------------|
| 01 | Game AI Pro 2 Ch.30 (Dave Mark) | Influence maps don't need per-frame updates. Strategic 0.5-1 Hz, tactical 2-5 Hz. `influence = max * exp(-dist * decay)` | Recompute `target_position` at 2 Hz (every 0.5 s), not every physics tick. Mobile CPU friendly, still readable | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 02 | arxiv 2501.05870 — Neighbor-based Pitch Ownership (2025) | Static Voronoi (nearest player to point) is cheapest pitch-control approximation. Formation anchors ARE Voronoi centroids | No Voronoi computation needed. `target_position = anchor + (ball - anchor) * role_factor` produces correct zones by construction | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 03 | GameDev.net Soccer AI thread | Event-driven + time-guarded hybrid is standard lightweight approach: "once a second, or whenever an event occurs (possession change), pick formation positions" | Event trigger (ball crosses halfway) + 1.5 s minimum interval. Confirms spec parameters: GK=0.1, def=0.3, mid=0.5, att=0.7 | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 04 | grant.tuxinator.net IM tutorial + gamedev.net r2799 | For 5 CPU players on 105×68 m, explicit influence grid unnecessary; analytical target per agent O(1). Optional debug 21×14 grid at 2 Hz | Skip grid in Phase 2. Compute analytically. Add debug overlay only if calibration needs it. Lerp momentum `alpha = dt / 1.5` | MEDIUM | **Sprint 8** (Close Control + Static AI / GK) |
| 05 | Frontiers in Sports PMC12163489 (2025) | Role-differentiated positioning empirically validated. Network eccentricity correlates with influence factor. Spacing ~0.2 between adjacent roles | Spec gradient (0.1/0.3/0.5/0.7) well-grounded. No adjustment. Maintain monotonic, evenly-spaced; don't flatten adjacent roles | MEDIUM | **Sprint 8** (Close Control + Static AI / GK) |
| 06 | Game AI Pro 1 Ch.21 + Game AI Pro 2 Ch.29 | World-space ANCHOR vs slot-relative SLOT distinction. Static AI = anchors only. Velocity-clamped lerp prevents visible sliding | Anchors only in Phase 2. Add `max_reposition_speed` 6-10 m/s per role to prevent edge-case teleport. `lerp_alpha = dt/1.5` clamped `[0,1]` | MEDIUM | **Sprint 8** (Close Control + Static AI / GK) |
| 07 | arxiv 2501.05870 + Frontiers — **PHASE 3+ ONLY** | Full dynamic pitch control (Temporal Voronoi / Spearman) needs per-player vel + body orientation + time-to-ball. Min viable: 3-param KNN at 10 Hz | **DO NOT apply Phase 2.** Flag for Phase 3 active opponent AI. η=2 frames, ξ=0.4, τ=3-frame, 10 Hz | LOW (Phase 3+) | **Phase 3 (deferred)** |

**Notes**: literature assumes active CPU players; spec inverts (intentional static obstacles). Influence maps unnecessary, Voronoi is "accidentally correct" via anchor formula. The 1.5 s lerp is the only dynamic behavior needed.

---

## R06 — Camera Systems for Football Games

| # | Source | Finding | Applicability | Priority | Used in Sprint |
|---|--------|---------|---------------|----------|----------------|
| 01 | Game Camera Systems Guide 2025 | Weighted centroid: `pos = sum(w_i * tgt_i)`. Sports smoothing 0.4-0.6 s, dead zone 20-30 % screen. Lerp 0.06 ≈ 0.3-0.4 s lag at 60 fps | Validates spec: `centroid = ball*0.6 + player*0.4` then `lerp(cam, centroid, 0.06)`. Mobile dead zone 25-35 % (wider than desktop) | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 02 | Cinemachine Framing Transposer docs | Dead zone = normalized screen region (0-1) where camera holds still. Soft zone for gradual re-entry. Lookahead 0-1, smoothing 0-30 | 2.5-4 m world-space dead zone on centroid. Camera moves only when centroid drifts beyond. Eliminates micro-jitter on mobile | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 03 | Unity Discussions — look-ahead velocity offset | `target = ball_pos + ball_vel * lookahead_s`, `lookahead_s = 0.1-0.3 s`. SmoothDamp with `dampTime = 0.15 s`. XZ only, ignore Y | `centroid_ahead = centroid + ball_velocity.normalized() * clamp(ball_speed * 0.1, 0, 5)`. 30 m/s → 3 m offset, cap at 5 m | MEDIUM | **Sprint 9 / 10 (deferred — polish)** |
| 04 | Godot Camera Bounds forums + padamthapa.com 2D limits | Bounds clamping AFTER lerp step, never before. Camera2D.limit_* principle translates to 3D pivot clamping post-lerp | Pitch 105×68 + 5 m margin: `cam_pivot.x = clamp(x, -57.5, 57.5)`, `cam_pivot.z = clamp(z, -39, 39)`. Apply post-lerp only | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 05 | Rocket League settings (Liquipedia) + Smash Bros multi-target | RL spring stiffness 0.50 (moderate). Smash: bounding box of all targets fits frame. Zoom range linear from extents | Zoom: `zoom_z = remap(ball_goal_dist, 0, 52.5, 30, 50)`. Lerp zoom slower (0.04) than position (0.06). FOV stays 45° per spec | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 06 | phrogz.net Frame-Rate Independent LP Filter + mobile camera notes | FR-independent lerp: `filtered = old + (new - old) * (delta / smoothing)`. Mobile: cap angular vel ~60 deg/s, dead zone 25-35 % | Replace `lerp(cam, tgt, 0.06)` with `lerp(cam, tgt, 1.0 - pow(0.94, delta * 60))`. Identical smoothing 30/60 fps on Android | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 07 | Godot 4 SpringArm3D docs + supermatrix.studio guide | SpringArm3D sweeps SphereShape3D (r 0.3-0.5 m), places Camera3D at collision point. Spring length = follow distance. Exclude player/ball layers | Mount SpringArm3D on centroid pivot. `spring_arm.spring_length = zoom_z`. Camera child at tip — no manual Z. Geometry clipping auto-handled | MEDIUM | **Sprint 9 / 10 (deferred — polish)** |

**Notes**: frame-rate variance is primary mobile risk — frame-rate-independent lerp (finding 06) is one-line fix. Dead zone NOT optional on mobile. Zoom slower than pan. Cap angular velocity ~60 deg/s before bounds clamp.

---

## R07 — Input & Controls for Mobile Sports

| # | Source | Finding | Applicability | Priority | Used in Sprint |
|---|--------|---------|---------------|----------|----------------|
| 01 | Gamedeveloper.com — Doing Thumbstick Dead Zones Right | Scaled-radial dead zone: `stick.normalized * ((mag - dz) / (1 - dz))` eliminates precision loss. Standard 0.10-0.20 (0-1 scale) | **Sprint 10**: scaled-radial in virtual joystick, `dead_zone_radius=0.12` in `InputConfig`. **Phase 2**: WASD digital — design `InputConfig` schema with both keyboard_map + touch_map fields | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 02 | Apple HIG + Google Material Design | Min touch target 44×44 pt (Apple) / 48×48 dp (Google). Primary actions 56-64 dp. Spacing ≥ 8 dp | **Sprint 10**: shoot button 64dp, pass/sprint 48dp min, 8dp spacing. **Phase 2**: reserve HUD zones now | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 03 | EA FC Mobile + CoD Mobile | Floating + fixed joystick modes; floating default. Tap=pass, hold-release=shot, double-tap=sprint mirrors keyboard E/Space-hold/Shift | **Phase 2 NOW**: build `ActionMap` abstraction — actions named, not key literals. Keyboard + touch bind to same actions | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 04 | Smashing Magazine — Thumb Zone + mobilefreetoplay | 49 % users one-hand; 75 % thumb. Landscape gamer-stance: easy reach = bottom corners, hard = top-center. Min swipe area 45×45 px | **Phase 2 NOW**: HUD zones = joystick bottom-left (10-20 %, 70-85 %), action cluster bottom-right (75-95 %, 65-85 %), HUD-safe top 15 % + center 30 % | MEDIUM | **Sprint 9 / 10 (deferred — polish)** |
| 05 | Interhaptics + XDA Marvel Snap analysis + Android Police | Three haptic tiers: light 10-15 ms (UI), medium 40-60 ms (bounce), heavy 80-120 ms (shot). Goal waveform [80, 40, 80]. Fire within 1 physics frame | **Phase 2**: `HapticConfig` resource: `pass_ms=15, bounce_ms=50, shot_ms=80, goal_waveform=[80,40,80]`. Emit Godot signals from physics events. **Sprint 10**: wire to platform haptic API | MEDIUM | **Sprint 9 / 10 (deferred — polish)** |
| 06 | GDC Vault — Aim Assist Console Shooters (Insomniac 2013) + Game Developer (War Robots) | Aim assist = magnetism (snap within ~10 % screen radius) + friction (slow over target). For football: pass magnetism within 25° arc | **Phase 2 NOW**: `PassAssist` module: `aim_assist_cone_degrees=25.0`, `aim_assist_max_distance_m=15.0`. Keyboard Q-switch shares same logic | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 07 | ACM SIGGRAPH MIG 2023 — Virtual Joystick Sensitivity (DOI 10.1145/3623264.3624461) | Floating preferred. Touch dead zone 12-18 % (vs 8-12 % hardware). Self-selected ~60-70 % deflection. Sensitivity exponent 1.3-1.5. > 85 % = sprint | **Sprint 10**: `touch_dead_zone=0.15, joystick_radius_dp=80, sensitivity_exponent=1.4, sprint_threshold=0.85`. Default mode floating. **Phase 2**: schema accommodates fields | HIGH | **Sprint 8** (Close Control + Static AI / GK) |

**Notes**: Phase 2 actionable items = ActionMap abstraction (F3), HUD zone reservation (F4), PassAssist module (F6), InputConfig schema (F1+F2). Touch implementation reserved for Sprint 10.

---

## R08 — Performance & Optimization for ~10 Entities

| # | Source | Finding | Applicability | Priority | Used in Sprint |
|---|--------|---------|---------------|----------|----------------|
| 01 | Godot docs CharacterBody3D + forum perf thread | CharacterBody3D avoids RigidBody3D constraint-solver N² cost. RigidBody hits wall ~30-40 entities. CharacterBody no ceiling at 10 | Keep all 10 players as CharacterBody3D. Don't switch body type. Ball's RigidBody + custom integrator already isolated | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 02 | Godot docs physics_introduction + forum #121503 | Each mask bit = extra broadphase query per tick. Off-screen bodies should disable CollisionShape | Layers: 1=World, 2=Players, 3=Ball, 4=GoalTrigger. Player mask `{1,2,3}`, Ball mask `{1,2,4}`, GoalTrigger mask `{3}`. Disable GoalTrigger CollisionShape when ball in far half | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 03 | Godot docs idle_and_physics_processing | At 120 Hz × 10 players = 1,200 `_physics_process()` calls/sec. Non-physics logic here wastes budget. Docs explicit: "if expensive logic causes slowdown, _physics_process is wrong place" | Player scripts: velocity + `move_and_slide()` in `_physics_process()` ONLY. AI decisions + animation in `_process()` throttled every 3-5 frames via counter | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 04 | Godot docs optimizing_3d_performance + GitHub #104194 | Compatibility (GLES3) does NOT support automatic mesh instancing (Forward+ only). Post-processing very expensive on mobile GLES3. Godot 4.4 batching regression on Android | `WorldEnvironment`: `glow_enabled=false, ssao_enabled=false, ssil_enabled=false`. Baked OmniLight3D for stadium. `VisibleOnScreenNotifier3D` per player | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 05 | Godot docs using_multimesh + optimizing_3d | MultiMeshInstance3D collapses N draws to 1 BUT no per-instance frustum culling. Useful only > 100 instances; 10 distinct players = marginal saving | Reserve MultiMesh for crowd/grass tiles (> 100). Keep 10 players as individual `MeshInstance3D` (different team colors). LOD auto-import on player meshes | MEDIUM | **Sprint 9 / 10 (deferred — polish)** |
| 06 | Godot docs the_profiler + godot-extended-libraries/godot-debug-menu | Full Godot profiler works on Android over USB ("Deploy with Remote Debug"). C# scripts NOT covered by GDScript profiler. Complement: godot-debug-menu, Android GPU Inspector | Workflow: (1) export debug APK with Remote Debug, (2) Profiler for physics/idle (target physics < 4 ms at 120 Hz = 8.33 ms/frame), (3) godot-debug-menu for sustained FPS, (4) GPU Inspector for draw calls | MEDIUM | **Sprint 9 / 10 (deferred — polish)** |
| 07 | Godot GDScript style guide + playgama.com mobile opt | Static typing + node pre-caching reduce per-frame interpreter overhead. `get_node()` + signal dispatch in `_physics_process()` measurable at 1,200 calls/sec | All player scripts: `@export var ball_ref: RigidBody3D` assigned in editor, cache in `_ready()`. Zero `get_node()`/`find_child()` in `_physics_process()`. Typed `PhysicsConfig` (already convention) | MEDIUM | **Sprint 9 / 10 (deferred — polish)** |

**Notes**: Real frame savings (act first) = F1-F4. Micro-opts (defer until profiler) = F5-F7. Highest leverage = F3 (move AI out of `_physics_process` at 120 Hz, run at 30 Hz via counter).

---

## R09 — Tricks & Shortcuts from the Industry

| # | Source | Finding | Applicability | Priority | Used in Sprint |
|---|--------|---------|---------------|----------|----------------|
| 01 | Jared Cone — "It IS Rocket Science!" GDC 2018 | Psyonix adds secondary impulse `J = m_b * ‖dv‖ * s(‖dv‖) * n` ball-only, violating Newton's 3rd. Contact normal vertically compressed (n[2] *= 0.35). Hitboxes are OBBs | On foot-ball contact: small directional bias impulse along kick vector (ball-side only). Add `kick_bias_impulse: float` to PhysicsConfig. Sprint 6/7 — Kick Feel | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 02 | Mark Turmell — NBA Jam Postmortem GDC 2018 | Trailing player silently boosted; outcome overrides hard-coded (Bulls miss buzzer vs Pistons). Players experience as variance, not assistance | When AI trails ≥ 2 goals with < 60 s left, boost shot-accuracy ~10-15 %, reduce GK reaction time ~15 %. Casual matches stay tense without touching ball physics. Sprint 8/9 | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 03 | Jonasson & Purho — "Juice It or Lose It" GDC Europe 2012 | 5 cosmetic effects (squash, shake, freeze 2-3 frames, pitch-shift sound, particles) transform Breakout from inert to alive. Zero physics changes | On goal: 2-3 frame timescale pause (~50 ms), shake (0.3 amp, 0.2 s exp decay). Hard shots: ball squash 1.3× along velocity, 4-frame recovery; sound +15 % pitch. Sprint 6 — Polish | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 04 | McComas & Sanmiya — Animation Warping FIFA, GDC 2010 | FIFA appears < 33 ms response while animations take 300-500 ms. Trick: Face Angle Warping rotates mesh toward input within 1 tick; physics body follows at sim speed. Warp range 0.5×-1.5× | Snap player mesh Y-axis (facing) toward input within 1-2 physics ticks (8-16 ms at 120 Hz); hitbox + state machine follow normally. Sprint 7 — Player Controller Feel | MEDIUM | **Sprint 9 / 10 (deferred — polish)** |
| 05 | Seth Coster — Forgiveness Mechanics GDC 2020 | Input buffering (store 100-200 ms; fire if valid context appears) + coyote time (4-10 frames after window closes). Players don't notice the windows | Store last input timestamp; fire pass/shoot if < 100 ms old AND avatar ball-ready. 6-frame coyote for tackles. Critical on mobile (50-100 ms inherent touch latency). Sprint 6 | HIGH | **Sprint 8** (Close Control + Static AI / GK) |
| 06 | Steve Swink — *Game Feel* (2008) | Full perceive→decide→act→see-result must complete < 100 ms for "real-time". Polish (particles, sound, FOV pulse) is independent communication channel for impact weight | Audit pipeline touch→physics→mesh→camera ≤ 100 ms total. FOV pulse +3-5° on fast shots. Particle count proportional to `ball_velocity` (8 at 15 m/s, 24 at 30 m/s). Sound +20 % pitch at max power. Sprint 6/7 | MEDIUM | **Sprint 9 / 10 (deferred — polish)** |
| 07 | Jon Hare / Squareblind — *Sociable Soccer* design | Aftertouch: ~0.3-0.5 s post-kick joystick adds lateral force (physically impossible, players feel authorship). One-button: tap < 150 ms = pass, hold > 150 ms = shot. Diving headers visually exaggerated | Aftertouch: post-kick swipe adds ±5 m/s² lateral for 0.3-0.5 s. Single tap/hold for pass/shoot on mobile. Header dive 0.2 s. Sprint 6 — Mobile & Spectacle. **CONFLICT FLAG** see notes | MEDIUM | **Sprint 9 / 10 (deferred — polish)** |

**Notes — Conflicts with "BallPhysics is sacred"**:
- **F01 SAFE with care** — bonus impulse routed through `_integrate_forces` and capped via new `kick_bias_impulse` config field; no Cd/Magnus changes.
- **F07 CONFLICT FLAG** — aftertouch must be implemented as accumulated `external_force` consumed inside `_integrate_forces` next tick (treated like Magnus), so drag-crisis Cd(v) still applies. Review by physics lead before Sprint 6 implementation.
- **F02-F06 SAFE** — pure cosmetic/AI/control-layer; never touch ball state.

---

## How to Query This Knowledge Base

```bash
# CLI memory search (semantic similarity)
npx @claude-flow/cli@latest memory search --query "auto-switch threshold" --namespace IssNostalgia/research

# MCP tool (in-conversation)
mcp__ruflo__memory_search query="possession freeze kinematic" namespace="IssNostalgia/research" limit=5
```

Sample result: `"possession magnetic ball"` → top hit `research:R02:finding-07` similarity 0.72, search 8.86 ms.

## Maintenance

- Update **"Used in Sprint"** column as Sprint 6-9 consume each finding.
- Add post-implementation **VALIDATED** / **SUPERSEDED** markers to track which findings panned out.
- New findings (e.g. discovered during Sprint playtests) follow same key pattern: `research:R0X:finding-NN`.

---

## Sprint 06 — Findings Applied

| Finding | How it landed in code | Status |
|---------|------------------------|--------|
| R01-F03 (input < 100 ms perceptible) | `PlayerController.buffer_window_ms = 100.0`; input poll runs each `_physics_process` tick (8.3 ms @ 120 Hz) — zero added delay | VALIDATED |
| R01-F04 (basis.slerp / interpolate_with) | `Player.update_facing` uses `transform.basis.slerp(target_basis, alpha)` with FR-independent alpha = `1 - 0.5^(rotation_speed * dt)` — Euler lerp avoided | VALIDATED |
| R01-F05 (stamina patterns) | `STAMINA_DRAIN_PER_SEC = 1/3`, `STAMINA_RECOVERY_PER_SEC = 1/5`, gated by sprint-released (S06-D04). Soft penalty (R01-F05 specific 10-20 % speed drop on exhaust) deferred to Sprint 9 polish. | PARTIAL |
| R02-F02 / F06 (KINEMATIC freeze, deferred set) | Schema designed in TeamController (controller-pointer model, Player flags `is_busy_with_ball_action`); the actual `freeze_mode = FREEZE_MODE_KINEMATIC` toggle on the real RigidBody3D ball lands in Sprint 7 ball-pickup task. | DESIGN-LOCKED |
| R06-F06 (frame-rate-independent low-pass filter) | Applied in `Player.update_facing` (alpha pow). Camera path will reuse the same formula in Sprint 9. | VALIDATED |
| R07-F03 (ActionMap abstraction) | `PlayerController.action_prefix` ('p1_' / 'p2_'); ACTION_SUFFIXES list isolates action names from key literals. project.godot ships both prefix sets — touch (Sprint 10) attaches to the same suffixes. | VALIDATED |
| R08-F01 (CharacterBody3D for players) | `Player extends CharacterBody3D`; ball stays RigidBody3D + custom_integrator. No N² constraint solver cost on the 10-player path. | VALIDATED |
| R08-F02 (collision mask layout) | Layer 1 World, Layer 2 Players (`Player.tscn` collision_layer=2 mask=7=World+Players+Ball). GoalTrigger mask reserved for Sprint 8. | PARTIAL |
| R09-F05 (input buffering 100 ms + coyote 6 frames) | `PlayerController.consume_buffered` (consumed-on-hit) + `was_recently_valid` (non-destructive). Ring size 4 per action, `coyote_window_frames = 6`. Sprint 7 tackles will be the first consumer of `was_recently_valid`. | VALIDATED |

Findings reserved for later sprints (no Phase 2 implementation yet):
R01-F01/02/06/07, R02-F01 (PhysicsConfig sacred — Phase 3),
R06-F01..F05/F07 (Sprint 9 camera), R07-F01/F02/F04..F07 (Sprint 10 touch),
R08-F03..F07 (profile after first measurable bottleneck),
R09-F01..F04/F06/F07 (juice / aftertouch / NBA-Jam catch-up — Sprint 8/9/Phase 3).

---

## Sprint 07 — Findings Applied

| Finding | How it landed in code | Status |
|---------|------------------------|--------|
| R02-F02 (KINEMATIC freeze + deferred set) | `BallPhysics.set_possessed` sets `_possessed_by` + `set_deferred("freeze", true)`; integrator early-returns when possessed | VALIDATED |
| R02-F03 (proximity 0.8 m + ball-speed gate) | `BallController._try_pickup`: `dx²+dz² ≤ 0.64` AND `|v|² ≤ 144`, GK excluded, post-release lockout 0.3 s | VALIDATED |
| R02-F06 (carry pos-copy + impulse on release) | `BallController._sync_carry_position` writes `ball.global_position = carrier_pos + visual_basis * carry_offset` directly (KINEMATIC accepts direct writes; staged-pending pipeline doesn't fire while frozen). Release via `apply_launch_state` deferred. | VALIDATED |
| R03-F01 (input lag < 100 ms) | shoot/pass roundtrip = 1 physics tick (8.3 ms) + deferred-freeze cycle ≤ 16 ms — well within budget | VALIDATED |
| R03-F02 (cubic charge curve) | `ShootingController.charge_curve_exponent = 3.0`; power_norm = `pow(t_norm, 3.0)` | VALIDATED |
| R03-F03 (instant impact, no ramp on release) | `ShootingController.fire_shot` → `BallController.request_release` → `BallPhysics.release` → `apply_launch_state` (1-tick deferred), no easing | VALIDATED |
| R03-F05 (90° forward cone target select) | `PassingController.cone_dot_threshold = 0.707`, nearest in cone, GK excluded; spin auto by distance (backspin < 8 m, topspin > 15 m, zero between) | VALIDATED |
| R03-F06 (reuse BallLauncher.launch_to_point) | `PassingController.try_pass` → `BallLauncher.compute_velocity_to_point` (refactored from `launch_to_point`) → `compose_spin` override | VALIDATED |
| R09-F04 (FIFA Animation Warping) | `Player.start_facing_warp(dir, 0.15)` writes target facing + boosts `rotation_speed` to `rotation_speed_warp = 50` for window. Used by `BallController._assign_carrier` AND `PassingController.try_pass` (receiver pre-orientation) | VALIDATED |
| R01-F07 (FIFA HyperMotion visual/physics decoupling) | `Player.tscn` adds `VisualRoot: Node3D` between CharacterBody3D and meshes. `update_facing` rotates VisualRoot ONLY; `transform.basis` (collision capsule) stays at identity. `Player.get_visual_basis()` / `get_visual_forward()` are the canonical facing accessors. | VALIDATED |

---

## Sprint 08 — Findings Applied

| Finding | How it landed in code | Status |
|---------|------------------------|--------|
| R02-F04 (carrier velocity drives kick direction; turn dampen) | `BallController._apply_proximity_kick` walk/sprint factors + `kick_turn_dampen_threshold_deg` / `kick_turn_dampen_factor` | VALIDATED |
| R02-F05 (touch-cycle dribble, geometric proximity kick) | `BallController._tick_dribble_impulses` + `_apply_proximity_kick` (no glue, kick_proximity_m=0.35, kick_factor walk/sprint = 1.08/1.18) | VALIDATED |
| R02-F07 (close_control / dribble_skill per-player) | DEFERRED → Sprint 9 (close-control modal button + per-player attribute lookup) | DEFERRED |
| R04-F01 (reachability two-gate) | `Goalkeeper.compute_save_decision` (t_av + d_eff + move_time_required) | VALIDATED |
| R04-F02 (commit-early teleport-on-trajectory) | `Goalkeeper._perform_snap` | VALIDATED |
| R04-F03 (controlled-hesitation reaction delay) | DEFERRED → Phase 3 (Phase 2 teleport is intentional visible cheat) | DEFERRED |
| R04-F04 (1-axis intercept formula) | `Goalkeeper.compute_save_decision` (kinematic, drag skipped per F04 sufficiency note) | VALIDATED |
| R04-F05 (idle = ball_x * 0.5 angle bisect) | `Goalkeeper._perform_idle` clamped to `goal_half_width_m` | VALIDATED |
| R04-F06 (give-up gates outside post / above crossbar) | `Goalkeeper.compute_save_decision` returns `idle` when `abs(intercept_x) > 3.2` OR `predicted_height > 2.44` | VALIDATED |
| R05-F01 (2 Hz tactical update) | `StaticAI.step` accumulator at `update_hz = 2.0` | VALIDATED |
| R05-F02 (anchor = Voronoi centroid, role-factor offset) | `StaticAI.tick_targets` | VALIDATED |
| R05-F03 (role factors GK 0.10 / DEF 0.30 / MID 0.50 / ATT 0.70; event hybrid) | `StaticAI.ROLE_FACTOR_*` constants. Half-change event hybrid DEFERRED → Sprint 9 (T04 spec mandated pure 2 Hz polling). | PARTIAL |
| R05-F04 (analytical per-agent target, lerp_alpha = dt/1.5) | `Player._drive_toward_static_target` (`STATIC_TARGET_LERP_TAU_S = 1.5`) | VALIDATED |
| R05-F05 (monotonic role gradient empirically validated) | `test_role_factor_gradient_is_monotonic` | VALIDATED |
| R05-F06 (max_reposition_speed cap 6–10 m/s by role) | `StaticAI.max_reposition_speed_*` (7/8/9) + `Player.set_static_target(pos, max_speed)` clamp | VALIDATED |
| R05-F07 (Temporal Voronoi KNN dynamic) | DEFERRED → Phase 3 (per-frame cost incompatible with mobile budget) | DEFERRED |
| R09-F02 (NBA Jam catch-up boost) | SCHEMA-ONLY: `Goalkeeper.get_effective_reaction_buffer_s` + `is_catchup_eligible` (Sprint 8 stub returns false). Runtime activation Sprint 9 (requires scoreboard). | PARTIAL |

---

## Sprint 09 — Findings Applied

| Finding | How it landed in code | Status |
|---------|------------------------|--------|
| R02-F04 (attribute-driven dribble touch interval — extension) | `BallController._apply_proximity_kick` lerps walk/sprint factor between high-skill (1.04 / 1.10) and low-skill (1.12 / 1.26) envelopes by `Player.dribble_skill`. Midpoint 0.5 reproduces Sprint 8 constants. | VALIDATED |
| R02-F07 (close-control modal + tight control) | `Player.get_effective_carry_offset(speed, base)` and `get_effective_loss_threshold(base)` with opt-in modulation (closeness=0 at default 0.5 + no modal returns base unchanged). `BallController._carry_offset_for_carrier` consumes via API. Input actions `p1_tight_control` (Z) / `p2_tight_control` (Num0). | VALIDATED |
| R05-F03 (event-driven half-change hybrid — completion) | `StaticAI._check_half_change_event` (signf(ball.z) flip + `min_seconds_between_events = 1.5` + `half_change_min_abs_z = 5.0` wobble buffer); `step()` resets polling timer + ticks immediately on event. Polling 2 Hz path unchanged. | VALIDATED |
| R09-F02 (NBA Jam catch-up runtime) | `Goalkeeper.is_catchup_eligible` reads `scoreboard.goal_gap_from(my_team_id) ≥ trailing_goal_threshold` AND `match_clock.current_time_remaining_s ≤ time_remaining_threshold_s`. NULL-safe. Default `catchup_boost_enabled = true`. +12.5 % shot-accuracy boost DEFERRED → Sprint 10 (no shot-spread concept yet). | PARTIAL |
| In-house: MatchClock + Scoreboard | `MatchClock` (240 s default, half-minute / match-ended signals) + `Scoreboard` (TEAM_A/B + goal_scored / score_changed signals + `goal_gap_from` accessor). `GameMatch._spawn_match_state` + `_check_goal_lines` edge-detect ball.z past ±52.5 with 0.5 s lockout. | VALIDATED |
| Sandbox dev-tool polish | `R` ball reset-to-centre + GK `_last_decision` HUD line. MMB camera reset already wired in S08. | VALIDATED |
| R06-F03 (camera look-ahead) | DEFERRED → Sprint 10 (camera bundle). | DEFERRED |
| R06-F07 (SpringArm3D collision) | DEFERRED → Sprint 10 (camera bundle). | DEFERRED |
| R09-F07 (aftertouch) | DEFERRED → Sprint 10 (touch-input bundle). | DEFERRED |
