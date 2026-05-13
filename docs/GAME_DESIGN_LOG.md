# GAME_DESIGN_LOG.md

Decisioni di game design per IssNostalgia Phase 2 — Game Mechanics (5v5).
Solo decisioni che divergono dal `PROMPT_CONTRACT_ISS_NOSTALGIA_PHASE2.md` o non
erano previste. Le decisioni di parametri fisici restano in `PHYSICS_LOG.md`.

Format: append-only. Riferimenti a finding di `RESEARCH_INDEX.md` come `RXX-FYY`.

## Workflow rules (post-Sprint 6)

1. **T00 obbligatorio** per ogni sprint: rileggi `RESEARCH_INDEX.md`,
   identifica finding `PRIORITY: HIGH` rilevanti, lista esplicita nel
   plan sotto "Research Findings Applied". Memory search Ruflo namespace
   `IssNostalgia/research` con termini chiave del scope; verifica
   coerenza con `RESEARCH_INDEX.md`, aggiorna se discrepanze.
2. **Post-commit ogni task Tn**: `memory_store IssNostalgia/gameplay`
   con chiave `sprintNN:Tn:decision-slug` per ogni decisione architetturale
   nuova. Verifica che `AgentDB.totalEntries` aumenti dopo store.
3. **T08 obbligatorio**: aggiorna `RESEARCH_INDEX.md` colonna "Used in
   Sprint" con stato VALIDATED / PARTIAL / DEFERRED; popola "Findings →
   Code Mapping" qui sotto con `RXX-FYY → file:func`.

---

## Sprint 06 — Discuss Phase (decisioni accettate, 2026-05-13)

| ID | Decisione | Rationale |
|----|-----------|-----------|
| S06-D01 | **Auto-switch hysteresis** = dead zone 0.5 m attorno alla soglia 8 m + minimum hold 3 physics frames (25 ms a 120 Hz) | Previene oscillazione quando due giocatori sono equidistanti dalla palla. Spec contract non ne parlava — gap colmato (R02 thin-area note). |
| S06-D02 | **Direzione tiro** = somma vettoriale `facing * 0.6 + WASD_input * 0.4` (NON override) | Override completo rende tiri imprevedibili soprattutto su mobile. La somma garantisce che il tiro segue sempre la direzione "naturale" del giocatore (R03-F03). |
| S06-D03 | **Possesso simultaneo** = nearest-by-`length_squared`, tie-breaker = umano > AI | Determinismo + evita race condition quando due giocatori entrano nel raggio nello stesso physics tick. |
| S06-D04 | **Stamina recovery gate** = ricarica solo se sprint NON premuto | Più realistico e leggibile, evita "free sprint" tenendo Shift premuto. (R01-F05 stamina patterns). |
| S06-D05 | **Spin automatico tiri** = topspin lieve (`+2 rad/s`) auto-applicato solo se `\|v\| > 20 m/s`. Sotto soglia: zero spin. | Spin sui tiri forti aumenta realismo arcade senza interferire con tiri di precisione bassi. |
| S06-D06 | **Aftertouch + kick_bias_impulse → Phase 3** | Conflict-flag con "BallPhysics sacred" (R09-F01, R09-F07). Phase 2 NON tocca PhysicsConfig — restano per Phase 3 review. |
| S06-D07 | **Static AI offset reattivo per ruolo**: difensori 6 m, centrocampista 4 m, attaccante 2 m | L'attaccante NON difende — resta avanzato come minaccia in contropiede. Spec dava range 5-8 senza dettaglio per ruolo. |
| S06-D08 | **Solo Team B (avversario) ha Static AI sui 4 outfield**. Compagni del Team A non controllati restano fermi in Phase 2. | Ridotta complessità Sprint 8. Compagni-AI futuri = Phase 3. |
| S06-D09 | **Isteresi 2 m sulla linea di metà campo** per il trigger della transizione formazione | Evita ping-pong della formazione su rimbalzi attorno a `z=0`. |
| S06-D10 | **Goalkeeper escluso dalla formula `anchor + ball_offset * influence_factor`** | GK ha logica completamente separata (X-only tracking + intervento reachability). `influence_factor=0.1` del contract NON applicato. |
| S06-D11 | **GK reachability formula** (R04-F01): teleport quando `d_eff / gk_speed > t_av` con `d_eff = max(0, d_lat - r)`, `t_av = max(0, t_f - t_r - t_buf)` | Sostituisce il "ball within 2 m AND on intercept trajectory" del contract — formula sport-science based, più rigorosa. |
| S06-D12 | **GK give-up gate** (R04-F06): GK non interviene se `abs(intercept_x) > 3.2 OR predicted_height > 2.44 m` | Aggiunto al contract (era missing). Evita teleport "omniscient" su tiri fisicamente impossibili da parare. |
| S06-D13 | **Carry mechanism** = `RigidBody3D.freeze_mode = FREEZE_MODE_KINEMATIC` + `set_deferred("freeze", true)` (R02-F02, R02-F06) | Più affidabile dell'early-return nel custom integrator. KINEMATIC permette `global_position` update per tick senza interferenze fisiche. Da Sprint 7. |
| S06-D14 | **Replay buffer durante carry** = continua a registrare la posizione del carry (statica relativa al player) | Non rompe il frame-step replay; quando si entra in possesso il replay mostra il carry path correttamente. |
| S06-D15 | **Goal validity** = front-only Area3D + check `ball.linear_velocity.dot(goal_forward_normal) > 0` al trigger | Risolve "goal dalla parte posteriore". 2 Area3D separate sarebbero scomode da gestire. |
| S06-D16 | **Halftime** = solo reset posizioni con stessi side. Nessuno swap fisico dei lati in Phase 2. | Swap visivo dei lati = Phase 3 (richiede animazione). |
| S06-D17 | **Out of bounds respawn** = bordo più vicino al punto di uscita, offset 0.5 m dentro il campo. Possesso → squadra che NON ha mandato fuori. | Approssimazione arcade della rimessa laterale. Phase 3 può aggiungere animazione di rimessa. |
| S06-D18 | **Camera centroid** = sempre 60% palla + 40% giocatore controllato (anche senza possesso) | Ball-centric anche su palle vaganti. Rimuove ambiguità del contract ("il giocatore controllato" durante possessi indecisi). |
| S06-D19 | **Camera zoom** = basato su distanza palla → porta in difesa (quella da proteggere), non porta avversaria | Più intuitivo: zoom in quando il pericolo è vicino. |
| S06-D20 | **Frame-rate-independent camera lerp** (R06-F06) adottato subito: `lerp(cam, tgt, 1.0 - pow(0.94, delta * 60))` invece di `lerp(cam, tgt, 0.06)` fisso | Stesso smoothing su Android 30/60 fps. One-line fix, nessuna ragione per rimandare. |
| S06-D21 | **Player vs GK** = stessa classe `Player.gd` con `is_goalkeeper: bool` flag. Refactor in `Goalkeeper.gd` solo se cresce di complessità in Sprint 8. | Riduce duplicazione iniziale, conserva opzione di estrazione futura. |
| S06-D22 | **Mesh placeholder** = `CapsuleMesh` con `material_override` colorato dal `TeamConfig.primary_color`. Default: Team A = `Color.BLUE`, Team B = `Color.RED`. | Massima leggibilità per debug visivo Sprint 6. Asset 3D veri → Phase 3. |
| S06-D23 | **TeamConfig.gd = solo dati** (color, name, formation_id). Calcoli di posizione vivono in `FormationData.gd` o `StaticAI.gd`. | Single Responsibility — Resource pura. |
| S06-D24 | **FormationData.gd parametrico**: `role_anchors: Array[Vector3]` + `role_factors: Array[float]` invece di hard-code 2-1-1 | Costo near-zero ora, evita refactor quando Phase 3 introduce 3-1-1 / 1-2-1 ecc. |
| S06-D25 | **ActionMap abstraction** introdotta da Sprint 6: `pass`, `shoot_charge`, `sprint`, `switch` come azioni nominate (Godot `InputMap`), keyboard binding ora, touch binding stub vuoto per Sprint 10 | Una riga ora evita refactor pesante in Sprint 10 (R07-F03). |
| S06-D26 | **Input buffering 100 ms + coyote 6 frames** adottati da Sprint 6 anche per keyboard | Diventa fondamentale su touch (R09-F05). Costruirlo subito = comportamento consistente cross-platform. |
| S06-D27 | **Animation warping** (mesh facing snap entro 1-2 physics tick, hitbox segue a sim speed) introdotto in Sprint 7 | Risolve "su rotaia" feel senza richiedere animazioni 3D vere (R09-F04). |
| S06-D28 | **Pass spin auto**: backspin `-3 rad/s` su grounder (`dist < 8 m`), topspin `+4 rad/s` su lob (`dist > 15 m`), zero in mezzo | Da R03-F05. Riusa `BallLauncher.compose_spin()`. |
| S06-D29 | **MatchManager.both_human: bool** flag debug (NON nel contract ufficiale) per testing locale 1v1 input keyboard / split-screen futuro | Utile per debug autoswitch e formation transition senza opponent AI. |
| S06-D30 | **Animazione tiro placeholder durata = 200 ms; passaggio = 100 ms**. Auto-switch bloccato durante questi intervalli. | Dura abbastanza per leggere il contesto, abbastanza poco da non frustrare. |
| S06-D31 | **Manual-override cooldown** = 240 physics frame (2.0 s @ 120 Hz) post-cycle, **auto-refreshing** finché (a) il player attivo si muove (`velocity² > 0.25`) OR (b) la palla non drifta più di 5 m dall'anchor catturato all'arm del cooldown. `step_autoswitch` muto per tutta la durata. | Senza cooldown il manual cycle perdeva sempre la guerra con autoswitch quando il giocatore manualmente scelto era lontano dalla palla (T05 visual playtest). Cooldown fisso 2s era ancora insufficiente: per MockBall ferma + giocatore parked, dopo 2s autoswitch revocava sempre. Auto-refresh con doppio criterio (player engaged OR ball static) preserva intent UX in tutti i casi rilevanti: build-up tattico (player parked, ball static) → override eterno; user attivo (move/charge/pass) → eterno; ball moves AND player parked → cooldown decrementa, autoswitch riprende dopo 2s. |
| S06-D32 | **Player auto-decel quando non drivato** — `Player._physics_process` controlla `_driven_this_tick` (settato da `apply_movement_step`) e, se falso, applica un drive zero-input come fallback. Decelera naturalmente in ~0.4 s da sprint a fermo (accel 20 m/s²). | T05 visual playtest: dopo Q-switch, il giocatore A continuava a muoversi indefinitamente perché nessuno chiamava più `apply_movement_step` su di lui (controller puntava a B). Senza fallback, `velocity` restava congelata e `move_and_slide` la propagava ogni tick. Il fallback fa sì che ogni Player non controllato (passaggio inattivo, NPC senza StaticAI, etc.) decelera naturalmente. Sprint 8 StaticAI driverà gli avversari → il fallback diventa irrilevante per loro, ma resta safety net per casi edge. |

---

### Linguaggio

- **HUD / log in-game** = inglese (allineato a commit messages e codice).
- **GAME_DESIGN_LOG.md** = italiano (come `PHYSICS_LOG.md`).
- **Commit messages** = inglese.

### Tracciamento applicazione findings R01-R09

Vedi colonna **"Used in Sprint"** in `RESEARCH_INDEX.md`. Aggiornata a fine sprint.

---

## Sprint 06 — Calibration Sessions

| Date       | Task   | Notes |
|------------|--------|-------|
| 2026-05-13 | T00    | Sprint 06 plan + GAME_DESIGN_LOG seed con 30 decisioni S06-D01..D30 dal discuss-phase. Branch `sprint/06-player-entity` creato off `main` post `v0.5.0-sprint05`. |
| 2026-05-13 | T01    | TeamConfig.gd + FormationData.gd typed Resources, preset 2-1-1 con anchors (DEF_LEFT -15,0,-35; DEF_RIGHT 15,0,-35; MID 0,0,-15; ATT 0,0,5; GK 0,0,-50) e role_offset_meters (6/6/4/2/0). team_a.tres blu human, team_b.tres rosso AI, mirror via get_anchor_mirrored (Z negato, X preservato). 8 GUT test → suite 38/38. |
| 2026-05-13 | T02    | Player.gd CharacterBody3D + state machine + stamina (drain 1/3 s/s, recovery 1/5 s/s, gated S06-D04) + rotation slerp FR-independent (R01-F04, R06-F06). Player.tscn capsule 0.4×1.8 + collision layer 2 mask 7 + BodyMesh + FrontMarker. material_override colorato da team in _ready. 10 GUT test → suite 48/48. |
| 2026-05-13 | T03    | InputMap p1_* (WASD + Shift + Q + Space + E) via physical_keycode. PlayerController con ActionMap abstraction (action_prefix), input buffer 100 ms (R09-F05), coyote 6 frames framework. is_shooting / is_passing flags pronti per Sprint 7 ball gate. 10 GUT test → suite 58/58. |
| 2026-05-13 | T04    | TeamController auto-switch + hysteresis (8m ± 0.5m dead zone, 3-frame hold S06-D01) + manual Q cycle skip GK + selection indicator runtime-instanced (CylinderMesh, alpha 0.85 active / 0.25 dim / hidden AI). 9 GUT test → suite 67/67. |
| 2026-05-13 | T05    | GameMatch.tscn: pitch 105×68 + 4 pali + MockBall yellow + Sun + camera broadcast + HUD label. GameMatch.gd spawn 10 player + 2 TeamController + 1 PlayerControllerA. Visual playtest: bug Q-switch — cycle funzionava ma autoswitch revocava entro 25 ms. **Hotfix S06-D31** cooldown 240 frame post-cycle. **Hotfix2 S06-D31 update** — auto-refresh while ball static OR active player moving (cooldown fisso ancora insufficiente con MockBall ferma). **Hotfix3 S06-D32** — Player auto-decel quando undriven (era ghost-inertia post-switch). 8 GUT test + 3 hotfix test → suite 79/79. |
| 2026-05-13 | T06    | both_human flag debug (S06-D29): spawn PlayerControllerB con prefix p2_, TeamControllerB.is_human=true. InputMap +13 actions (p2_*: Frecce/RShift/NumEnter/Num+/Num-; debug_ball_*: [/]/;/'/B). move_ball_relative + randomize_ball_position API pubbliche. HUD multilinea P1/P2 + FPS. HelpLabel scena con full keymap. 4 nuovi test → suite 83/83. |
| 2026-05-13 | T07    | Regression confirmed 83/83 PASS, 484 asserts, 3.2 s headless. Sprint 5→6 delta: +53 test, +192 asserts. Hardened test_game_match_setup contro stato del scene file (helper `_spawn_match(both_human)` rebuild-on-demand). FPS counter aggiunto al HUD. User confirm FPS ≥ 60 sustained con 10 player + Q + ball-move debug keys. |

---

## Sprint 07 — Discuss Phase (decisioni accettate, 2026-05-13)

| ID | Decisione | Rationale |
|----|-----------|-----------|
| S07-D01 | **BallPhysics state-toggle API** = `set_possessed(Player)` + `release(impulse, angular)` + `is_possessed()` + signal `released`. Internal: `freeze_mode = FREEZE_MODE_KINEMATIC` via `set_deferred("freeze", value)`. Mai modifica `PhysicsConfig`. | Pattern R02-F02 (KINEMATIC reliable) + R02-F06 (Godot 4 drag-drop recipe). PhysicsConfig sacred (S06-D06) — toggle è SOLO mode/freeze, non parametri. |
| S07-D02 | **BallController.gd** singleton di match (figlio GameMatch). Gestisce arbitrato globale palla: pickup, release, carry sync. Player NON sa di altri Player — solo BallController decide chi possiede. | Single source of truth previene race condition con 10 player. Tie-breaker human > AI (S06-D03) implementato qui. |
| S07-D03 | **Carry offset** = `player.basis * Vector3(0, -0.2, 0.5)` (player-local: 0.5 m forward, 0.2 m below capsule center). | Approx ai piedi del player. Da R02-F06 raccomandazione canonica. |
| S07-D04 | **Shoot direction** = `(facing * 0.6 + WASD_input * 0.4).normalized()` (riconferma S06-D02). Elevation = `lerp(8°, 12°, power_norm)` per arco visibile non lob. | Somma vettoriale evita override imprevedibile su mobile. Elevation contenuta = tiro, non lob. |
| S07-D05 | **Shot spin auto**: topspin `+2 rad/s` se `\|v\| > 20 m/s`, altrimenti zero (S06-D05 riconferma). | Spin marginale per tiri forti, zero per finezza. Soglia 20 = realistico arcade. |
| S07-D06 | **Pass spin auto**: backspin `-3 rad/s` se `distance < 8 m` (grounder), topspin `+4 rad/s` se `> 15 m` (lob), zero in mezzo (S06-D28 riconferma). Riusa `BallLauncher.compose_spin`. | Da R03-F05 / R03-F06. Soglie 8/15 m discriminano grounder vs lob. |
| S07-D07 | **Animation warping**: `VisualRoot` Node3D figlio Player con BodyMesh + FrontMarker; ruota istantaneamente (alpha 0.5/tick) verso `_facing_target`. CollisionShape resta a lerp slow esistente (rotation_speed 8). | Da R09-F04. Risolve "su rotaia" senza animazioni vere. Hitbox lento = no glitch fisici. |

### Sprint 07 — Findings → Code Mapping (T08 — VALIDATED)

| Finding | File:func / commit | Status |
|---------|--------------------|--------|
| R02-F02 KINEMATIC freeze pattern | `BallPhysics.set_possessed` + `set_deferred("freeze", true)` + `freeze_mode = FREEZE_MODE_KINEMATIC`; integrator early-returns on `_possessed_by != null` (commit @ T01) | VALIDATED |
| R02-F03 possession proximity 0.8 m + ball-approaching gate | `BallController._try_pickup`: `dx²+dz² ≤ 0.64` AND `|v|² ≤ 144`, GK excluded, post-release lockout 0.3 s (commit @ T02 + T05-fix2) | VALIDATED |
| R02-F06 Godot 4 drag/drop recipe (carry pos-copy + impulse on release) | `BallController._sync_carry_position` writes `ball.global_position = carrier_pos + visual_basis * carry_offset` directly (KINEMATIC accepts direct writes; staged-pending pipeline only fires when integrator runs). Release via `BallPhysics.release` → `apply_launch_state` deferred. (commit @ T02 + T05-fix1) | VALIDATED |
| R03-F01 input < 100 ms | shoot/pass roundtrip = 1 physics tick (8.3 ms) + deferred-freeze cycle ≤ 16 ms — within budget (re-validated @ T03) | VALIDATED |
| R03-F02 cubic t³ charge curve | `ShootingController.charge_curve_exponent = 3.0`; `power_norm = pow(t_norm, 3.0)`; `speed = lerp(15, 30, power_norm)` (commit @ T03) | VALIDATED |
| R03-F03 instant velocity on release | `ShootingController.fire_shot` → `BallController.request_release` → `BallPhysics.release` → `apply_launch_state` (1-tick deferred), no easing on release (commit @ T03) | VALIDATED |
| R03-F05 dot-product 90° cone for pass target | `PassingController.cone_dot_threshold = 0.707`; nearest in cone, GK excluded; spin auto by distance (backspin <8m, topspin >15m, zero between) (commit @ T04) | VALIDATED |
| R03-F06 reuse `BallLauncher.launch_to_point` + `compose_spin` | `BallLauncher.compute_velocity_to_point` extracted from `launch_to_point` for compute-only use; `PassingController.try_pass` uses solver + `compose_spin` for spin override (commit @ T04 + BallLauncher refactor) | VALIDATED |
| R09-F05 buffer + coyote (re-validate) | `PassingController` consumes `&"pass_ball"` via `consume_buffered`; `ShootingController` polls `Input.is_action_pressed` for hold-charge (commit @ T03 / T04) | VALIDATED |
| R09-F04 FIFA Animation Warping | `Player.start_facing_warp(dir, 0.15)` + `rotation_speed_warp = 50` boost window. Used by `BallController._assign_carrier` (on-pickup safety net) AND by `PassingController.try_pass` (receiver pre-orientation @ pass-fire). 99% facing convergence in ~110ms. (commit @ T05-fix5 + fix6) | VALIDATED |
| R01-F07 FIFA HyperMotion visual/physics decoupling | `Player.tscn` adds `VisualRoot: Node3D` between CharacterBody3D and meshes; rotation lives on VisualRoot, collision capsule basis stays at identity. `Player.get_visual_basis()` / `get_visual_forward()` are canonical accessors. All ball-interaction code migrated. (commit @ T06) | VALIDATED |

### Sprint 07 — Calibration Sessions

| Date       | Task   | Notes |
|------------|--------|-------|
| 2026-05-13 | T05-fix1 | Carry sync no-op bug — `teleport_to` stages `_pending_teleport` for `_integrate_forces`, but KINEMATIC-frozen RigidBody3D doesn't run the integrator. Switched carry sync to direct `ball.global_position` write. |
| 2026-05-13 | T05-fix2 | Post-release pickup lockout 0.3 s — without it the same physics tick that fires `release()` re-runs `_try_pickup`, ball still at carry offset (within 0.8 m radius), instant re-grab wipes launch velocity. |
| 2026-05-13 | T05-fix2 | Player snap-direction tuning — `accel` 20 → 50 m/s² fixes "ventaglio" (~0.4 s velocity reversal traced visible arc). `rotation_speed` 8 → 20 (~160 ms to 99 % facing). |
| 2026-05-13 | T05-fix4-6 | Reception facing — first try `set_facing_immediate` (snap) read as scatto. Replaced with `start_facing_warp` per R09-F04 (warp 50 rad/s, ~110 ms). Then moved warp from on-pickup to **at-pass-fire** time on the targeted teammate (`receiver_prewarp_duration_s = 0.30`) for real-football realism. |
| 2026-05-13 | T05-fix7 | Pass active-switch glitch — `TeamController._manual_override_remaining` (240 tick = 2 s) blocked autoswitch to receiver. `PassingController` now explicitly calls `team_controller.set_active(target_idx)` when the pass-anim window expires. Deterministic, no race with override. |
| 2026-05-13 | T06   | VisualRoot decoupling validated against tests 1-5 (snap-on-direction-change, no jitter circular walk, carry-during-turn, front-marker readability, shoot/pass direction correct). Test 6 (post-pass receiver orientation) covered by fix5/fix6 warp. |

---

## Sprint 08 — Discuss Phase (decisioni accettate, 2026-05-13)

| ID | Decision | Rationale |
|----|----------|-----------|
| S08-D01 | **Sprint 8 title** = "Close Control + Static AI" (non solo "Static AI" come da Phase 2 contract originario). Close Control entra come T01-T03 prima dello Static AI. | User direction post-Sprint 7 playtest. Close-control è feature critica per "feel" arcade, merita slot esplicito prima dello StaticAI che dipende da palla viva. |
| S08-D02 | **Touch-cycle release kind**: `BallController.request_release(velocity, angular, kind: ReleaseKind)`. `ReleaseKind ∈ {SHOOT, PASS, TOUCH}`. Solo SHOOT/PASS armano il `_pickup_lockout_remaining_s = 0.3`. TOUCH → no lockout. | Sprint 7 lockout 0.3 s impedirebbe il touch-cycle interval (0.4 s sprint < 0.3 s lockout). Distinzione kind preserva anti re-grab per shoot/pass mantenendo il dribble vivo. |
| S08-D03 | **Receiver pre-orientation warp** (Sprint 7 fix6) **NON si attiva** su `kind == TOUCH`. Solo SHOOT/PASS. | Touch è continuo — un warp a ogni intervallo sarebbe rumore. Pre-warp resta solo per pass intenzionali. |
| S08-D04 | **Carry offset**: `lerp(0.3, 0.5, player_speed/max_walk_speed)` modulato runtime invece del fisso 0.5 m attuale. Y stays -0.7 (ankle), Z front (negativo per Godot -Z forward). | Da R02-F04 EA Pitch Notes — elite players keep ball closer at walk, push further at sprint. |
| S08-D05 | **Ball speed coupling during sprint**: `ball.linear_velocity = carrier.velocity * touch_speed_ratio` (default 0.95). | Da R02-F04 — elite retain 88-95 % player speed; MVP fisso 0.95, Sprint 9+ legato a TeamConfig.dribble_skill. |
| S08-D06 | **Loss threshold** = 1.6 m base (= 2 × pickup radius) per R02-F05. Player.tight_control bool flag raises a 2.0 m (R02-F07 future "Tight Control" skill). MVP flag default false. | Architecture C (proximity + position-copy) requires explicit loss boundary. 1.6 m sopra pickup radius lascia margine recovery. |
| S08-D07 | **Static AI tactical update** = 2 Hz (ogni 0.5 s), NOT per-tick. Position lerp `alpha = dt / 1.5`. Max reposition speed 6-10 m/s per ruolo. | Da R05-F01 / R05-F04 — influence maps non per-frame, mobile CPU friendly. Lerp + speed cap evita scatti visibili. |
| S08-D08 | **Static AI target formula** = `anchor + (ball - anchor) * role_factor` con `role_factor` = {GK: 0.1, DEF: 0.3, MID: 0.5, ATT: 0.7}. | Da R05-F02 / R05-F05 — Voronoi statico = formation anchors, gradient role-differentiated empiricamente validato. |
| S08-D09 | **GK reactive save**: teleport-on-trajectory cheat (R04-F02 motivato — umani veri si pre-committano 100-250 ms prima del contatto). Give-up gate: `\|intercept_x\| > 3.2` OR `predicted_height > 2.44`. | Da R04-F01 + R04-F06 — pattern arcade leggero con give-up gate evita "GK robotico onnipotente". |
| S08-D10 | **GK reaction delay** (R04-F03 elite 193 ± 67 ms) **deferred a Phase 3**. Phase 2 GK keeps no-delay teleport. | Cheat è intenzionale Sprint 8. Reaction delay è polish (Phase 3 active opponent AI). |
| S08-D11 | **NBA Jam catch-up boost** (R09-F02): schema esposto in T06 (`@export` flags + hooks su Goalkeeper.get_effective_reaction_time). Runtime gate ritorna sempre false in Sprint 8 — applicazione in Sprint 9 quando esiste scoreboard. | Schema-only ora evita refactor in Sprint 9. Hooks pronti, attivazione 1 riga. |

### Sprint 08 — Findings → Code Mapping (popolato a fine sprint, T08)

| Finding | File:func / commit | Status |
|---------|--------------------|--------|
| R02-F04 speed-modulated carry offset | _TBD T01_ | _PENDING_ |
| R02-F05 touch-cycle (Architecture C, 1.6 m loss) | _TBD T02_ | _PENDING_ |
| R02-F07 magnetic feel + dribble_skill + tight_control | _TBD T03_ | _PENDING_ |
| R05-F01..F06 Static AI 2 Hz tactical, anchor + ball-attraction | _TBD T04_ | _PENDING_ |
| R04-F01/F02/F04/F05/F06 GK reactive save + give-up gate | _TBD T05_ | _PENDING_ |
| R04-F03 reaction delay | DEFERRED → Phase 3 | DEFERRED |
| R09-F02 NBA Jam catch-up boost (schema-only) | _TBD T06_ | _PENDING_ |

### Sprint 08 — Calibration Sessions

| Date       | Task   | Notes |
|------------|--------|-------|
