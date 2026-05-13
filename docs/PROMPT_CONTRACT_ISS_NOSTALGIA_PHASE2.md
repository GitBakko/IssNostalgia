# PROMPT_CONTRACT_ISS_NOSTALGIA_PHASE2.md
## Progetto: IssNostalgia — Mobile Football Game
## Fase 2: Game Mechanics — 5v5, Hybrid Control, Static Formations

---

## 🎯 Missione

Phase 1 ha costruito e validato la fisica della palla (Magnus, Cross-2002, knuckleball, drag crisis, per-zone surfaces). È demo-ready, taggata `v0.5.0-sprint05`, con 27/27 GUT PASS.

Phase 2 trasforma il physics sandbox in un **gioco giocabile 5v5**. L'obiettivo è avere una partita completa funzionante — con giocatori, possesso palla, passaggi, tiri, goal, punteggio — prima di affrontare Sprint 6 (Android export).

**La fisica della palla è sacra e non si tocca senza ragione documentata.** Tutti i parametri locked in `PHYSICS_LOG.md` rimangono invariati.

---

## 🧠 Principi Guida

> "Il gioco deve essere divertente da subito, non perfetto. Aggiungi complessità solo dove aggiunge divertimento."

> "Static AI non significa stupido — significa prevedibile e leggibile. Il giocatore deve capire dove andranno i difensori."

> "Ibrido = auto-switch fluido + controllo manuale preciso. Mai strappare il controllo al giocatore in un momento critico."

---

## 🛠️ Stack Tecnico

Invariato da Phase 1:
- **Engine:** Godot 4.6.2 .NET mono
- **Language:** GDScript (C# solo se bottleneck dimostrato da profiler)
- **Renderer:** Compatibility (GLES3)
- **Physics palla:** `BallPhysics.gd` — custom integrator, immutabile
- **Config fisica:** `PhysicsConfig.tres` — preset ISS_Feeling, immutabile

---

## 👥 Specifiche Gameplay

### Formazione: 5v5
- **5 giocatori per squadra** (10 totali in campo)
- Formazione default: **2-1-1** (2 difensori + 1 centrocampista + 1 attaccante — il portiere è separato e non conta nella formazione)
- Portiere: comportamento separato (si muove solo sull'asse X della porta)
- Giocatori di movimento: 4 outfield per squadra

### Controllo Ibrido
- **Auto-switch:** il controllo passa automaticamente al giocatore più vicino alla palla quando il giocatore attivo supera una soglia di distanza (default: 8m)
- **Manual override:** tasto dedicato (default: `Q`) per ciclare manualmente tra i giocatori della propria squadra
- **Indicatore visivo:** anello/cerchio sotto il giocatore controllato (colore primario squadra), più sottile sotto gli altri giocatori
- **Regola anti-frustrazione:** l'auto-switch NON avviene durante un'animazione di tiro o passaggio in corso

### Static AI (squadra avversaria)
- I giocatori avversari NON si muovono autonomamente in Phase 2
- Occupano posizioni di formazione fisse, calcolate in base alla posizione della palla
- **Offset reattivo:** quando la palla entra nella metà campo avversaria, i difensori avanzano di 5-8m (e viceversa) — si muovono in modo rigido ma contestuale
- Portiere avversario: tracking orizzontale della palla (segue X della palla entro i pali)
- Lo scopo è creare **ostacoli leggibili** per il giocatore umano, non una vera IA

---

## 🏗️ Architettura

```
IssNostalgia/
├── scenes/
│   ├── PhysicsSandbox.tscn       # Phase 1 — invariato
│   ├── GameMatch.tscn            # NEW — scena principale Phase 2
│   ├── Player.tscn               # NEW — singolo giocatore
│   ├── Team.tscn                 # NEW — nodo squadra (5 Player + gestione)
│   └── GoalDetector.tscn         # NEW — Area3D trigger porta
├── scripts/
│   ├── BallPhysics.gd            # Phase 1 — IMMUTABILE
│   ├── BallLauncher.gd           # Phase 1 — riusato per tiri/passaggi
│   ├── Player.gd                 # NEW — movimento, stati, animazione
│   ├── PlayerController.gd       # NEW — input umano → player attivo
│   ├── TeamController.gd         # NEW — gestione squadra, selezione, auto-switch
│   ├── StaticAI.gd               # NEW — posizionamento statico avversari
│   ├── MatchManager.gd           # NEW — game state machine
│   ├── MatchHUD.gd               # NEW — score, timer, indicatori
│   └── CameraController.gd       # NEW — camera che segue il gioco
├── resources/
│   ├── PhysicsConfig.tres        # Phase 1 — IMMUTABILE
│   ├── TeamConfig.gd             # NEW — colori, nome, formazione
│   └── FormationData.gd          # NEW — posizioni relative formazione
└── docs/
    ├── PHYSICS_LOG.md            # Phase 1 — solo append, no modifica
    ├── GAME_DESIGN_LOG.md        # NEW — decisioni di game design
    └── SPRINT_0X_PLAN.md         # per ogni sprint
```

---

## 🎮 Player — Specifiche

### Stati del giocatore (State Machine)
```
IDLE → RUNNING → NEAR_BALL → POSSESSO → TIRO/PASSAGGIO → IDLE
                                      ↓
                               TACKLE (futuro Phase 3)
```

### Movimento
- `CharacterBody3D` con `move_and_slide()`
- Velocità: **5.5 m/s** (walking) / **8.0 m/s** (sprint)
- Accelerazione: **20 m/s²** (responsivo, arcade)
- Input: WASD (giocatore umano) — touch deferred Sprint 6
- Rotazione: il giocatore ruota verso la direzione di movimento (lerp, non istantanea)
- Sprint: tasto `Shift` — consuma stamina (semplificato: 3s di sprint, recupero 5s)

### Possesso palla
- Il giocatore entra in possesso se: distanza dalla palla < `possession_radius` (default: 0.8m) E velocità relativa palla < 12 m/s
- In possesso: la palla segue il giocatore a `ball_carry_offset` (0.5m davanti ai piedi)
- La fisica custom della palla è **disattivata** durante il carry (BallPhysics in pausa, posizione forzata)
- Uscita possesso: tiro, passaggio, tackle subito, o la palla viene strappata da avversario entro 0.3m

### Tiro
- Richiede possesso
- Tasto: `Spacebar`
- Potenza: carica con hold (0.3s min → 1.5s max = full power)
- Direzione: direzione attuale del giocatore + analog input (WASD durante il caricamento)
- Al rilascio: la fisica BallPhysics viene riattivata con vettore velocità calcolato da potenza + direzione + spin automatico (topspin lieve per tiri forti)
- Animazione placeholder: piccolo tween di scala sul giocatore mesh

### Passaggio
- Richiede possesso
- Tasto: `E`
- Target: il compagno di squadra più vicino nella direzione del movimento (cono 90°)
- Se nessun compagno nel cono: passa nella direzione del movimento
- Potenza automatica: calcolata sulla distanza del target (non caricata manualmente)
- Spin: leggerissimo backspin per passaggi a terra, topspin per lanci in profondità (distanza > 15m)

---

## 🤖 Static AI — Specifiche

### Posizionamento base
```gdscript
# Per ogni giocatore avversario:
# target_position = formation_anchor + ball_influence_offset

var ball_influence_offset = (ball_position - center_field) * influence_factor[role]
# influence_factor: portiere=0.1, difensore=0.3, centrocampista=0.5, attaccante=0.7
```

### Portiere avversario
- Si muove solo sull'asse X (larghezza porta)
- Target X = clamp(ball.position.x, -3.2, 3.2) — rimane tra i pali
- Speed: 6.0 m/s, lerp factor 0.15 (risposta lenta, leggibile)
- Intervento: se palla entro 2m e in traiettoria → teleporta alla posizione di intercetto (cheat visibile — Phase 3 lo migliorerà)

### Transizione formazione
- Quando palla cambia metà campo: tutti i giocatori avversari si muovono verso nuove posizioni
- Durata transizione: **1.5 secondi** (lerp fluido, non teleport)
- Questo crea il feedback visivo "la difesa si sistema"

---

## ⚙️ MatchManager — Game State Machine

```
PREGAME → KICKOFF → PLAYING → GOAL_SCORED → KICKOFF → ... → HALFTIME → ... → FULLTIME
```

| Stato | Descrizione |
|-------|-------------|
| `PREGAME` | Setup squadre, formazioni, inizializzazione |
| `KICKOFF` | Palla al centro, 3s di countdown, giocatori in posizione |
| `PLAYING` | Gioco attivo |
| `GOAL_SCORED` | 2s di pausa, aggiorna score, ricomincia da kickoff |
| `OUT_OF_BOUNDS` | Palla fuori → rimessa laterale (semplificata: respawn sul bordo) |
| `HALFTIME` | Pausa 3s, scambio di campo, reset posizioni |
| `FULLTIME` | Schermata risultato finale |

### Durata partita
- Default: **4 minuti** (2 tempi da 2 minuti)
- Configurabile in `MatchManager` come `@export`

### Goal
- `GoalDetector` = Area3D dentro la porta (dentro i pali, sotto la traversa)
- Trigger su `body_entered` dalla palla → `MatchManager.on_goal_scored(team)`
- Goal non valido se: palla entra dalla parte posteriore della rete

---

## 📷 CameraController — Specifiche

### Comportamento
- Segue il **baricentro dinamico** tra palla e giocatore controllato (peso 60% palla, 40% giocatore)
- Bounds: camera non esce mai dai limiti del campo + 5m di margine
- Lerp factor: 0.06 (fluido, non rigido)
- Altezza e angolo: invariati da Phase 1 (0, 20, 40) → look_at origin offsettata

### Zoom
- Distanza varia in base alla distanza palla-portiere (se palla vicina a porta → zoom in lieve)
- Range: Z tra 30 e 50 (nessuno zoom estremo)

---

## 🖥️ MatchHUD — Specifiche

Overlay sempre visibile (non togglabile durante la partita):

```
┌─────────────────────────────────────────┐
│  TEAM A  2 — 1  TEAM B    [02:34]       │
│  ▪ Marco (stamina: ████░░)              │
└─────────────────────────────────────────┘
```

- Score centrato in alto
- Timer in alto a destra (countdown)
- Nome + barra stamina del giocatore attivo in basso a sinistra
- Indicatore "GOAL!" animato a centro schermo (2s)
- Indicatore "HALF TIME" / "FULL TIME" con risultato

---

## 🧪 GUT Test Suite Phase 2

Per ogni sprint, aggiungere test per:
- `test_possession_acquired` — giocatore entra in range → acquista possesso
- `test_possession_lost_on_shot` — tiro → palla esce dal carry, BallPhysics riattivata
- `test_autoswitch_triggers` — giocatore attivo a >8m dalla palla → switch avviene
- `test_autoswitch_blocked_during_shot` — autoswitch non avviene durante animazione tiro
- `test_goal_detector_front` — palla entra dalla parte frontale → goal valido
- `test_goal_detector_back` — palla entra dalla parte posteriore → goal non valido
- `test_static_ai_formation_offset` — palla in metà campo A → difensori B si avvicinano
- `test_match_state_kickoff_to_playing` — transizione di stato corretta

Target cumulativo Phase 2: **40+ GUT PASS**

---

## 🔬 Phase 0 — Knowledge Base Research (PREREQUISITO)

**Phase 0 va eseguita PRIMA di qualsiasi sprint di implementazione.**
Non produce codice. Produce una knowledge base strutturata, indicizzata e vettorizzata in Ruflo AgentDB, che gli sprint successivi recuperano automaticamente.

### Obiettivo

Raccogliere best practices, formule già tarate, trucchi e soluzioni consolidate per le casistiche tipiche dello sviluppo di un gioco di calcio — così da non perdere tempo a riscoprire soluzioni già note durante l'implementazione.

### Mandato di Ricerca

**Modello:** Sonnet 4.6 (non Opus — la ricerca è intensiva in tool calls, Sonnet è più efficiente)
**Metodo:** Web search + fetch paper/articoli tecnici + GDC talks
**Output:** NON solo sintesi testuale — ogni finding strutturato per indicizzazione vettoriale

### Topic da Investigare (obbligatori)

#### R01 — Player Movement in Football Games
- Acceleration/deceleration curves usate in FIFA/PES/Rocket League
- "Responsiveness vs realism" threshold: quanto immediato deve essere l'input su mobile
- Foot-planting e rotation smoothing: come evitare il giocatore "su rotaia"
- Fonti target: GDC talks, devblogs Psyonix, EA Sports technical papers

#### R02 — Ball Possession & Control System
- Proximity-based vs physics-based possession: quale approccio usano i top games
- "Magnetic ball" trick: come FIFA gestisce l'attrazione della palla al piede
- Carry offset animation: foot IK vs fixed offset
- Dribbling feel: velocità palla durante carry in relazione alla velocità del giocatore
- Fonti target: GDC 2018 FIFA, Rocket League blog, StackExchange gamedev

#### R03 — Shooting & Passing Feel
- Power charge curve: lineare vs quadratica vs ease-in-out
- Directional deviation on shot: come aggiungere errore umano realistico
- Auto-aim / aim assist su mobile: soglie e metodi standard
- Passing arc automatico in funzione della distanza
- Fonti target: GDC, devblogs, paper sports game design

#### R04 — Goalkeeper Behavior Patterns
- Diving range e timing: come calcolare l'intercetto ottimale
- "Cheat" patterns usati in giochi arcade (teleport, prediction lookahead)
- Goalkeeper idle positioning vs ball position
- Fonti target: AI Game Programming Wisdom, GDC AI summit

#### R05 — Static / Reactive Formation AI
- Influence maps per posizionamento difensivo
- "Magnetic zones": come i giocatori CPU si distribuiscono sul campo
- Voronoi-based positioning
- Transition fluency: come evitare sliding noticeable durante reposition
- Fonti target: AI Game Programming Wisdom vol.2-3, paper su tactical AI calcio

#### R06 — Camera Systems per Football
- Spring-arm camera con baricentro dinamico: formule e coefficienti tipici
- "Dead zone" camera: area in cui la camera non si muove (riduce motion sickness su mobile)
- Zoom in/out su azione: trigger e curve tipiche
- Fonti target: GDC camera talks, devblog Unity/Godot sport games

#### R07 — Input & Controls per Mobile Sports
- Virtual joystick: dead zone, sensitivity curve, placement ergonomico
- Tap-to-pass vs hold-to-shoot: pattern UX consolidati
- Haptic feedback timing per tiri e rimbalzi
- Fonti target: GDC mobile, Apple HIG, Google Material Design per games

#### R08 — Performance & Optimization per 10 Entities
- CharacterBody3D vs RigidBody3D per 10 giocatori: confronto performance
- LOD e culling per mobile con Compatibility renderer
- Physics layers: collision mask ottimale per giocatori + palla + trigger
- Fonti target: Godot docs, GodotCon talks, profiling reports

#### R09 — Tricks & Shortcuts da Games Industry
- "Smoke and mirrors" usati nei football games per sembrare più realistici
- GDC 2018 Psyonix: "It's Physics, but not as we know it" (Rocket League)
- Tecniche di "game feel" applicate a sport games (cit. Game Feel, Swink 2009)
- Fonti target: GDC vault, Gamasutra/Game Developer

### Formato Output per ogni Finding

```
TOPIC: R0X — [nome topic]
SOURCE: [URL o riferimento citabile]
FINDING: [sintesi concisa, max 3 righe]
APPLICABILITY: [come si applica a IssNostalgia — specifico]
PARAMETERS: [valori numerici, formule, soglie — se presenti]
PRIORITY: HIGH / MEDIUM / LOW
```

### Storage in Ruflo AgentDB

**Namespace:** `IssNostalgia/research`

Per ogni finding, usare il MCP tool di Ruflo per:
1. Fare `memory_store` nel namespace `IssNostalgia/research`
2. Vettorizzare il contenuto nell'AgentDB (verificare che `AgentDB Vectors` aumenti nel dashboard)
3. Usare chiavi strutturate: `research:R01:finding-01`, `research:R02:finding-01`, ecc.

**Index file:** al termine di Phase 0, creare `docs/RESEARCH_INDEX.md` con:
- Tabella di tutti i finding per topic
- Link ai source verificati
- Colonna "Used in Sprint" (compilata durante Phase 2)

### Verifica Completamento Phase 0

- [ ] Tutti i topic R01-R09 investigati con almeno 3 finding ciascuno
- [ ] `AgentDB Vectors > 0` confermato nel dashboard Ruflo
- [ ] `docs/RESEARCH_INDEX.md` creato e popolato
- [ ] Almeno 1 finding per topic classificato PRIORITY: HIGH
- [ ] Ruflo memory search test: query `"possession magnetic ball"` → restituisce risultati pertinenti

**Solo dopo aver completato Phase 0, inizia Sprint 6.**

---

## 📋 Sprint Plan Phase 2

### Sprint 6 — Player Entity & Control
- `Player.tscn` + `Player.gd` (state machine, movimento, mesh placeholder)
- `PlayerController.gd` (input WASD, sprint, selezione manuale Q)
- `TeamController.gd` (auto-switch logica)
- Due squadre di 5 in campo, giocatore umano controlla squadra A
- Nessuna palla ancora — verifica solo movimento e selezione
- GUT: possesso, auto-switch, blocco durante tiro

### Sprint 7 — Ball Interaction & Shooting
- Sistema possesso palla (pickup, carry, rilascio)
- Tiro (Spacebar con carica)
- Passaggio (E verso compagno)
- Integrazione con BallPhysics (attiva/disattiva durante carry)
- GUT: tutti i test ball interaction

### Sprint 8 — Static AI & MatchManager
- `StaticAI.gd` — posizionamento formazione + offset reattivo
- Portiere avversario tracking + intervento cheat
- `MatchManager.gd` — state machine completa
- Kickoff, goal detection, halftime, fulltime
- GUT: stati partita, goal detector

### Sprint 9 — HUD, Camera, Polish
- `MatchHUD.gd` — score, timer, stamina, indicatori
- `CameraController.gd` — baricentro dinamico + bounds + zoom
- Placeholder audio (goal sound, kickoff whistle)
- Calibrazione finale feel: velocità giocatori, auto-switch threshold, stamina
- GUT regression completa (target 40+)
- Tag `v0.9.0-phase2-complete`

---

## 🚫 Out of Scope Phase 2

- **Touch controls / Android** → Sprint 10 (ex Sprint 6)
- **Tackle e contrasto fisico** → Phase 3
- **Falli e cartellini** → Phase 3
- **Calci piazzati (punizioni, corner, rigori)** → Phase 3
- **IA avversaria con movimento autonomo** → Phase 3
- **Animazioni 3D vere** → Phase 3 (mesh placeholder in Phase 2)
- **Selezione squadre / menu principale** → Phase 3
- **Salvataggio progressi / statistiche** → Phase 3
- **Rete porta visiva** → Phase 3

---

## 🔁 Modalità di Lavoro

- Checkpoint task-by-task per Sprint 6 (primo sprint Phase 2 = stabilisce convenzioni)
- Auto mode per Sprint 7-9 salvo calibrazioni soggettive
- `GAME_DESIGN_LOG.md` aggiornato a ogni sprint con decisioni di gameplay
- Parametri fisici in `PhysicsConfig.tres` **non si toccano** — se il gameplay richiede aggiustamenti fisici, si discute prima e si documenta in `GAME_DESIGN_LOG.md`
- Ogni sprint chiude con PR + merge + tag

---

## 🌊 Contesto Ruflo

- Memory namespace aggiuntivo: `IssNostalgia/gameplay`
- Memorizzare: soglie di auto-switch validate, parametri StaticAI locked, formation data confirmed
- Recupero inizio sessione: `ruflo memory search "IssNostalgia"` (sia /physics che /gameplay)

---

*Prompt Contract generato per IssNostalgia — Fase 2: Game Mechanics*
*Modello target: Claude Opus 4.6 (claude-opus-4-6)*
*Prerequisito: Phase 1 completa, v0.5.0-sprint05, 27/27 GUT PASS*
*Data: Maggio 2026*
