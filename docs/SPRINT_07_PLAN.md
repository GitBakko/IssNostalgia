# SPRINT_07_PLAN.md

## Sprint 07 — Ball Interaction & Shooting

**Branch**: `sprint/07-ball-interaction` (off `main` @ `7b52441`, post `v0.6.0-sprint06`)
**Phase**: Phase 2 — Game Mechanics, secondo sprint
**Modalità**: Checkpoint task-by-task per task soggettive (feel), auto per pure logic / unit tests
**Tag finale**: `v0.7.0-sprint07`

## Goal

Trasforma `MockBall` Node3D in palla vera (`RigidBody3D` con custom integrator
da Phase 1, IMMUTABILE). Implementa:

- **Possesso** — pickup proximity-based (0.8 m XZ + ball-speed ≤ 12 m/s),
  carry con `freeze_mode = FREEZE_MODE_KINEMATIC`, release on shoot/pass.
- **Tiro** (`Space` hold-charge) — 0.3 s min → 1.5 s max, cubic `t³` power
  curve, direzione vettoriale somma `facing*0.6 + WASD*0.4`, spin
  auto-topspin per |v| > 20 m/s.
- **Passaggio** (`E`) — auto-target cone 90° (dot > 0.707), nearest
  teammate, potenza derivata da distanza, spin auto (backspin grounder
  < 8 m, topspin lob > 15 m), riusa `BallLauncher.launch_to_point` +
  `compose_spin`.
- **Animation warping** — mesh facing snap a 1-2 tick su input change
  brusco (R09-F04), risolve "su rotaia".

Exit: una partita demo apribile — player umano controlla Team A,
raccoglie la palla, tira / passa, BallPhysics ripercorre la traiettoria
con Magnus / Cross-2002 / drag-crisis attive. Bounces visibili, palla
rilanciata da Team B AI (statica — Sprint 8 darà loro reazione vera).

---

## T00 — Research verification + Plan + GAME_DESIGN_LOG seed

**Obbligatorio prima di T01** (workflow nuovo introdotto post-Sprint 6).

### Step 1 — Research findings rilevanti (PRIORITY: HIGH, R02 + R03)

Letti da `docs/RESEARCH_INDEX.md`. I finding HIGH coerenti con lo scope
Sprint 7 sono **9 in totale, 8 applicabili in questo sprint** (uno
deferred a Phase 3):

| ID | Source (short) | Apply Where | Status S7 |
|----|----------------|-------------|-----------|
| **R02-F02** | Godot RigidBody3D docs + Forum #65668 — KINEMATIC freeze pattern (deferred set, never inside `_integrate_forces`) | `BallPhysics` nuovo public API `set_possessed(bool)` che setta `freeze_mode = FREEZE_MODE_KINEMATIC` via `set_deferred("freeze", true)` | APPLY |
| **R02-F03** | PhysicsFC arXiv 2504.21216 — proximity ≤ 2 m + ball approaching; horizontal-only check | Possession trigger su Player: `Vector2(dx, dz).length_squared() < 0.64` (radius 0.8 m da spec) + ball relative speed ≤ 12 m/s | APPLY |
| **R02-F06** | Kids Can Code Godot 4 RigidBody drag/drop recipe — freeze + position-copy + impulse on release | Carry loop in `BallController.gd`: `freeze=true`, copy `ball.global_position = carrier.global_position + carry_offset` ogni tick, release con `apply_central_impulse(shot_vec)` deferred | APPLY |
| **R02-F01** | smish.dev RL ball simulation GDC 2018 — dual-impulse bonus on contact | `kick_bias_impulse` field on PhysicsConfig | **DEFERRED → Phase 3** (S06-D06: PhysicsConfig is sacred this phase) |
| **R03-F01** | Steve Swink *Game Feel* — input lag < 100 ms perceptible | Già applicato in S06 via `PlayerController.buffer_window_ms = 100.0` — re-validate in S7 con shoot/pass | VALIDATE |
| **R03-F02** | febucci.com easing functions — cubic EaseIn `t³` per charge curve "weight-building" feel | Shot power: `t = clamp((hold_s - 0.3) / 1.2, 0, 1)`, `speed = lerp(min_spd, max_spd, t³)`. 50% hold → 12.5 % power | APPLY |
| **R03-F03** | gamedeveloper.com Game Feel Tips II — impact actions apply velocity instantly, charge bar SNAP on release | Shot release: chiamata immediata `BallPhysics.apply_launch_state()`, no ramp/ease-out sul rilascio. Charge bar HUD snap visible | APPLY |
| **R03-F05** | Meta + EA passing — dot-product cone 90° (dot > 0.707) per target selection; power > 50 % seleziona riceventi più lontani | Pass target: filtra teammate `forward.dot(dir_to_t) > 0.707`, nearest in cone; lob > 15 m / grounder < 8 m discrimina spin | APPLY |
| **R03-F06** | Reuse `BallLauncher.launch_to_point` (esistente Phase 1 — `h = clamp(dist · 0.32, 1.2, 9.6)`, iterative drag-aware solver) + `compose_spin` | Pass action chiama `_launcher.launch_to_point(target)` poi override spin via `compose_spin(dir, ±3 o ±4)` | APPLY |
| **R09-F05** | Seth Coster GDC 2020 — input buffering 100 ms + coyote 6 frames | Già applicato in S06; S7 aggiunge `consume_buffered("shoot_charge")` e `consume_buffered("pass_ball")` come trigger di rilascio | VALIDATE |

### Step 2 — Ruflo memory search verification

Eseguito su `IssNostalgia/research` namespace con i 4 termini richiesti:

- `"possession"` → R02:F03 (sim 0.35), R02:F05 (sim 0.34) ✅
- `"shooting hold charge curve"` → R03:F07 (sim 0.68), R03:F04 (sim 0.50), R03:F02 (sim 0.50), R03:F03 (sim 0.46), R03:F01 (sim 0.39) ✅
- `"passing teammate cone target"` → R03:F05 (sim 0.65), R07:F06 (sim 0.60), R09:F01 (sim 0.36) ✅
- `"magnetic ball foot suction freeze kinematic"` → R02:F07 (sim 0.69), R02:F02 (sim 0.60), R02:F06 (sim 0.58) ✅

**No discrepancies** tra AgentDB e `RESEARCH_INDEX.md`. Top hits match
exactly le righe del index. Vector search times 10-120 ms — HNSW healthy.

### Step 3 — Decisione su conflitto: R03-F05 (90° pass cone) vs R07-F06 (25° aim-assist)

Apparente contraddizione: R03-F05 raccomanda cone 90° per teammate
target selection, R07-F06 raccomanda magnetism cone 25° per touch
aim-assist. **Non si elidono — sono livelli diversi**:

- R03-F05 = **target selection** (quale compagno riceve il pass — dipende
  dalla direzione del movimento del player).
- R07-F06 = **aim-assist su touch** (snap del touch verso il target —
  irrilevante in S7 keyboard, applica solo Sprint 10).

**Sprint 7 usa SOLO R03-F05 (90° cone, dot > 0.707).** R07-F06 attende
Sprint 10.

### Step 4 — Decisioni architetturali nuove (S07-D01..D??)

Compilate iterativamente durante l'esecuzione, in `GAME_DESIGN_LOG.md`.
Discuss-phase iniziale per S7:

- **S07-D01** `BallPhysics` espone public API `set_possessed(bool)` +
  `is_possessed() -> bool` + signal `released(velocity, position)`.
  Internal: setta `freeze_mode = FREEZE_MODE_KINEMATIC` + `set_deferred("freeze", value)`. **Non** tocca i parametri `PhysicsConfig` —
  rispetta S06-D06.
- **S07-D02** `BallController.gd` nuovo singleton-on-match (figlio di
  GameMatch). Gestisce stato palla globale: chi la possiede, transizioni
  pickup/release, freeze toggle, carry-position sync. Player non sa di
  altri Player; solo BallController arbitra.
- **S07-D03** Carry offset = `player.transform.basis * Vector3(0, -0.2, 0.5)`
  (player-local: 0.5 m davanti, 0.2 m sotto il centro del capsule, sotto i piedi).
  Da R02-F06.
- **S07-D04** Shoot direction = `(facing * 0.6 + WASD_input * 0.4).normalized()`
  (S06-D02 ribadito); shoot vy positivo lieve (10°-15° elevation) per
  arc visibile.
- **S07-D05** Spin auto per shot: topspin `+2 rad/s` se `|v| > 20 m/s`,
  zero altrimenti (S06-D05).
- **S07-D06** Spin auto per pass: backspin `-3 rad/s` se distance `< 8 m`
  (grounder), topspin `+4 rad/s` se `> 15 m` (lob), zero in mezzo
  (S06-D28). Riusa `compose_spin`.
- **S07-D07** Animation warping (R09-F04): mesh visual_root rotation
  snap entro 1-2 physics tick verso input direction. Hitbox segue a
  sim speed (esistente Player.rotation_speed = 8). Nuovo nodo
  `VisualRoot` figlio Player, separato da `CollisionShape3D`.

### Step 5 — Workflow update per task successive

A ogni commit di T01-T07, store in Ruflo memory namespace `IssNostalgia/gameplay`
una entry con chiave `sprint07:T<N>:<decision-slug>` e value = breve
sintesi della decisione architetturale + path al file di implementazione.
Verifica che `AgentDB.totalEntries` aumenti dopo ogni `memory_store`.

---

## T01 — BallPhysics state-toggle + signal `released`

- `BallPhysics.gd` aggiunge:
  - `var _possessed_by: Player = null`
  - `func set_possessed(player: Player) -> void` — sets `_possessed_by`,
    schedules `set_deferred("freeze", true)`, `freeze_mode = FREEZE_MODE_KINEMATIC`
  - `func release(impulse: Vector3, angular: Vector3) -> void` — clears
    `_possessed_by`, `set_deferred("freeze", false)`, queues
    `_pending_linear = impulse / config.ball_mass` + `_pending_angular = angular`
    (riusa il pattern Phase 1 di apply_launch_state)
  - `func is_possessed() -> bool`
  - signal `released(by: Player, velocity: Vector3)` — emesso al primo
    tick post-release
- `BallPhysics._integrate_forces` early-returns quando `is_possessed()`:
  no gravity / drag / Magnus integration. Compensation `transform.origin -=
  linear_velocity * dt` (S05-FIX) lascia in pace `linear_velocity = 0`.
- GUT: `test_ball_possession_toggle.gd`
  - `test_set_possessed_freezes_integrator` — pre/post velocity invariata
  - `test_release_re_enables_drag` — drag accel ≠ 0 dopo release
  - `test_release_emits_signal_with_velocity` — signal capture
- Decisioni: S07-D01
- Post-commit: `memory_store sprint07:T01:ballphysics-state-toggle`

## T02 — BallController + Player possession proximity check

- `scripts/BallController.gd` — `class_name BallController extends Node`:
  - `@export var ball: BallPhysics`
  - `@export var teams: Array[TeamController]`
  - `var _carrier: Player = null`
  - In `_physics_process`:
    - if `_carrier == null`: scan all players, find one with
      `Vector2(dx, dz).length_squared() < 0.64` AND
      `ball.linear_velocity.length() <= 12.0` → first hit wins (S06-D03
      tie-breaker human > AI: iterate human team first)
    - if `_carrier != null`: copy ball position to `carrier.global_position
      + carrier.basis * Vector3(0, -0.2, 0.5)` ogni tick
  - Public API: `request_release(impulse, angular)` chiamato da
    shoot/pass logic, calls `ball.release(...)` + clears `_carrier`
- `Player.gd` espone `var has_ball: bool` (mirrora `BallController._carrier == self`)
  per HUD/state.
- GUT: `test_ball_controller_possession.gd`
  - `test_pickup_when_in_range_and_slow`
  - `test_no_pickup_when_ball_fast` (linear_velocity 15 m/s)
  - `test_human_team_wins_simultaneous_pickup`
  - `test_carry_position_offset_in_front_of_player`
- Decisioni: S07-D02, S07-D03
- Post-commit: `memory_store sprint07:T02:ballcontroller-possession-logic`

## T03 — Shoot system (Spacebar hold-charge cubic t³)

- `scripts/ShootingController.gd` — `class_name ShootingController extends Node`:
  - `@export var ball_controller: BallController`
  - In `_physics_process`:
    - if `BallController._carrier == active_player` AND
      `Input.is_action_pressed(_full("shoot_charge"))`:
      - increment `_charge_hold_s += delta`
      - publish to HUD via signal `charge_changed(t_norm: float)`
    - if just released AND `_charge_hold_s >= 0.3`:
      - `t_norm = clamp((hold - 0.3) / 1.2, 0, 1)`
      - `power_norm = t_norm * t_norm * t_norm` (cubic R03-F02)
      - `speed = lerp(15.0, 30.0, power_norm)` (m/s)
      - `dir = (facing * 0.6 + wasd_input * 0.4).normalized()` (S07-D04)
      - elev_deg = lerp(8.0, 12.0, power_norm) (small arc, no full lob)
      - spin = `compose_spin(dir, 2.0, 0, 0)` if speed > 20 else `Vector3.ZERO`
      - `ball_controller.request_release(velocity_vec, spin)`
      - Set `active.state = SHOOTING` for 200 ms (S06 spec A2)
- HUD: `ChargeBar` nodo nuovo (ProgressBar o Control con Rect), bound
  a `charge_changed` signal. Reset on release.
- GUT: `test_shoot_charge_curve.gd`
  - `test_charge_curve_cubic` — hold=0.6s → t_norm=0.25 → power=0.015 ≈ 1.5%
  - `test_min_hold_ignored` — hold < 0.3 s → no shot
  - `test_max_hold_clamped` — hold > 1.5 s → power = 1.0
  - `test_shoot_releases_ball_and_emits_signal`
- Decisioni: S07-D04, S07-D05
- Post-commit: `memory_store sprint07:T03:shoot-charge-curve`

## T04 — Pass system (E key, auto-target 90° cone)

- `scripts/PassingController.gd` — `class_name PassingController extends Node`:
  - `@export var ball_controller: BallController`
  - `@export var team_controller: TeamController` (per leggere `players` array)
  - In `_physics_process`:
    - if `BallController._carrier == active_player` AND
      `controller.consume_buffered("pass_ball")`:
      - compute target via `_select_pass_target(active)`:
        - filter teammates dove `forward.dot(dir_to_t) > 0.707` (R03-F05 90° cone)
        - exclude active itself + GK (per ora)
        - pick nearest if any; else target = `active.position + facing * 10.0`
          (fallback: passaggio "nel vuoto" davanti)
      - call `_launcher.launch_to_point(target_pos)` (esistente Phase 1)
      - override spin: distance < 8 → `compose_spin(dir, -3, 0, 0)` (backspin
        grounder), > 15 → `compose_spin(dir, +4, 0, 0)` (topspin lob), else zero
      - `ball_controller.request_release(launcher_velocity, spin)`
      - Set `active.state = PASSING` per 100 ms (S06 spec A2)
- Helper `_launcher` istanziato in GameMatch (riuso codebase Phase 1).
- GUT: `test_pass_target_selection.gd`
  - `test_pass_target_within_cone_selected`
  - `test_pass_target_outside_cone_ignored`
  - `test_pass_fallback_when_no_teammate_in_cone`
  - `test_pass_short_distance_uses_backspin`
  - `test_pass_long_distance_uses_topspin`
- Decisioni: S07-D06
- Post-commit: `memory_store sprint07:T04:pass-target-selection`

## T05 — Integrate real Ball into GameMatch.tscn

- Remove `MockBall` Node3D, instance `scenes/Ball.tscn` (Phase 1 esistente)
  in its place.
- Wire `BallController` + `ShootingController` + `PassingController` in
  `GameMatch.gd`:
  - 1 `BallController` per match
  - 1 `ShootingController` + 1 `PassingController` per team controllabile
    (riusa `controller.player` ref già esistente)
- HUD: estendi `_update_hud` per mostrare `[BALL: carried by <name>]` se
  posseduta; nasconde altrimenti.
- Debug ball-move keys (T06 di S06) restano funzionanti su ball reale:
  `move_ball_relative(dx, dz)` ora chiama `ball.teleport_to` invece di
  set `global_position` (preserva la fisica).
- GUT: `test_game_match_with_ball.gd`
  - `test_real_ball_instantiated_at_origin`
  - `test_ball_controller_wired`
  - `test_debug_move_uses_teleport`
- Decisioni: nessuna nuova (integrazione)
- Post-commit: `memory_store sprint07:T05:realball-integration`

## T06 — Animation warping (mesh facing snap)

- `Player.tscn`: introduce `VisualRoot` Node3D figlio Player, sposta
  `BodyMesh` + `FrontMarker` sotto di esso.
- `Player.gd`:
  - rename `update_facing` → `update_collision_facing` (slerp slow per
    hitbox).
  - aggiungi `update_visual_facing(dt)` — snap basis del `VisualRoot` a
    `_facing_target` entro 1-2 physics tick (alpha 0.5 per tick).
  - In `_physics_process`: chiama entrambe.
- Effetto: mesh ruota istantaneamente, capsule fisico ruota lentamente
  (lerp 8 esistente).
- GUT: `test_player_visual_warping.gd`
  - `test_visual_root_rotates_within_two_ticks`
  - `test_collision_basis_still_slow_lerp`
- Decisioni: S07-D07
- Post-commit: `memory_store sprint07:T06:animation-warping`

## T07 — GUT regression + perf check

- Full headless suite: target ~100 PASS (83 da S6 + ~15-20 nuovi)
- FPS check visivo in `GameMatch.tscn` con ball reale + 10 player attivi
  → ≥ 60 sustained
- No regressioni Phase 1 (BallPhysics tests intatti)

## T08 — RESEARCH_INDEX update + GAME_DESIGN_LOG calibration sessions + PR/merge/tag

- `RESEARCH_INDEX.md`: append "Sprint 07 — Findings Applied" sezione,
  marcare VALIDATED / PARTIAL / DEFERRED per R02-F01/F02/F03/F06,
  R03-F01/F02/F03/F05/F06, R09-F05 (revalidate).
- `GAME_DESIGN_LOG.md`:
  - Append decisioni S07-D01..D?? alla tabella architettura.
  - Compila "Sprint 07 — Calibration Sessions" con righe T00-T07.
  - **Per ogni finding applicato Sprint 7**, aggiungi una riga alla
    nuova tabella "Findings → Code Mapping" con `RXX-FYY → file:func`.
- Memory store: dump finale di tutte le decisioni S07-D01..D?? in
  `IssNostalgia/gameplay` namespace con `sprint07:T08:decisions-summary`.
- PR `sprint/07-ball-interaction → main`, self-review, merge.
- Tag `v0.7.0-sprint07`.

---

## Exit Criteria

- [x] T00 research verification + plan committed
- [ ] Ball reale (RigidBody3D Phase 1) in `GameMatch.tscn`
- [ ] Player umano raccoglie palla (proximity 0.8 m + ball-speed ≤ 12 m/s)
- [ ] Carry: ball segue carrier, BallPhysics integrator off (freeze KINEMATIC)
- [ ] Shoot: Space hold 0.3-1.5 s, cubic t³ power, lancia ball con
  spin auto, BallPhysics riprende integration
- [ ] Pass: E key, target più vicino in cone 90°, spin auto su distanza
- [ ] Charge bar HUD visibile durante hold
- [ ] Animation warping — mesh ruota istantaneamente su input change
- [ ] GUT 100+ PASS, 0 nuove regressioni Phase 1
- [ ] FPS ≥ 60 sustained
- [ ] PR + merge + tag

## Risk & Mitigation

| Risk | Mitigation |
|------|------------|
| Carry position-copy interferisce con Godot continuous_cd | KINEMATIC freeze disabilita move integration; ball è proprio "rapita" da Godot phys, no CD active |
| Release impulse + apply_launch_state stage doppio | `release()` riusa `_pending_linear/angular` (single source of truth) |
| Pass target selection picca compagno alle spalle | `forward.dot(...) > 0.707` rigorosamente positivo (45° avanti) |
| Charge curve cubic feel troppo "deboli" tiri 50% | Esponente `@export` configurabile in S07-D04 (default 3.0, tarabile 2.0-4.0) |
| Animation warping causa jitter alla collisione | VisualRoot è solo cosmetico; hitbox = capsule originale invariata |

## Workflow notes (post-Sprint 6 update)

- T00 obbligatorio in ogni sprint: research verification + plan + GAME_DESIGN_LOG seed
- Post-commit per ogni Tn: `memory_store IssNostalgia/gameplay` key `sprintNN:Tn:decision-slug`
- T08 obbligatorio: RESEARCH_INDEX "Used in Sprint" update + Findings→Code mapping in GAME_DESIGN_LOG
- AgentDB.totalEntries deve aumentare a ogni store — verifica via `memory_stats` snapshot pre/post
