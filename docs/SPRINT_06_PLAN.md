# SPRINT_06_PLAN.md

## Sprint 06 — Player Entity & Control

**Branch**: `sprint/06-player-entity` (off `main` @ `cbf5f75`, post `v0.5.0-sprint05`)
**Phase**: Phase 2 — Game Mechanics, primo sprint
**Modalità**: Checkpoint task-by-task (commit + push + "ok prosegui" tra una task e la successiva)
**Tag finale**: `v0.6.0-sprint06`

## Goal

Mettere in campo **10 giocatori** (5 vs 5, formazione 2-1-1 + portiere), con il
giocatore umano che ne controlla uno alla volta su Team A. Niente palla in
questo sprint — solo **movimento, sprint, stamina, selezione manuale (Q),
auto-switch ipotetico (driven da una `Vector3` mock-ball)**, e tutta
l'infrastruttura su cui Sprint 7-9 si appoggeranno (ActionMap, input buffering,
TeamConfig, FormationData).

Exit: una scena `GameMatch.tscn` apribile in editor che mostra 10 capsule
colorate sul campo, il giocatore umano si muove, sprinta con stamina, ruota
fluidamente, l'indicatore di selezione segue auto-switch o Q manuale, gli altri
9 stanno fermi nelle loro posizioni di formazione.

## Tasks

### T00 — Plan + GAME_DESIGN_LOG seed (questo file)
- `docs/SPRINT_06_PLAN.md` (questo)
- `docs/GAME_DESIGN_LOG.md` con 30 decisioni S06-D01..D30 dal discuss-phase
- Branch `sprint/06-player-entity` creato

### T01 — TeamConfig.gd + FormationData.gd (typed Resources)
- `resources/TeamConfig.gd` — `class_name TeamConfig extends Resource`:
  - `@export var team_name: String = "TEAM"`
  - `@export var primary_color: Color = Color.WHITE`
  - `@export var formation_id: StringName = &"2-1-1"`
- `resources/FormationData.gd` — `class_name FormationData extends Resource`:
  - `@export var formation_id: StringName`
  - `@export var role_anchors: Array[Vector3]` (4 outfield + 1 GK = 5 entries)
  - `@export var role_factors: Array[float]` (influence_factor per ruolo, GK ignorato a runtime)
  - `@export var role_names: Array[StringName]` (`def`, `def`, `mid`, `att`, `gk`)
- `resources/formations/formation_2_1_1.tres` — preset 2-1-1 con anchor coordinati
  rispetto al campo 105 × 68 m (origine al centro)
- `resources/teams/team_a.tres` (blu) + `resources/teams/team_b.tres` (rosso)
- Decisioni: S06-D07 (offset per ruolo), S06-D22 (colori), S06-D23/D24 (Resource design)
- **No GUT test** — pure Resource, validato in editor

### T02 — Player.gd + Player.tscn (state machine, no input ancora)
- `scripts/Player.gd` — `class_name Player extends CharacterBody3D`:
  - State machine: `IDLE | RUNNING | TURNING | (PLACEHOLDER_SHOOT | PLACEHOLDER_PASS)`
  - `@export var team_config: TeamConfig`
  - `@export var role_index: int` (0..4, posiziona via FormationData)
  - `@export var is_goalkeeper: bool = false`
  - `var max_walk_speed: float = 5.5`
  - `var max_sprint_speed: float = 8.0`
  - `var accel: float = 20.0` (single-phase per ora, two-phase ramp R01-F06 → backlog)
  - `var rotation_speed: float = 8.0` (per `transform.interpolate_with`)
  - `var stamina: float = 1.0` (0..1, 3 s sprint = -0.333/s, 5 s recovery = +0.20/s)
  - Pure-function `apply_movement(input_dir: Vector3, sprint_held: bool, dt: float)` (testabile)
  - `_physics_process` chiama `move_and_slide()` con velocity calcolato
  - Mesh facing: `basis.slerp(target_basis, alpha)` con alpha frame-rate-independent
- `scenes/Player.tscn`:
  - `CharacterBody3D` root (Player.gd)
  - `CapsuleMesh` (radius 0.4, height 1.8) con `material_override` driven da `team_config.primary_color` in `_ready`
  - `CollisionShape3D` `CapsuleShape3D` (matching mesh)
  - Layer 2 (Players) — mask `{1, 2, 3}` (World, Players, Ball) (R08-F02 anticipato)
- GUT: `tests/unit/test_player_movement.gd`
  - `test_walk_speed_clamp` — input WASD, stamina pieno, sprint OFF → `velocity.length() ≤ 5.5`
  - `test_sprint_speed_clamp` — sprint ON, stamina > 0 → `velocity.length() ≤ 8.0`
  - `test_stamina_drain` — sprint per 3 s → stamina ≈ 0 (entro 5 %)
  - `test_stamina_recovery_gated` — sprint OFF per 5 s → stamina ≈ 1 (entro 5 %)
  - `test_stamina_recovery_blocked_during_sprint` — sprint ON con stamina vuota → resta a 0
- Decisioni: S06-D04 (stamina gate), S06-D21 (single class + flag), S06-D22 (capsule)

### T03 — ActionMap + PlayerController.gd (input WASD)
- `project.godot` `[input]`: aggiungi 6 InputMap actions:
  - `move_forward`, `move_back`, `move_left`, `move_right` (WASD)
  - `sprint` (Shift)
  - `switch_player` (Q)
  - `shoot_charge` (Space) — bind ora, useless finché Sprint 7
  - `pass_ball` (E) — idem
- `scripts/PlayerController.gd` — `class_name PlayerController extends Node`:
  - `@export var player: Player`
  - In `_physics_process`: legge InputMap, computa `input_dir: Vector3` su XZ, chiama `player.apply_movement(...)`
  - `is_shooting: bool` + `is_passing: bool` flags (esposti per TeamController auto-switch block)
  - **Input buffering** (S06-D26 / R09-F05): ring buffer ultimi `100 ms` di action presses; se l'azione non era consumabile al frame del press ma ora lo è (es. switch durante shot), la firma
  - **Coyote framework**: 6-frame window post-azione-non-valida (es. switch quando già in possesso non blocca, Sprint 7+ varrà)
- GUT: `tests/unit/test_player_controller.gd`
  - `test_input_dir_diagonal_normalized` — pressing forward+right → `input_dir.length() ≈ 1.0`
  - `test_input_buffering_fires_when_valid` — buffer un'azione, attendere 50 ms, se diventa valida → fired
  - `test_input_buffering_expires_after_100ms` — buffer + 150 ms → discarded

### T04 — TeamController.gd (auto-switch + manual cycle Q + indicatore visivo)
- `scripts/TeamController.gd` — `class_name TeamController extends Node`:
  - `@export var players: Array[Player]` (5 elementi)
  - `@export var team_config: TeamConfig`
  - `@export var is_human: bool = false`
  - `@export var ball_ref: Node3D` (mock Node3D in Sprint 6, vero RigidBody in Sprint 7)
  - `var active_index: int = 0`
  - **Auto-switch logica** (S06-D01 / S06-D03):
    - Se `is_human == false`: skip
    - Trova il giocatore più vicino alla palla (by `length_squared` su XZ)
    - Se `(active.distance > 8.0 + 0.5) AND (closest != active) AND (NOT controller.is_shooting AND NOT controller.is_passing)`:
      - Setta `pending_switch_index = closest.index`, `pending_switch_frames = 3`
    - Decremento `pending_switch_frames` ogni physics tick; arrivato a 0 → commit switch
    - Hysteresis dead zone 0.5 m intorno alla soglia 8 m (no switch quando active dist ∈ [7.5, 8.5])
  - **Manual switch** (Q): cycle `active_index` su `(active_index + 1) % 5`, ignorando GK in cycle
  - Tie-breaker (S06-D03): umano > AI implementato facendo iterare PRIMA i player umani in caso di distanze uguali (irrilevante in Sprint 6 perché solo 1 team umano, ma codifica già il pattern)
- **Indicatore visivo**: `MeshInstance3D` (cylinder anello, raggio 0.6 m, h=0.02) figlio di ogni Player; alpha 0.85 sotto active, 0.25 sotto gli altri della squadra umana, hidden per AI team
  - Color = `team_config.primary_color`
- GUT: `tests/unit/test_team_controller.gd`
  - `test_autoswitch_triggers_above_threshold` — active a 10 m da ball, altro a 2 m → switch dopo 3 frames
  - `test_autoswitch_blocked_during_shoot` — same scenario ma controller.is_shooting=true → no switch
  - `test_autoswitch_hysteresis_dead_zone` — active a 8.2 m → no switch (dentro dead zone)
  - `test_manual_q_cycles_skipping_gk` — Q 4 volte → torna a indice 0 saltando GK
  - `test_tie_breaker_human_wins` — due distanze uguali su team umano → indice umano scelto

### T05 — GameMatch.tscn (10 player + mock ball + camera placeholder)
- `scenes/GameMatch.tscn`:
  - Root `Node3D` (placeholder MatchManager — vero in Sprint 8)
  - `Pitch` MeshInstance3D 105×68 m, verde semplice (riuso o copia da PhysicsSandbox)
  - `TeamA` Node3D + 5 Player istanze (4 outfield + 1 GK), posizionate via FormationData
  - `TeamB` Node3D + 5 Player istanze idem (mirror su Z)
  - `MockBall` Node3D (sphere mesh r=0.11, no physics) controllabile via tasti `[`/`]`/`;`/`'` per spostarla manualmente in test (tasti debug, da rimuovere Sprint 7)
  - `Camera3D` placeholder fissa broadcast (da Phase 1 sandbox)
  - `TeamControllerA` (is_human=true, ball_ref=MockBall)
  - `TeamControllerB` (is_human=false, ball_ref=MockBall)
  - HUD minimo: `Label` con stamina giocatore attivo + nome ("Player N")
- Validazione visiva: aprire scena, muovere player umano con WASD, spostare MockBall con `[` `]` `;` `'`, vedere autoswitch + indicatore + manual Q
- **No GUT** (scena, non logica) — checkpoint manuale utente

### T06 — Debug toggles & both_human flag
- Aggiungere `@export var both_human: bool = false` su `GameMatch.tscn` root
  - Quando true: TeamControllerB.is_human = true, comandi Team B = mappature alternative (Frecce per movimento, RShift sprint, Numpad-Enter switch)
  - Documenta nel HUD se entrambi human
- Tasti debug `[`/`]`/`;`/`'` per spostare MockBall (X +/-, Z +/-) di 1 m per pressione
- Tasto `B` per "boost-ball" — sposta MockBall a posizione random sul campo (test rapido autoswitch)
- Decisione: S06-D29 (both_human flag)
- **No GUT** — debug only

### T07 — GUT regression + perf check
- Run full suite headless: target ~38-40 PASS (30 da Sprint 5 + ~8-10 nuovi in Sprint 6)
- FPS check: aprire `GameMatch.tscn` su dev box, misurare HUD FPS con tutti i 10 player presenti, vari movimenti del player umano. Target ≥ 60 (Compatibility renderer, MSAA 2×).
- No regressioni Sprint 1-5

### T08 — GAME_DESIGN_LOG update + PR/merge/tag
- Compila la sezione "Sprint 06 — Calibration Sessions" in `GAME_DESIGN_LOG.md` con righe per task (T01-T07) + notes su scelte non triviali emerse
- Aggiorna `RESEARCH_INDEX.md` colonna "Used in Sprint" per i finding effettivamente applicati (R01-F04, R02-F02/06, R06-F06, R07-F03, R09-F05 ecc.)
- PR `sprint/06-player-entity → main`, self-review checklist, merge
- Tag `v0.6.0-sprint06`

## Exit Criteria

- [x] (T00) `SPRINT_06_PLAN.md` + `GAME_DESIGN_LOG.md` esistono e committati
- [ ] `GameMatch.tscn` apribile, mostra 10 capsule colorate (5 blu + 5 rosse) in formazione 2-1-1
- [ ] Giocatore umano si muove con WASD entro `5.5 m/s` walking / `8.0 m/s` sprint
- [ ] Stamina: 3 s sprint la consuma, 5 s di rilascio la ripristina, mai sotto 0 mai sopra 1
- [ ] Indicatore visivo (anello) sotto giocatore attivo, dimmer sugli altri umani, hidden su AI
- [ ] Auto-switch funziona: spostando MockBall, dopo 3 physics frame il controllo passa al giocatore Team A più vicino, RISPETTANDO hysteresis e i flag `is_shooting`/`is_passing`
- [ ] Manual Q cicla i 4 outfield (skip GK)
- [ ] `both_human=true` permette controllo Team B con Frecce + RShift + Numpad-Enter
- [ ] FPS ≥ 60 in `GameMatch.tscn` con tutti i 10 player attivi
- [ ] GUT 38+ PASS, 0 nuove regressioni
- [ ] PR mergiata, tag `v0.6.0-sprint06` pushato

## Out of Scope (rimandato a Sprint 7+)

- Palla vera + possesso + carry (Sprint 7)
- Tiro / passaggio / spin auto (Sprint 7)
- StaticAI movimento opponent (Sprint 8)
- MatchManager state machine completa (Sprint 8)
- Goal detection (Sprint 8)
- Camera dinamica centroid + zoom + bounds (Sprint 9)
- HUD completo con score/timer/goal-banner (Sprint 9)
- Audio placeholder (Sprint 9)
- Two-phase acceleration ramp R01-F06 (backlog Sprint 9 polish)
- Animation warping mesh facing snap (Sprint 7 — quando arriva il carry / shoot animation)

## Risk & Mitigation

| Risk | Mitigation |
|------|------------|
| `move_and_slide()` interagisce male con multiple CharacterBody3D vicine | Test in T05 con 10 player concentrati al centro. Se jitter, applica R08-F02 mask `{1, 2}` solo su player→player |
| Indicatore visivo (anello) tra player ↔ player blocca raycast camera futura | Indicatore su layer dedicato (es. layer 5 "FX"), escluso da SpringArm3D Sprint 9 |
| Frame-rate-independent lerp su rotation produce numeric drift | Usa `basis.slerp(target_basis, alpha_clamped)` non `interpolate_with` su transform completo (transform include translation) |
| GUT test per stamina dipende da `dt` reale → flaky | Pure-function `apply_movement(dt)` con `dt` esplicito passato dal test, non `_physics_process` |
| `both_human` debug flag dimentica di chiudere indicatori avversari | T06 commenta esplicitamente: quando `both_human=true`, indicatori visibili anche su Team B con team_b.primary_color |

## Decisions referenced (S06-D01..D30 in GAME_DESIGN_LOG)

T01 → D07, D22, D23, D24
T02 → D04, D21, D22
T03 → D25, D26
T04 → D01, D03, D29
T05 → D29
T06 → D29

R01-R09 findings utilizzati (vedi RESEARCH_INDEX.md per dettagli):
- R01-F03 (input lag < 100 ms), R01-F04 (basis.slerp rotation), R01-F05 (stamina patterns)
- R02-F02/F06 (freeze pattern — Sprint 7 prep, schema designed in TeamController)
- R06-F06 (frame-rate independent lerp — applicato in Player.gd rotation)
- R07-F03 (ActionMap abstraction)
- R08-F01 (CharacterBody3D scelta validata), R08-F02 (collision mask layout)
- R09-F05 (input buffering + coyote)
