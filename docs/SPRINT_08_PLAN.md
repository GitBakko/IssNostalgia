# SPRINT_08_PLAN.md

## Sprint 08 — Close Control + Static AI

**Branch**: `sprint/08-close-control-staticai` (off `main` post `v0.7.0-sprint07`)
**Phase**: Phase 2 — Game Mechanics, terzo sprint
**Modalità**: Checkpoint task-by-task per task soggettive (close-control feel,
GK reach), auto per pure logic / unit tests
**Tag finale**: `v0.8.0-sprint08`

## Goal

Due moduli paralleli, entrambi attesi per chiudere la "demo giocabile vs
AI statica" da merge a `main`:

- **Close Control** (T01-T03) — sostituisce il carry "incollato" di
  Sprint 7 con il **touch-cycle dribble** delle simulazioni reali: la
  palla viene spinta in avanti a brevissima distanza, il giocatore la
  rincorre, la ri-controlla. Speed-modulated carry offset, ball_speed
  coupled a player_speed (ratio elite 0.88-0.95), loss threshold
  1.6 m. Pattern documentato e già mappato — non riscoperta. Vedi
  R02-F04/F05/F07 per backing literature; tutti applicati in T01-T03.

- **Static AI + Goalkeeper** (T04-T06) — i 5 giocatori della Team B
  AI smettono di essere bersagli statici. Riposizionamento per ruolo
  basato su anchor formation + ball-attraction factor (R05-F01..F06),
  goalkeeper con teleport-on-trajectory + give-up gate (R04-F01..F06).
  Niente NavMesh, niente Voronoi dinamico — pattern arcade leggero
  da 2 Hz tactical update.

Exit: una partita demo end-to-end giocabile contro l'AI. Team A umano
attacca, Team B AI riposiziona difensori e fa parate ragionevoli sul
goal. Niente tackle attivo, niente possesso da parte dell'AI (Sprint
9 polish). Replay buffer Sprint 5 ancora disponibile per debug.

---

## T00 — Research verification + Plan + GAME_DESIGN_LOG seed

**Obbligatorio prima di T01** (workflow rule introdotto post-Sprint 6,
applicato per la prima volta in Sprint 7).

### Step 1 — Research findings rilevanti (PRIORITY: HIGH/MEDIUM)

Letti da `docs/RESEARCH_INDEX.md`. Tutti i finding sotto sono già
mappati al task — **nessun TBD**. La documentazione è pronta, deve
essere applicata, non riscoperta.

#### Close Control (T01-T03)

| ID | Source (short) | Apply Where | Status S8 |
|----|----------------|-------------|-----------|
| **R02-F04** | EA Sports FIFA 23 / FC 25/26 Pitch Notes — attribute-driven touch intervals; elite players retain 88-95 % sprint speed with ball | `BallController.carry_offset_m = lerp(0.3, 0.5, player_speed/max_walk_speed)`. Quando il carrier sprinta, `ball.linear_velocity = carrier.velocity * lerp(0.88, 0.95, dribble_skill)`. **MVP** ratio fisso 0.92 (no per-player attributes ancora). | T01 APPLY |
| **R02-F05** | GameDev.tv + Unity forum dribbling — 3 architetture; **C) proximity + position-copy** scelta. Loss threshold 1.6 m (= 2× pickup radius) | Touch-cycle: `BallController` ogni `touch_interval_s` (0.6 s walk, 0.4 s sprint) chiama `ball.release(carrier.velocity * touch_speed_ratio, ZERO)` con piccolo impulse forward. Re-pickup automatico via `_try_pickup` quando il carrier raggiunge la palla. **Loss threshold**: se `|ball - carrier|` > 1.6 m mentre `ball` non è frozen, possesso perso (gate sul `_try_pickup` esistente già copre il riacquisto, basta NON ri-armare il lockout post-release). | T02 APPLY |
| **R02-F07** | eFootball Magnetic Feet skill + PES Mastery — magnetic feel via threshold + offset modulation, NO foot-IK | `Player.dribble_skill: float = 0.5` (0..1, MVP costante; Sprint 9+ legato a TeamConfig). `carry_offset_mag = lerp(0.3, 0.5, speed/7.0)`. Future "Tight Control" skill flag (booleano per player) raisera loss threshold da 1.6 → 2.0 m — schema ready ma flag default false. | T03 APPLY |

**Note Close Control**:
- Architettura C compatibile col custom integrator BallPhysics — la
  palla rimane RigidBody3D guidata dal proprio `_integrate_forces`,
  BallController emette impulse periodici via `apply_launch_state`.
- Il "post-release lockout" da Sprint 7 fix2 va MODIFICATO: lockout
  globale 0.3 s ora rompe il touch-cycle (intervallo 0.4 s sprint).
  Soluzione: lockout solo per "release intenzionale" (shoot/pass) e
  NESSUN lockout per "release di touch-dribble". Nuovo parametro
  `BallController.request_release(velocity, angular, kind)` con
  `kind ∈ {SHOOT, PASS, TOUCH}`.
- Receiver pre-orientation warp (R09-F04) resta attivo solo per
  `kind ∈ {SHOOT, PASS}`, NON per touch (sarebbe rumore continuo).

#### Static AI + Goalkeeper (T04-T06)

| ID | Source (short) | Apply Where | Status S8 |
|----|----------------|-------------|-----------|
| **R05-F01** | Game AI Pro 2 Ch.30 (Dave Mark) — influence maps non per-frame; tactical 2-5 Hz | `StaticAI._physics_process` aggiorna `target_position` ogni 0.5 s (2 Hz), non ogni tick. Mobile CPU friendly. | T04 APPLY |
| **R05-F02** | arxiv 2501.05870 — Voronoi statico = formation anchors | Nessuna Voronoi computation. `target_position = anchor + (ball - anchor) * role_factor`. Zone corrette by construction. | T04 APPLY |
| **R05-F03** | GameDev.net Soccer AI — event-driven + time-guarded hybrid | Trigger event: ball cross halfway OR possession change. Min interval 1.5 s. Conferma role_factor: GK=0.1, def=0.3, mid=0.5, att=0.7. | T04 APPLY |
| **R05-F04** | grant.tuxinator.net — analytical target O(1) per agent, no grid | Skip influence grid. Compute analytically. `lerp_alpha = dt / 1.5` per posizionamento smooth. | T04 APPLY |
| **R05-F05** | Frontiers PMC12163489 — role-differentiated positioning empiricamente validato | Mantieni gradient monotonic 0.1/0.3/0.5/0.7. Spacing ~0.2 tra ruoli adiacenti. | T04 APPLY |
| **R05-F06** | Game AI Pro 1 Ch.21 — anchor vs slot; velocity-clamped lerp | Anchors only in Phase 2. `max_reposition_speed` 6-10 m/s per role per evitare teleport. | T04 APPLY |
| **R04-F01** | calculatorcorp.com — reachability formula `t_av = max(0, t_f - t_r - t_buf)`, `d_eff = max(0, d_lat - r)` | `Goalkeeper._can_reach_shot(ball)`: chiama `BallPhysics.predict_forward(t_f)`, calcola `d_eff/gk_speed > t_av` → teleport, else give up. | T05 APPLY |
| **R04-F02** | PMC8812381 — penalty GK science: 600 ms response budget, commit 100-250 ms before contact | Teleport-on-trajectory cheat fisicamente motivato. Trigger condizioni come F01. | T05 APPLY |
| **R04-F03** | PMC3590836 — elite GK reazione 193 ± 67 ms; 66.3 % save success | **Phase 3 target**: 0.1-0.2 s simulated reaction delay. **Phase 2 skips** (cheat è intenzionale, no delay). | T05 DEFERRED → Phase 3 |
| **R04-F04** | gamedeveloper.com — predictive aim 1-axis intercept | Reusa `BallPhysics.predict_forward(t_flight)`. Clamp intercept_x a `[-3.2, 3.2]`. No new math. | T05 APPLY |
| **R04-F05** | FIFA Training Centre + Keeperstop — GK angle bisect ball→posts | `gk_idle_target_x = clamp(ball_x * 0.5, -3.2, 3.2)`. GK Z = goal_line + 1.0-1.5 m. Spec speed 6.0, lerp 0.15. | T05 APPLY |
| **R04-F06** | forrestthewoods + GDC arcade AI — 3 cheats: teleport, X-only shadow, give-up gate | Phase 2 = pattern 1 + give-up gate (`abs(intercept_x) > 3.2` OR `predicted_height > 2.44 m`). Play save anim anche su teleport per leggibilità. | T05 APPLY |
| **R09-F02** | NBA Jam Postmortem GDC 2018 — silent catch-up boost on trailing AI | **Sprint 8/9 phase 3 polish**: AI shot accuracy +10-15 % e GK reaction -15 % se trail ≥ 2 goals con < 60 s. Schema pronto, applicazione deferred a Sprint 9 (richiede scoreboard). | T06 SCHEMA-ONLY |

### Step 2 — Ruflo memory search verification

Da eseguire prima di T01 con queste query (namespace `IssNostalgia/research`):
- `"close control touch dribble ball at foot"` → conferma R02-F04/F05/F07 top-3
- `"goalkeeper reaction teleport reachability arcade"` → conferma R04-F01/F02/F06 top-3
- `"static AI formation anchor influence map"` → conferma R05-F01/F02/F03 top-3
- `"NBA Jam catch-up boost trailing AI"` → conferma R09-F02 top-1

Output atteso: tutti i finding sopra restituiti con similarity > 0.6.
Se NO, c'è disallineamento knowledge base → fix prima di T01.

### Step 3 — GAME_DESIGN_LOG seed

In testa a Sprint 8 nel `GAME_DESIGN_LOG.md`, sezione "Findings → Code
Mapping (S08)", template come Sprint 7 — popolato durante esecuzione.

---

## Tasks

### T01 — Close Control: speed-modulated carry offset (R02-F04)

Replace `BallController.CARRY_OFFSET_LOCAL` constant con un calcolo
runtime in `_sync_carry_position`:

```gdscript
@export var carry_offset_min_m: float = 0.3   ## walk
@export var carry_offset_max_m: float = 0.5   ## sprint
@export var carry_offset_y: float = -0.7      ## ankle height (Sprint 7)
@export var ball_speed_ratio: float = 0.92    ## elite range 0.88-0.95

func _sync_carry_position():
    var carrier_speed = _carrier.velocity.length()
    var t = clampf(carrier_speed / _carrier.max_walk_speed, 0.0, 1.0)
    var z_offset = -lerpf(carry_offset_min_m, carry_offset_max_m, t)
    var local_offset = Vector3(0.0, carry_offset_y, z_offset)
    var world_offset = _carrier.get_visual_basis() * local_offset
    ball.global_position = _carrier.global_position + world_offset
```

Tests:
- `test_carry_offset_modulates_with_speed` — walk → 0.3 m, sprint → 0.5 m
- `test_carry_offset_clamped_at_walk_max` — speed > max_walk uses 0.5 m

### T02 — Touch-cycle dribble (R02-F05)

Aggiungi state machine in `BallController`:
- `_touch_timer_s: float`
- `@export var touch_interval_walk_s: float = 0.6`
- `@export var touch_interval_sprint_s: float = 0.4`
- `@export var touch_speed_ratio: float = 0.95` (palla esce a 95 % player speed)

In `step(delta)`:
```
if _carrier != null and _carrier.velocity.length() > 0.5:
    _touch_timer_s += delta
    var interval = touch_interval_sprint_s if sprinting else touch_interval_walk_s
    if _touch_timer_s >= interval:
        _emit_touch()
        _touch_timer_s = 0.0
```

`_emit_touch()` chiama `request_release(carrier.velocity * touch_speed_ratio,
ZERO, RELEASE_KIND.TOUCH)`. La palla esce, vola in avanti, BallPhysics
applica drag e rolling friction. Carrier rincorre. `_try_pickup` ri-attiva
quando carrier raggiunge la palla (entro 0.8 m + ball |v| < 12 m/s).

**`request_release` modificato**:
```
enum ReleaseKind { SHOOT, PASS, TOUCH }
func request_release(velocity, angular, kind):
    ...
    if kind != ReleaseKind.TOUCH:
        _pickup_lockout_remaining_s = post_release_lockout_s
    ball.release(velocity, angular)
```

Tests:
- `test_touch_emitted_at_walk_interval` — 0.6 s walk → emit
- `test_touch_emitted_at_sprint_interval` — 0.4 s sprint → emit
- `test_touch_kind_no_lockout` — touch release non arma lockout
- `test_loss_threshold_at_1_6_m` — se carrier si allontana > 1.6 m
  da palla, possesso perso (no auto re-pickup; serve avversario o
  ri-pickup esplicito post 1.6 m drift)

### T03 — Magnetic feel + dribble_skill (R02-F07)

Aggiungi a `Player`:
```
@export_group("Dribbling")
@export var dribble_skill: float = 0.5  ## 0..1 — MVP costante
@export var tight_control: bool = false  ## "Tight Control" skill flag
```

Loss threshold dipende da skill:
```
const LOSS_THRESHOLD_BASE_M = 1.6
const LOSS_THRESHOLD_TIGHT_M = 2.0
var loss_threshold = LOSS_THRESHOLD_TIGHT_M if carrier.tight_control else LOSS_THRESHOLD_BASE_M
```

Tests:
- `test_tight_control_raises_loss_threshold` — flag true → 2.0 m
- `test_dribble_skill_clamped_0_1` — out-of-range value clamped

### T04 — Static AI formation positioning (R05-F01..F06)

Nuovo `scripts/StaticAI.gd` extends Node:
- `@export var team_controller: TeamController` (per leggere players)
- `@export var ball_ref: BallPhysics`
- `@export var update_hz: float = 2.0`
- Tactical update timer: `_update_timer_s`
- Per ogni player non-attivo: `target_position = anchor + (ball - anchor) * role_factor`
- `Player` riceve `target_position` via nuovo metodo
  `Player.set_static_target(pos, max_speed)` che agisce come autopilot
  (lerp velocity verso target invece di leggere input)

Role factors (R05-F03):
- GK = 0.1
- DEF = 0.3
- MID = 0.5
- ATT = 0.7

Posizionamento smoothness:
- `lerp_alpha = dt / 1.5` (R05-F04)
- `max_reposition_speed = 6-10 m/s` per role (R05-F06)

Spawn: `GameMatch._spawn_team_b` aggiunge `StaticAI` come child di
`team_b_root` con riferimenti già wired. Esegue solo se
`team_b_ctrl.is_human == false` (AI side).

Tests:
- `test_static_ai_target_uses_role_factor`
- `test_static_ai_skips_active_human_players` (Team A non viene
  pilotato anche se richiamato per errore)
- `test_static_ai_updates_at_2_hz` (5 tick ≠ 5 update)

### T05 — Goalkeeper reactive save (R04-F01..F02/F04..F06)

Nuovo `scripts/Goalkeeper.gd` extends Node (controller specializzato
per il GK, NON modifica Player):
- `@export var goalkeeper: Player` (il GK del proprio team)
- `@export var ball: BallPhysics`
- `@export var goal_z: float`  (own goal line, ±52.5)
- `@export var goal_half_width_m: float = 3.2`
- `@export var crossbar_height_m: float = 2.44`
- `@export var gk_speed: float = 6.0`
- `@export var idle_lerp: float = 0.15`
- `@export var reaction_buffer_s: float = 0.05`
- Idle: `idle_target_x = clamp(ball.x * 0.5, -3.2, 3.2)` (R04-F05)
- Save trigger: ogni tick computa `t_flight = (goal_z - ball.z) / ball.linear_velocity.z`,
  se positivo chiama `ball.predict_forward(t_flight)` per ottenere
  `intercept_x` (R04-F04)
- Give-up gate (R04-F06): `abs(intercept_x) > 3.2` OR `predicted_height > 2.44`
- Reachability (R04-F01): `d_eff = max(0, abs(intercept_x - gk_x) - r)`,
  `t_av = max(0, t_flight - reaction_buffer)`, `d_eff/gk_speed > t_av`
  → teleport gk a `intercept_x`. Else lerp idle_target.
- `Player.state = SAVING` (nuovo enum value) per anim placeholder

Tests:
- `test_gk_idle_tracks_ball_x_at_half`
- `test_gk_teleport_when_unreachable`
- `test_gk_gives_up_outside_post_width`
- `test_gk_gives_up_above_crossbar`
- `test_gk_does_nothing_for_grounder_passing_outside`

### T06 — NBA Jam catch-up boost schema (R09-F02)

**Schema-only T06** — applicazione runtime deferred a Sprint 9
(richiede scoreboard). In Sprint 8 si codifica solo:
- `@export var catchup_boost_enabled: bool = false`
- `@export var trailing_goal_threshold: int = 2`
- `@export var time_remaining_threshold_s: float = 60.0`
- `@export var catchup_accuracy_boost: float = 0.125`
- `@export var catchup_gk_reaction_factor: float = 0.85`

Hook function `Goalkeeper.get_effective_reaction_time()` che ritorna
`reaction_buffer_s * (catchup_gk_reaction_factor if eligible else 1.0)`.
Eligibility check ritorna sempre false in Sprint 8 (no scoreboard).

Tests:
- `test_catchup_boost_disabled_by_default`
- `test_catchup_eligibility_returns_false_without_scoreboard`

### T07 — GUT regression + perf check

- Target: ≥ 145 PASS (Sprint 7 chiude a 134, Sprint 8 aggiunge
  ~12 close-control + ~10 static AI + ~8 GK + ~2 catchup = +32)
- FPS ≥ 60 sustained con close-control attivo (palla in volo + 4
  AI players moving + GK tracking)
- Profiler check: `_physics_process` budget ≤ 4 ms per tick a 120 Hz
  con tutto attivo

### T08 — RESEARCH_INDEX update + GAME_DESIGN_LOG mapping + PR

- `RESEARCH_INDEX.md` "Sprint 08 — Findings Applied" con stati
  VALIDATED / PARTIAL / DEFERRED per R02-F04/F05/F07 + R04-all + R05-all
- `GAME_DESIGN_LOG.md` Findings → Code mapping section popolata
- Calibration sessions tabella (close-control feel, GK timings)
- `memory_store sprint08:T08:decisions-summary` namespace `IssNostalgia/gameplay`
- PR `sprint/08-close-control-staticai` → `main`, merge, tag `v0.8.0-sprint08`

---

## Risk Table

| Risk | Mitigation |
|------|------------|
| Touch-cycle interval troppo aggressivo / felpa rotta | Inizia con 0.6 s walk / 0.4 s sprint (literature defaults), tune in playtest. Lockout TOUCH disabilitato evita re-pickup glitch. |
| Loss threshold rompe possesso "normale" | 1.6 m è 2× pickup radius. Se carrier sta passando palla a se stesso (degenerate), pickup non scatta in lockout SHOOT/PASS. Touch non triggera lockout → pickup normale al recovery. |
| Static AI "vibra" tra anchor e ball-attracted target | `lerp_alpha = dt / 1.5` smoothing, 2 Hz tactical (no per-tick jitter), max_reposition_speed clampa salti. |
| GK teleport visibile come "scatto innaturale" | R04-F02: gli umani veri si pre-committano 100-250 ms prima del contatto, quindi il teleport NON è irrealistico. Save anim sopra il teleport per leggibilità. Phase 3 aggiungerà reaction delay R04-F03. |
| FPS scende sotto 60 con tutto attivo | StaticAI a 2 Hz invece di 120 Hz è il principale buffer. Profiler check in T07 — se serve, taglia GK predict_forward a 60 Hz invece di 120. |
| Glitch interazione close-control + receiver pre-warp da Sprint 7 | Pre-warp solo su kind ∈ {SHOOT, PASS}. Touch kind = no warp. Test esplicito `test_touch_does_not_arm_warp`. |

---

## Exit Criteria

- [ ] T01-T03: close-control playabile, palla "viva" davanti al
      giocatore, 1.6 m loss threshold rispettato
- [ ] T04: 4 AI players Team B si riposizionano per ruolo,
      smooth lerp, no scatti
- [ ] T05: GK Team B salva tiri raggiungibili, ignora tiri fuori
      post / sopra traversa, idle bisect ball/posts
- [ ] T06: catch-up boost schema in place, tutti i flag esposti
- [ ] T07: ≥ 145 GUT PASS, 60 FPS sustained playtest
- [ ] T08: RESEARCH_INDEX + GAME_DESIGN_LOG aggiornati,
      `sprint08:T08:decisions-summary` in AgentDB,
      PR mergeata in `main`, tag `v0.8.0-sprint08`

---

## Research findings — Coverage Summary

| Finding | Sprint 8 task | Apply / Defer |
|---------|---------------|---------------|
| R02-F04 | T01 | APPLY |
| R02-F05 | T02 | APPLY |
| R02-F07 | T03 | APPLY |
| R04-F01 | T05 | APPLY |
| R04-F02 | T05 | APPLY |
| R04-F03 | — | DEFERRED → Phase 3 (reaction delay) |
| R04-F04 | T05 | APPLY (reuses `predict_forward`) |
| R04-F05 | T05 | APPLY |
| R04-F06 | T05 | APPLY (give-up gate) |
| R05-F01..F06 | T04 | APPLY |
| R05-F07 | — | DEFERRED → Phase 3 (Temporal Voronoi) |
| R09-F02 | T06 | SCHEMA-ONLY (runtime in Sprint 9) |

**Documentation status**: tutti i finding sopra sono già letti, già
collocati nel `RESEARCH_INDEX.md` con sprint assignment esplicito
(non più `_TBD_`). Vector memory `IssNostalgia/research` ne contiene
le full-text entries (62 total). T00 verifica semantic recall come
gate — se la similarity di una query rilevante scende sotto 0.6,
investigare disallineamento KB prima di proseguire.
