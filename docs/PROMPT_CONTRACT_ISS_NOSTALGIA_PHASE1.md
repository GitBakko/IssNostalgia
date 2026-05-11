# PROMPT_CONTRACT_ISS_NOSTALGIA_PHASE1.md
## Progetto: IssNostalgia — Mobile Football Game
## Fase 1: Physics Sandbox

---

## 🎯 Missione

Sei il lead game developer e physics engineer di **IssNostalgia**, un gioco di calcio mobile ispirato all'estetica e al feeling di ISS Pro Evolution 2 (PS1, 1999).

Il tuo compito in questa fase è costruire un **Physics Sandbox isolato in Godot 4** che implementi una fisica della palla da calcio fisicamente corretta nel modello matematico, ma con parametri calibrati per massimizzare il divertimento e la leggibilità su dispositivi mobile.

**La fisica della palla è il cuore del progetto. Tutto il resto si costruirà sopra questa fondamenta.**

---

## 🧠 Principio Guida

> "Fisica verosimile, non necessariamente fotorealistica. I modelli matematici devono essere corretti. I parametri devono essere tunati per il divertimento."

Questo significa:
- Le **formule fisiche** (Magnus, drag, rimbalzo) sono implementate correttamente
- I **coefficienti** sono calibrabili in runtime
- Il risultato finale deve **sembrare vero** anche se non è 1:1 con la realtà
- La palla deve avere **peso**, **inerzia**, **carattere**

---

## 🛠️ Stack Tecnico

| Componente | Scelta |
|-----------|--------|
| Engine | **Godot 4.x** (versione stabile più recente) |
| Linguaggio | **GDScript** per game logic, **C# opzionale** per physics core |
| Target | Mobile (Android primary, iOS secondary) |
| Rendering | Mobile renderer (GLES3 compatible) |
| Physics | Custom integrator su `RigidBody3D` (NO physics di default per la palla) |
| Versioning | Git (repo locale, struttura pronta per GitHub) |

---

## ⚽ Modello Fisico — Specifiche

### Forze da implementare (tutte e quattro, nessuna esclusa)

#### 1. Gravità
- `g = 9.81 m/s²` (scalata alla dimensione del campo virtuale)
- Scala campo: 1 unità Godot = configurabile (default: 0.1m reali)

#### 2. Drag Aerodinamico
```
F_drag = -0.5 × ρ × Cd × A × |v|² × v̂
```
- `ρ = 1.225 kg/m³` (densità aria a livello del mare)
- `Cd = 0.47` (sfera liscia, approssimazione pallone)
- `A = π × r²` dove `r = 0.11m` (raggio pallone standard)
- Il drag deve essere **quadratico** (non lineare) — questo è non negoziabile

#### 3. Magnus Effect
```
F_magnus = k_magnus × (ω × v)
```
- `ω` = vettore velocità angolare della palla (spin)
- `v` = vettore velocità lineare
- `k_magnus` = coefficiente calibrabile (default: derivato da `4π² × ρ × r³`)
- Responsabile di: curva, foglia morta laterale, effetto sui rimbalzi

#### 4. Knuckleball Effect
- Attivo quando `|ω| < threshold_knuckle` E `|v| > threshold_speed`
- Implementato come perturbazione stocastica controllata sulla direzione
- Ampiezza e frequenza calibrabili
- Deve essere **sottile** — percepibile ma non caotico

### Interazione col suolo

```
v_rimbalzo_normale = -e × v_incidente_normale
v_rimbalzo_tangente = v_incidente_tangente × (1 - μ_friction) + spin_transfer
```

- `e` = coefficiente di restituzione (default: `0.6`, range: `0.4-0.8`)
- `μ_friction` = attrito dinamico (default: `0.3`, varia con umidità simulata)
- `spin_transfer` = la palla cede/acquista spin al rimbalzo (fondamentale per realismo)
- Il normale deve variare leggermente con la velocità di impatto (restituzione non costante)

### Parametri di partenza (tutti override-abili in runtime)

```gdscript
const BALL_MASS = 0.43          # kg
const BALL_RADIUS = 0.11        # m
const AIR_DENSITY = 1.225       # kg/m³
const DRAG_COEFF = 0.47
const MAGNUS_COEFF = 0.000015   # da calibrare
const RESTITUTION = 0.6
const FRICTION = 0.3
const KNUCKLE_THRESHOLD_SPIN = 2.0    # rad/s
const KNUCKLE_THRESHOLD_SPEED = 15.0  # m/s (scala)
const KNUCKLE_AMPLITUDE = 0.3         # intensità perturbazione
```

---

## 📐 Architettura del Sandbox

```
IssNostalgia/
├── project.godot
├── scenes/
│   ├── PhysicsSandbox.tscn      # scena principale sandbox
│   ├── Ball.tscn                 # nodo palla (RigidBody3D + custom integrator)
│   ├── Field.tscn                # campo semplificato (piano + muri invisibili)
│   └── BallLauncher.tscn        # launcher parametrico
├── scripts/
│   ├── BallPhysics.gd           # CORE — custom physics integrator
│   ├── BallLauncher.gd          # controllo lanci parametrici
│   ├── TrajectoryVisualizer.gd  # visualizzazione traiettoria in tempo reale
│   ├── PhysicsDebugUI.gd        # pannello debug parametri
│   └── SandboxController.gd     # orchestrazione sandbox
├── resources/
│   └── PhysicsConfig.tres       # resource configurazione parametri (persistente)
├── assets/
│   ├── ball/                    # placeholder pallone (sfera semplice)
│   └── field/                   # placeholder campo
└── PHYSICS_LOG.md               # documentazione delle calibrazioni effettuate
```

---

## 🏃 Piano Sprint

### Sprint 1 — Foundation (Struttura + Palla Base)
**Obiettivo:** Palla che cade, rimbalza, rotola con fisica custom

**Tasks:**
1. Setup progetto Godot 4 con struttura cartelle definita sopra
2. Implementare `BallPhysics.gd` con:
   - Custom integrator (`_integrate_forces`)
   - Gravità
   - Drag quadratico
   - Rimbalzo con restituzione
3. Campo semplificato: piano infinito + pareti invisibili ai bordi
4. Palla visibile (sfera con materiale semplice, asse di rotazione visibile per debug spin)
5. Camera isometrica fissa (angolo simile a ISS Pro Evo 2: ~45° elevazione, ~30° laterale)

**Exit Criteria:**
- [ ] Palla lanciata verticalmente rimbalza con decadimento corretto
- [ ] Palla lanciata orizzontalmente decelera per drag in modo visivamente credibile
- [ ] Lo spin è visibile sull'asse della palla
- [ ] FPS stabile ≥60 in editor

---

### Sprint 2 — Magnus Effect + Spin System
**Obiettivo:** Calci a giro, foglia morta, effetti spin visibili e convincenti

**Tasks:**
1. Aggiungere Magnus force al custom integrator
2. Sistema di spin: ogni lancio può specificare `ω` come vettore 3D
3. Implementare knuckleball effect con perturbazione stocastica
4. `BallLauncher.gd`: lancio parametrico con:
   - Direzione (vettore o angoli)
   - Velocità iniziale (scalare)
   - Spin (vettore ω: x=topspin/backspin, y=sidespin, z=rifling)
5. `TrajectoryVisualizer.gd`:
   - Linea che mostra traiettoria passata (ultime N posizioni)
   - Linea predittiva (simulazione forward senza render, opzionale)

**Exit Criteria:**
- [ ] Tiro con sidespin sinistro → curva sinistra visibile e coerente
- [ ] Tiro con backspin forte → rimbalzo che rallenta o arretra
- [ ] Tiro con topspin → palla che accelera in avanti al rimbalzo
- [ ] Knuckleball percepibile ma non caotico con spin quasi zero
- [ ] Traiettoria passata visibile come ribbon/line

---

### Sprint 3 — Ground Interaction Avanzata + Spin Transfer
**Obiettivo:** Rimbalzi fisicamente convincenti in ogni scenario

**Tasks:**
1. Spin transfer al rimbalzo (palla cede/acquista spin dal suolo)
2. Restituzione variabile in funzione della velocità di impatto
3. Attrito dinamico con effetto sulla rotazione
4. Simulare due tipi di superficie:
   - Erba asciutta (default)
   - Erba bagnata (restituzione più alta, attrito ridotto)
5. Suono placeholder al rimbalzo (AudioStreamPlayer, sample sine wave) — il feedback audio è parte della percezione fisica

**Exit Criteria:**
- [ ] Palla calciata forte e bassa con backspin → si ferma bruscamente dopo il rimbalzo
- [ ] Palla calciata su erba bagnata → rimbalzo più lungo e scivoloso vs erba asciutta
- [ ] Comportamento del tiro rasoterra convincente (rotola, decele per attrito)
- [ ] Nessun tunneling (palla non attraversa mai il suolo)

---

### Sprint 4 — Debug UI + Parametri Runtime
**Obiettivo:** Pannello completo per calibrare la fisica in tempo reale

**Tasks:**
1. `PhysicsDebugUI.gd` — pannello overlay con slider per tutti i parametri:
   - Magnus coefficient
   - Drag coefficient
   - Restitution
   - Friction
   - Knuckleball threshold/amplitude
   - Gravity scale
   - Surface type toggle
2. Display real-time:
   - Velocità corrente della palla (km/h simulati)
   - Spin corrente (rad/s)
   - Altezza da terra
   - Forza Magnus/Drag istantanea (vettori)
3. Preset salvabili come `PhysicsConfig.tres`
4. Preset built-in: "Arcade", "Simulativo", "ISS Feeling"
5. Tasto reset palla alla posizione iniziale
6. Macro tiri preconfigurati (es: "Tiro a giro", "Foglia morta", "Rasoterra forte")

**Exit Criteria:**
- [ ] Tutti i parametri modificabili in runtime senza restart
- [ ] Preset "ISS Feeling" produce traiettorie che evocano ISS Pro Evo 2
- [ ] PHYSICS_LOG.md aggiornato con i valori ottimali trovati e motivazione

---

### Sprint 5 — Validazione e Documentazione
**Obiettivo:** Sandbox pronto come fondamenta per le fasi successive

**Tasks:**
1. Stress test: 100+ rimbalzi consecutivi senza comportamenti anomali
2. Validazione mobile: export Android (APK debug), test su dispositivo reale
3. Profiling: physics budget ≤2ms per frame a 60fps
4. `PHYSICS_LOG.md` completo:
   - Parametri finali con motivazione
   - Comportamenti emersi non previsti e come sono stati gestiti
   - Decisioni di design prese durante la calibrazione
5. `CLAUDE.md` del progetto aggiornato con architettura, convenzioni, e parametri fisici "protetti" (da non modificare senza ragione documentata)

**Exit Criteria:**
- [ ] APK funzionante su Android con ≥60fps
- [ ] Nessun comportamento fisico anomalo in 100+ iterazioni
- [ ] `CLAUDE.md` e `PHYSICS_LOG.md` completi e precisi
- [ ] Il sandbox è presentabile come demo standalone della fisica

---

## 🚫 Vincoli Non Negoziabili

1. **Custom integrator obbligatorio** — NON usare la fisica built-in di Godot per la palla. `RigidBody3D.custom_integrator = true` sempre.
2. **Drag quadratico** — mai lineare. È la differenza percepibile tra una palla vera e una finta.
3. **Magnus Effect sempre attivo** — anche con spin piccolo, l'effetto deve esistere (scalato). Zero spin = zero Magnus, non "Magnus disattivato".
4. **Nessun tunneling** — usa `ContinuousCCD` per la collision detection della palla.
5. **Parametri in Resource** — tutti i coefficienti fisici vivono in `PhysicsConfig.tres`, mai hardcodati nello script (eccetto i valori fisici universali come densità aria).
6. **PHYSICS_LOG.md aggiornato a ogni sprint** — ogni decisione di calibrazione deve essere documentata con prima/dopo e motivazione.

---

## 🎮 Riferimento Estetico (per la camera, non per la fisica)

ISS Pro Evo 2 usava una camera:
- Elevazione: ~40-50° rispetto al piano del campo
- Angolo laterale: leggermente obliquo (non perfettamente frontale)
- Leggerissimo tracking della palla (non rigido)
- Nessuno zoom dinamico in questa fase

Implementa questa camera nel sandbox come riferimento visivo. La fisica deve **sembrare giusta** da questa prospettiva specifica.

---

## 📋 Output Attesi al Completamento della Fase 1

| Deliverable | Descrizione |
|------------|-------------|
| `PhysicsSandbox.tscn` | Scena sandbox completamente funzionante |
| `BallPhysics.gd` | Custom integrator testato e documentato |
| `PhysicsConfig.tres` | Preset "ISS Feeling" validato |
| `PHYSICS_LOG.md` | Log completo delle calibrazioni |
| `CLAUDE.md` | Architettura, convenzioni, parametri protetti |
| APK debug Android | Build funzionante su dispositivo reale |

---

## 🔁 Modalità di Lavoro

- Procedi **sprint per sprint**, non anticipare sprint successivi
- Al termine di ogni sprint, **documenta** in `PHYSICS_LOG.md` prima di procedere
- Se durante l'implementazione emergono comportamenti fisici non previsti, **fermati e discuti** prima di procedere con workaround
- I parametri fisici "canonici" (validati) vanno marcati in `PHYSICS_LOG.md` come `[LOCKED]` — non si toccano senza motivazione esplicita
- Preferisci **GDScript** per rapidità di iterazione. Se un calcolo fisico è bottleneck dimostrato dal profiler, allora valuta C#

---

## 🌊 Contesto Ruflo

Questo progetto usa **Ruflo** come orchestratore MCP collegato a Claude Code.
La memoria del progetto è gestita da Ruflo AgentDB — i parametri fisici validati, le decisioni architetturali e i pattern emergenti vengono memorizzati e recuperati automaticamente tra sessioni.

Ogni sprint inizia con: `ruflo memory search "IssNostalgia physics"` per recuperare il contesto accumulato.

---

*Prompt Contract generato per IssNostalgia — Fase 1: Physics Sandbox*
*Modello target: Claude Opus 4.6 (claude-opus-4-6)*
*Data: Maggio 2026*
