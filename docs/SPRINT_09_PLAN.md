# SPRINT_09_PLAN.md

## Sprint 09 — Per-Player Attributes + Catch-up Runtime + AI Polish

**Branch**: `sprint/09-magnetic-feel-attributes` (off `main` post `v0.8.0-sprint08`)
**Phase**: Phase 2 — Game Mechanics, quarto sprint
**Modalità**: Checkpoint task-by-task per task soggettive (close-control feel,
catch-up tuning), auto per pure logic / unit tests
**Tag finale**: `v0.9.0-sprint09`

## Goal

Tre moduli ortogonali — chiudono il debito Sprint 8 e portano la demo
da "giocabile vs AI statica" a "match completo con timer, punteggio,
e sensazione di controllo per-giocatore":

- **Per-player attributes + close-control modal** (T01-T02) —
  TeamConfig acquisisce `close_control` e `dribble_skill` per giocatore,
  `BallController` consuma le attribute al posto delle costanti
  walk/sprint hardcoded di Sprint 8, e arriva il modal button (`L1`/
  `Shift`) che attiva il "tight control" mode (carry più stretto,
  loss threshold più alto sotto pressione). Backing R02-F07 + R02-F04
  già documentato.

- **Match scoreboard + clock + catch-up runtime** (T03-T04) —
  infrastruttura `MatchClock` + `Scoreboard` autoload o nodo per HUD,
  poi attivazione del flag `Goalkeeper.is_catchup_eligible()` con la
  vera logica score-gap + final-window (R09-F02). Schema già pronto in
  T06 Sprint 8; T04 lo accende.

- **StaticAI half-change event hybrid** (T05) — completamento del
  pattern R05-F03: oltre alla 2 Hz polling timer, trigger event
  `ball_crossed_halfway` che forza un re-position immediato fuori dal
  ciclo polling. Min interval 1.5 s tra trigger consecutivi.

Exit: match 4-min con punteggio visibile, timer countdown, AI catch-up
quando perde di 2+ goal nell'ultimo minuto, due squadre con player
"tecnici" (close_control alto) distinguibili dai "fisici" (dribble_skill
alto, close_control basso). PR + tag `v0.9.0-sprint09`.

---

## T00 — Research verification + Plan + GAME_DESIGN_LOG seed

**Obbligatorio prima di T01** per regola permanente (issued 2026-05-14).

### Step 1 — Research findings rilevanti (PRIORITY: HIGH/MEDIUM)

Tutti già in `docs/RESEARCH_INDEX.md`; nessuno NEW per questo sprint.

| Finding | How it informs the task | Sprint 9 task |
|---------|--------------------------|---------------|
| **R02-F07** | "Magnetic Feet" = threshold modifier (loss_threshold + carry_offset reduction at low speed). Modal button toggles the mode. | T01 + T02 APPLY |
| **R02-F04** | Per-player Dribbling + Ball Control attribute drives carry distance + carry_speed_ratio (0.85-0.95 elite). | T01 APPLY |
| **R05-F03** | Event-driven + time-guarded hybrid: trigger on ball half-change + 1.5 s min interval between transitions. | T05 APPLY |
| **R09-F02** | Catch-up boost: score gap ≥ 2 in last 60 s → reduce GK reaction buffer ×0.85, +12.5 % shot accuracy for trailing team. Schema already in `Goalkeeper.gd` (Sprint 8 T06). | T04 APPLY |
| **R06-F03** | Camera look-ahead `target += ball_vel.normalized() * clamp(ball_speed * 0.1, 0, 5)`. | DEFERRED → Sprint 10 (camera polish bundle) |
| **R06-F07** | SpringArm3D for camera collision. | DEFERRED → Sprint 10 |
| **R09-F07** | Aftertouch: 0.3-0.5 s post-kick swipe adds ±5 m/s² lateral. | DEFERRED → Sprint 10 (depends on touch input pass) |

### Step 2 — Ruflo memory verification

```
memory_search "close control modal button magnetic dribble skill attribute per-player"
  → R02-F07 (0.65), R02-F04 (0.60) ✓ both already APPLIED-SCHEMA / VALIDATED in S08

memory_search "match clock scoreboard timing soccer arcade"
  → no findings >0.55 — match clock + scoreboard are well-known patterns,
    no external research required (in-house spec in T03).

memory_search "player attributes stats rating skill tight control"
  → R02-F04 (0.54), R02-F07 (0.54) ✓
```

### Step 3 — GAME_DESIGN_LOG seed

Append `## Sprint 09 — Discuss Phase` heading + decisions accepted
(see commit). Findings → Code Mapping table populated as tasks land.

---

## Tasks

### T01 — Per-player attributes schema (TeamConfig + Player)

`resources/TeamConfig.tres` schema additions — per-player rows for:
- `close_control: float = 0.5` (0.0..1.0)
- `dribble_skill: float = 0.5` (0.0..1.0)
- `tight_control_skill_flag: bool = false` (granular skill, see T02)

`scripts/Player.gd`:
- `@export var close_control: float = 0.5`
- `@export var dribble_skill: float = 0.5`
- `@export var has_tight_control: bool = false`

`scripts/GameMatch.gd._instantiate_players` reads attribute per role
from `TeamConfig` and writes onto `Player`.

`scripts/BallController.gd._apply_proximity_kick` consumes
`_carrier.dribble_skill` to lerp between `kick_factor_walk_low` /
`kick_factor_walk_high` (and same sprint pair). High-skill = closer
touch = lower factor.

Tests:
- `test_player_inherits_close_control_from_team_config`
- `test_player_inherits_dribble_skill_from_team_config`
- `test_kick_factor_lerps_with_dribble_skill`

### T02 — R02-F07 close-control modal button + tight control

New input action `p1_tight_control` (key `LShift` reserved? or
modifier — check overlap with sprint). Pick a free key — proposal:
key `Z`.

`scripts/Player.gd`:
- `var tight_control_held: bool = false` (set by PlayerController)
- `func get_effective_carry_offset() -> float`: lerp(0.55, 0.30,
  closeness_factor) where closeness_factor combines speed +
  tight_control_held + close_control attribute.
- `func get_effective_loss_threshold() -> float`: scales `BallController.
  loss_threshold_m` by 1.0..1.25 based on tight_control state.

`scripts/PlayerController.gd._physics_process`:
- Polls `tight_control` action; writes to `player.tight_control_held`.

`scripts/BallController.gd`:
- `turn_glue_offset_m` becomes a function `_carry_offset_for_carrier()`
  that calls `_carrier.get_effective_carry_offset()`.
- `loss_threshold_m` similarly uses `_carrier.get_effective_loss_threshold()`.

Tests:
- `test_tight_control_reduces_carry_offset`
- `test_tight_control_extends_loss_threshold`
- `test_close_control_attribute_floors_offset_at_low_speed`

### T03 — Match scoreboard + clock infrastructure

New `scripts/MatchClock.gd` extends Node:
- `@export var match_duration_s: float = 240.0` (4 min default)
- `current_time_remaining_s: float`
- `signal half_minute_elapsed(remaining_s)`
- `signal match_ended()`
- pause/resume API for goal celebrations (Sprint 10)

New `scripts/Scoreboard.gd` extends Node:
- `var team_a_goals: int = 0`
- `var team_b_goals: int = 0`
- `func register_goal(team: int) -> void:`  ## emits `goal_scored`
- `signal goal_scored(team: int, total: int)`
- `signal score_changed(a: int, b: int)`

`scripts/GameMatch.gd._spawn_match_state` instantiates both, wires
goal-line collision detection (simple: ball.z passes ±52.5 with no
GK catch in last 0.5 s → goal).

HUD additions: timer label, score label.

Tests:
- `test_match_clock_decrements_per_tick`
- `test_match_clock_emits_half_minute_signal`
- `test_match_clock_ends_at_zero`
- `test_scoreboard_increments_on_register_goal`
- `test_scoreboard_emits_score_changed`

### T04 — R09-F02 NBA Jam catch-up runtime activation

Wire scoreboard + clock into `Goalkeeper.is_catchup_eligible()`:

```gdscript
func is_catchup_eligible() -> bool:
    if scoreboard == null or match_clock == null: return false
    if not catchup_boost_enabled: return false
    var my_team_goals = scoreboard.goals_for(_my_team)
    var their_team_goals = scoreboard.goals_for(_other_team)
    var gap = their_team_goals - my_team_goals  ## negative = leading
    if gap < trailing_goal_threshold: return false
    return match_clock.current_time_remaining_s <= time_remaining_threshold_s
```

Apply same pattern to `ShootingController` for the +12.5 % accuracy
boost (Sprint 9 may defer if shot accuracy isn't yet a concept —
schema-only otherwise).

Tests:
- `test_catchup_inactive_when_score_gap_below_threshold`
- `test_catchup_inactive_when_time_above_threshold`
- `test_catchup_active_when_trailing_in_final_window`
- `test_get_effective_reaction_buffer_uses_factor_when_eligible`

### T05 — R05-F03 StaticAI half-change event hybrid

`scripts/StaticAI.gd`:
- Track `_last_ball_half: int` (-1 / +1 based on `signf(ball.z)`).
- On change: force `_update_timer_s = interval` so next `_physics_
  process` immediately re-ticks targets.
- Min interval guard: `_min_seconds_since_event_trigger = 1.5` —
  between event triggers, only the polling timer fires.

Tests:
- `test_static_ai_event_trigger_on_ball_half_change`
- `test_static_ai_event_trigger_respects_min_interval`

### T06 — Sandbox dev-tool polish

Quick wins surfaced during S08 playtest:
- `MMB` resets camera orbit + zoom to defaults (already in HUD docs;
  verify wiring in `GameMatch._unhandled_input`).
- `R` resets ball to centre + clears all carriers.
- HUD displays current `Goalkeeper._last_decision` for the active GK.

Pure dev-tool — no deferred research backing required.

Tests: none required (UI / dev-affordance only). Smoke test in
playtest pass.

### T07 — GUT regression + perf check

- Target: ≥ 215 PASS (Sprint 8 closed at 203; Sprint 9 adds ~3 attr
  + ~3 modal + ~5 clock/scoreboard + ~4 catch-up + ~2 staticAI = +17)
- FPS ≥ 60 sustained con scoreboard + clock attivi + catch-up valutato
- `_physics_process` budget ancora ≤ 4 ms per tick a 120 Hz

### T08 — RESEARCH_INDEX update + GAME_DESIGN_LOG mapping + PR

- `RESEARCH_INDEX.md` "Sprint 09 — Findings Applied" with statuses
- `GAME_DESIGN_LOG.md` Findings → Code mapping populated for R02-F07,
  R05-F03, R09-F02 runtime
- Calibration sessions table (close-control feel, catch-up tuning)
- `memory_store sprint09:T08:decisions-summary` namespace `IssNostalgia/gameplay`
- PR `sprint/09-magnetic-feel-attributes` → `main`, merge,
  tag `v0.9.0-sprint09`

---

## Risk Table

| Risk | Mitigation |
|------|------------|
| Per-player attributes break existing dribble feel | T01 lerps from current Sprint 8 constants — bottom of `dribble_skill = 0.5` reproduces today's behaviour |
| Catch-up boost feels unfair / too obvious | R09-F02 says invisible to player; tune `catchup_gk_reaction_factor` 0.85 (= ~15 % faster) per Turmell range |
| Half-change event firing on every dribble cross-of-halfway | 1.5 s min interval guard; debounce on `signf(ball.z)` only when |z| > 5 m so quick wobbles around centre line don't spam |
| Match clock / scoreboard balloons HUD into a Sprint 10 task | Keep T03 minimal: timer + 2 numbers, no overtime / penalties / replay buttons (those are Sprint 10+) |

---

## Exit Criteria

- [ ] T01: Player + TeamConfig carry per-player attributes; BallController consumes
- [ ] T02: tight-control button + carry/loss thresholds modulate per skill
- [ ] T03: MatchClock + Scoreboard + HUD; goal detection wired
- [ ] T04: Goalkeeper.is_catchup_eligible reads real score + clock
- [ ] T05: StaticAI half-change event trigger fires + respects 1.5 s
- [ ] T06: MMB camera reset + R ball reset + HUD GK debug
- [ ] T07: 215+ GUT PASS, FPS ≥ 60 sustained
- [ ] T08: PR merged, `v0.9.0-sprint09` tag

---

## Research findings — Coverage Summary

| Finding cluster | Sprint 9 task | Status |
|-----------------|---------------|--------|
| R02-F04 (already validated S08) | T01 (consumed by attribute lerp) | EXTEND |
| R02-F07 (Magnetic Feet + tight control) | T01 + T02 | APPLY |
| R05-F03 (event-driven hybrid) | T05 | APPLY |
| R06-F03 (look-ahead) | — | DEFERRED → Sprint 10 (camera bundle) |
| R06-F07 (SpringArm3D) | — | DEFERRED → Sprint 10 |
| R09-F02 (catch-up runtime) | T04 | APPLY |
| R09-F07 (aftertouch) | — | DEFERRED → Sprint 10 (touch-input bundle) |
