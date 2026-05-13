# GAME_DESIGN_LOG.md

Decisioni di game design per IssNostalgia Phase 2 — Game Mechanics (5v5).
Solo decisioni che divergono dal `PROMPT_CONTRACT_ISS_NOSTALGIA_PHASE2.md` o non
erano previste. Le decisioni di parametri fisici restano in `PHYSICS_LOG.md`.

Format: append-only. Riferimenti a finding di `RESEARCH_INDEX.md` come `RXX-FYY`.

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
| S06-D31 | **Manual-override cooldown** = 240 physics frame (2.0 s @ 120 Hz) post-cycle. `step_autoswitch` muto per tutta la durata. | Senza cooldown il manual cycle perde sempre la guerra contro l'auto-switch quando il giocatore manualmente scelto è lontano dalla palla (caso più comune). 2 s = abbastanza per agire sul giocatore selezionato, abbastanza breve per non sembrare bloccato. Aggiunto dopo T05 visual playtest dove Q non aveva effetto visibile. |

---

### Linguaggio

- **HUD / log in-game** = inglese (allineato a commit messages e codice).
- **GAME_DESIGN_LOG.md** = italiano (come `PHYSICS_LOG.md`).
- **Commit messages** = inglese.

### Tracciamento applicazione findings R01-R09

Vedi colonna **"Used in Sprint"** in `RESEARCH_INDEX.md`. Aggiornata a fine sprint.

---

## Sprint 06 — Calibration Sessions

(Compilato durante l'esecuzione delle task.)

| Date | Task | Notes |
|------|------|-------|
| | | |
