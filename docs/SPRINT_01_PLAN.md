# SPRINT 01 — Foundation: Plan di Esecuzione

**Progetto:** IssNostalgia
**Fase:** 1 — Physics Sandbox
**Sprint:** 01 — Foundation (Struttura + Palla Base)
**Branch:** `sprint/01-foundation` (creato da `main` dopo Bootstrap)
**Workflow:** Task → Commit `[S01-Txx]` → Mostra → Attendi "ok prosegui" → Task successivo

---

## 0. Pre-Flight Verifiche

Eseguite prima del Bootstrap (T0). Solo log, nessun commit.

| Check | Comando / Azione | Esito Atteso |
|-------|------------------|--------------|
| Godot 4 .NET installato | `godot --version` | `4.x.y.stable.mono` |
| `gh` CLI auth | `gh auth status` | logged in user `GitBakko` |
| Visual Studio 2026 | path `devenv.exe` | trovato |
| Repo remote raggiungibile | `gh repo view GitBakko/IssNostalgia` | OK |
| `git submodule` supportato | `git --version` | ≥ 2.30 |

**Se uno fallisce:** stop, segnalo, attendo fix.

---

## 1. Bootstrap (commit unico su `main`)

Tag commit: `[INIT] Project scaffolding`

### Deliverable

```
IssNostalgia/
├── .gitignore                  # Godot ufficiale + .mono/ + *.user + .idea/ + .vs/
├── .gitmodules                 # submodule refs
├── .gitattributes              # eol=lf per .gd .cs .md; binary per .glb .png .wav
├── LICENSE                     # MIT, holder: GitBakko
├── README.md                   # stub (titolo + tagline + setup)
├── CLAUDE.md                   # append sezione ## IssNostalgia Physics
├── project.godot               # config Godot 4 .NET, GLES3 Compatibility, 120Hz tick
├── icon.svg                    # icona default Godot
├── PROMPT_CONTRACT_ISS_NOSTALGIA_PHASE1.md   # mosso da docs/ in root? NO — resta in docs/
├── addons/
│   ├── imgui-godot/            # submodule pkulchenko/imgui-godot v6.x
│   └── gut/                    # submodule bitwes/Gut v9.x
├── docs/
│   ├── PROMPT_CONTRACT_ISS_NOSTALGIA_PHASE1.md   # esistente
│   ├── SPRINT_01_PLAN.md       # questo file
│   └── PHYSICS_LOG.md          # template vuoto
├── scenes/                     # vuoto (.gdkeep)
├── scripts/                    # vuoto (.gdkeep)
├── resources/
│   ├── backups/                # vuoto (.gdkeep)
│   └── .gdkeep
├── assets/
│   ├── ball/.gdkeep
│   └── field/.gdkeep
└── tests/
    ├── unit/.gdkeep
    └── .gutconfig.json
```

### project.godot — Impostazioni Chiave

```ini
[application]
config/name="IssNostalgia"
config/features=PackedStringArray("4.x", "C#", "Mobile")
config/icon="res://icon.svg"
run/main_scene="res://scenes/PhysicsSandbox.tscn"   # placeholder finché T01 non la crea

[physics]
common/physics_ticks_per_second=120
common/max_physics_steps_per_frame=8
3d/default_gravity=9.81
3d/default_gravity_vector=Vector3(0, -1, 0)

[rendering]
renderer/rendering_method="gl_compatibility"
renderer/rendering_method.mobile="gl_compatibility"
textures/vram_compression/import_etc2_astc=true

[display]
window/size/viewport_width=1920
window/size/viewport_height=1080
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[dotnet]
project/assembly_name="IssNostalgia"
```

### PHYSICS_LOG.md — Template

```
# PHYSICS_LOG.md — IssNostalgia Phase 1

## Convenzioni
- Stato: [DRAFT] (in calibrazione) | [VALIDATED] (testato) | [LOCKED YYYY-MM-DD] (immutabile senza rationale)
- Ogni modifica a param `[LOCKED]` richiede nuovo entry con motivazione.

## Sprint 01 — Foundation

### Parametri Fisici
| Parametro | Valore Iniziale | Valore Finale | Stato | Rationale |
|-----------|-----------------|---------------|-------|-----------|
| BALL_MASS | 0.43 kg | — | [DRAFT] | FIFA spec pallone standard |
| BALL_RADIUS | 0.11 m | — | [DRAFT] | FIFA spec |
| AIR_DENSITY | 1.225 kg/m³ | — | [DRAFT] | livello del mare |
| DRAG_COEFF | 0.47 | — | [DRAFT] | sfera liscia |
| GRAVITY | 9.81 m/s² | — | [DRAFT] | standard terrestre |
| RESTITUTION_BASE | 0.6 | — | [DRAFT] | erba asciutta default contract |

### Decisioni Architetturali
| ID | Decisione | Rationale |
|----|-----------|-----------|
| S01-A01 | Custom integrator via `_integrate_forces` | Contract vincolo non negoziabile |
| S01-A02 | Substep adattivo 4/6/8 in base a `|v|` | Bilancia accuratezza/costo |
| S01-A03 | Semi-implicit Euler | RK4 overkill, Verlet senza constraints |

### Comportamenti Emersi
_(da popolare durante implementazione)_

---

## Sprint 02-05
_(da popolare)_
```

### README.md — Stub

```markdown
# IssNostalgia

> Mobile football game inspired by ISS Pro Evolution 2 (PS1, 1999).

Custom physics-driven football game built in Godot 4. Phase 1 builds an
isolated **Physics Sandbox** that implements a physically correct ball
model tuned for fun and readability on mobile devices.

## Physics Sandbox (Phase 1)

The sandbox is an end-to-end calibration tool for the ball physics:
custom integrator with quadratic drag, Magnus effect, knuckleball
perturbation, and Cross-2002 ground interaction with spin transfer.

## Setup

1. Install **Godot 4.x .NET** edition.
2. Clone with submodules:
   ```bash
   git clone --recurse-submodules https://github.com/GitBakko/IssNostalgia.git
   ```
   If already cloned: `git submodule update --init --recursive`
3. Open `project.godot` in Godot editor.
4. Enable addons in **Project → Project Settings → Plugins**: `imgui-godot`, `gut`.
5. Run main scene `scenes/PhysicsSandbox.tscn` (created in Sprint 01).

## License

MIT — see [LICENSE](LICENSE).
```

### CLAUDE.md — Append

Sezione `## IssNostalgia Physics` aggiunta in fondo al `CLAUDE.md` esistente:

```markdown
## IssNostalgia Physics

### Convenzioni Mondo
- Scala: 1 unità Godot = 1 metro reale
- Assi: Y up, -Z forward (Godot default)
- Physics tick: 120 Hz
- Spin vector ω: world space

### Parametri Protetti
Tutti i parametri marcati `[LOCKED]` in `docs/PHYSICS_LOG.md` non si modificano
senza nuova entry di rationale. Lista dinamica — consulta `PHYSICS_LOG.md` per
lo stato corrente.

### Convenzioni Codice
- GDScript Sprint 1-3, migrazione selettiva a C# solo se profiler lo richiede
- File ≤ 500 righe
- Custom integrator: `RigidBody3D.custom_integrator = true` sempre per la palla
- Drag quadratico mai lineare
- Tutti i coefficienti fisici vivono in `resources/PhysicsConfig.tres`

### Workflow Sprint
1. Branch per sprint: `sprint/NN-name`
2. Commit per task: `[SNN-Txx] descrizione`
3. Merge su `main` solo a sprint completato
4. `main` è sempre demo-ready
```

### Submodule Setup

```bash
git submodule add https://github.com/pkulchenko/imgui-godot addons/imgui-godot
git submodule add https://github.com/bitwes/Gut addons/gut
# Pin a tag stabile dopo add:
git -C addons/imgui-godot checkout v6.1.1   # versione effettiva da verificare
git -C addons/gut checkout v9.3.1            # versione effettiva da verificare
```

> **Nota**: tag esatti verificati prima del commit. Se versione non esiste, uso
> ultimo tag stabile disponibile e annoto in PHYSICS_LOG.

### .gitignore Highlights

```
# Godot 4
.godot/
.import/
*.import

# .NET / Mono
.mono/
*.user
bin/
obj/
.vs/

# IDE
.idea/
.vscode/

# OS
Thumbs.db
.DS_Store

# Build artifacts
*.apk
*.aab
android/build/

# Backup
resources/backups/*.tres
!resources/backups/.gdkeep
```

### Exit Bootstrap

- [ ] `git status` pulito su `main`
- [ ] `git push origin main` riuscito
- [ ] `git submodule status` mostra 2 submodule pinned
- [ ] `gh repo view` mostra README aggiornato
- [ ] Branch `sprint/01-foundation` creato e checked out
- [ ] Godot apre `project.godot` senza errori (warning su scena mancante ok)

---

## 2. Task Sprint 01

Tutti i task sotto avvengono su branch `sprint/01-foundation`.

### T01 — Field + Camera

**Goal:** Campo regolamentare visibile, camera ISS-like fissa, porte stub.

**Files creati:**
- `scenes/PhysicsSandbox.tscn` — scena root
- `scenes/Field.tscn` — campo + linee + porte
- `scripts/SandboxController.gd` — orchestrazione iniziale (~50 righe)
- `assets/field/field_texture.png` — placeholder texture verde con linee (genero procedurally se non scarico)
- `assets/field/grass_tile.png` — texture tile Kenney CC0

**Implementazione:**
- `PlaneMesh` 105×68 m, texture bakeata 2048×2048 con linee bianche (centrocampo, area rigore, dischetto, cerchio centro)
- 2 porte: `BoxMesh` 7.32×2.44×0.1 m, materiale bianco, montanti+traversa stub (3 box per porta)
- `Camera3D` perspective FOV 45°, posizione `(0, 35, 20)`, rotation guardando origine, angolo ~42° inclinazione
- `DirectionalLight3D` luce solare semplice, no shadow Sprint 1 (perf)
- `WorldEnvironment` con sky procedurale chiaro

**Exit T01:**
- [ ] Aprendo `PhysicsSandbox.tscn` vedo campo intero in vista
- [ ] Porte visibili alle estremità del campo
- [ ] Linee campo leggibili
- [ ] FPS ≥ 60 in editor
- [ ] Commit `[S01-T01] Field, goals and ISS-like camera`

---

### T02 — BallPhysics Core (Gravity + Quadratic Drag)

**Goal:** Palla cade con gravità, decelera in aria con drag quadratico, NO collisioni ancora.

**Files creati:**
- `scenes/Ball.tscn` — `RigidBody3D` con `CollisionShape3D` (SphereShape3D r=0.11), `MeshInstance3D` (GLTF pentagoni)
- `scripts/BallPhysics.gd` — custom integrator (~150 righe)
- `resources/PhysicsConfig.gd` — class_name PhysicsConfig extends Resource
- `resources/PhysicsConfig.tres` — preset default
- `assets/ball/ball_soccer.glb` — sphere con texture pentagoni (genero placeholder)
- `assets/ball/ball_albedo.png` — texture pentagoni neri

**BallPhysics.gd struttura:**

```gdscript
class_name BallPhysics extends RigidBody3D

@export var config: PhysicsConfig

var _last_position: Vector3
var _current_substeps: int = 4

func _ready() -> void:
    custom_integrator = true
    continuous_cd = true
    contact_monitor = true
    max_contacts_reported = 4
    mass = config.ball_mass
    _last_position = global_position

func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
    var dt: float = state.step
    _current_substeps = _compute_substeps(state.linear_velocity.length())
    var sub_dt: float = dt / float(_current_substeps)
    for i in _current_substeps:
        _integrate_substep(state, sub_dt)

func _integrate_substep(state, sub_dt: float) -> void:
    var v: Vector3 = state.linear_velocity
    var f_total: Vector3 = _gravity_force() + _drag_force(v)
    var a: Vector3 = f_total / mass
    # Semi-implicit Euler
    var v_new: Vector3 = v + a * sub_dt
    var p_new: Vector3 = state.transform.origin + v_new * sub_dt
    state.linear_velocity = v_new
    var t: Transform3D = state.transform
    t.origin = p_new
    state.transform = t

func _gravity_force() -> Vector3:
    return Vector3(0.0, -config.gravity, 0.0) * mass

func _drag_force(v: Vector3) -> Vector3:
    var speed: float = v.length()
    if speed < 0.001: return Vector3.ZERO
    var area: float = PI * config.ball_radius * config.ball_radius
    var magnitude: float = 0.5 * config.air_density * config.drag_coeff * area * speed * speed
    return -v.normalized() * magnitude

func _compute_substeps(speed: float) -> int:
    if speed < 15.0: return 4
    elif speed < 25.0: return 6
    else: return 8
```

**PhysicsConfig.gd:**

```gdscript
class_name PhysicsConfig extends Resource

@export var ball_mass: float = 0.43
@export var ball_radius: float = 0.11
@export var air_density: float = 1.225
@export var drag_coeff: float = 0.47
@export var gravity: float = 9.81
@export var restitution_base: float = 0.6
@export var friction: float = 0.3
# Sprint 2+ params (default a 0 finché non implementati):
@export var magnus_coeff: float = 0.0
@export var knuckle_threshold_spin: float = 2.0
@export var knuckle_threshold_speed: float = 15.0
@export var knuckle_amplitude: float = 0.0
```

**Exit T02:**
- [ ] Palla istanziata cade per gravità (visibile)
- [ ] Palla lanciata in alto rallenta più velocemente del solo gravità → drag attivo
- [ ] No collision yet — palla cade sotto Y=0 (atteso)
- [ ] Commit `[S01-T02] BallPhysics core with gravity and quadratic drag`

---

### T03 — Ground Collision + Restitution

**Goal:** Palla rimbalza correttamente sul suolo. Restituzione costante (variabile arriva Sprint 3).

**Files modificati:**
- `scripts/BallPhysics.gd` — aggiungi collision handling
- `scenes/Field.tscn` — aggiungi `StaticBody3D` con `CollisionShape3D` (WorldBoundary o BoxShape sottile)
- `scenes/PhysicsSandbox.tscn` — aggiungi pareti invisibili ai 4 bordi del campo (StaticBody3D + BoxShape 1m alto)

**Implementazione collision:**

```gdscript
# In BallPhysics._integrate_substep, dopo update posizione:
var contacts: int = state.get_contact_count()
for i in contacts:
    var normal: Vector3 = state.get_contact_local_normal(i)
    var v_n: float = state.linear_velocity.dot(normal)
    if v_n < 0.0:   # palla entrando nella superficie
        _apply_bounce(state, normal, v_n)

func _apply_bounce(state, normal: Vector3, v_n: float) -> void:
    var v: Vector3 = state.linear_velocity
    var v_normal: Vector3 = normal * v_n
    var v_tangent: Vector3 = v - v_normal
    var v_normal_new: Vector3 = -config.restitution_base * v_normal
    var v_tangent_new: Vector3 = v_tangent * (1.0 - config.friction)
    state.linear_velocity = v_normal_new + v_tangent_new
    _emit_bounce_signal(abs(v_n))   # placeholder per audio Sprint 3
```

**Note:**
- Substep + CCD garantiscono no tunneling per `|v|` fino a ~80 m/s
- Backup swept-sphere manuale: ray test `_last_position → new_position` ogni substep, se hit ground stage early → applica bounce a punto hit
- Pareti laterali del campo: stesso bounce con `restitution_base × 0.8` (assorbono di più)

**Exit T03:**
- [ ] Palla droppata da 5m rimbalza, altezza decrescente con `e = 0.6`
- [ ] Palla lanciata orizzontalmente a 20 m/s rotola, decelera per drag+friction
- [ ] Nessun tunneling visibile (test `v_init = 50 m/s` verticale verso il basso)
- [ ] Spin asse visibile (texture pentagoni ruota — anche se Sprint 1 spin è puramente cinematico, non simulato)
- [ ] Commit `[S01-T03] Ground collision and restitution bounce`

---

### T04 — GUT Tests (4 Test Numerici)

**Goal:** Suite test passa al verde. Fisica testata, non solo "guardata".

**Files creati:**
- `tests/unit/test_ball_physics.gd` — 4 test
- `tests/unit/test_physics_config.gd` — sanity check resource

**Test stubs:**

```gdscript
extends GutTest

const SIM_TIME := 2.0
const TICK_DT := 1.0 / 120.0

func _make_ball() -> BallPhysics:
    # Istanzia ball senza scena, applica config default, ritorna nodo
    ...

func test_gravity_integration() -> void:
    # No drag (disable): integra 1s, verify v ≈ g*1 = 9.81 entro 0.01 m/s
    ...

func test_drag_terminal_velocity() -> void:
    # Drop libero verticale, simula 30s, verify |v| converge a
    # v_term = sqrt(2 * m * g / (rho * Cd * A)) entro 5%
    # Atteso ~28-30 m/s per pallone standard
    ...

func test_restitution_decay() -> void:
    # Drop verticale h0=2m, restitution=0.6, no drag
    # Verify h_n = h_0 * e^(2n) per n=1..5 entro 3%
    # h1 = 2 * 0.36 = 0.72m, h2 = 0.2592m, ...
    ...

func test_no_tunneling() -> void:
    # Pos iniziale Y=10, v=(0,-50,0), simula 1s
    # Verify y >= 0 in ogni frame del log
    ...
```

**Run:** `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit`

**Exit T04:**
- [ ] 4 test pass
- [ ] Output GUT log salvato in `tests/last_run.log` (gitignored)
- [ ] Commit `[S01-T04] GUT unit tests for ball physics`

---

### T05 — BallLauncher Minimal + Spin Visual

**Goal:** Lanciare la palla con parametri (velocità + direzione) per validare Exit Criteria contract. Rotazione visiva.

**Files creati:**
- `scenes/BallLauncher.tscn` — Node3D + UI Control overlay
- `scripts/BallLauncher.gd` — input + parametric launch (~80 righe)
- `scripts/SandboxController.gd` — espande: reset palla, hotkey

**Comandi:**
- `Space` → lancio verticale 15 m/s
- `H` → lancio orizzontale 20 m/s asse +X
- `R` → reset posizione palla a `(0, 1.5, 0)`
- `Mouse drag` (Sprint 1 desktop) → direzione + magnitudo, release per lancio
- Spin Sprint 1: input setta `angular_velocity` SOLO per rotazione visiva (no simulazione fisica)

**Exit T05:**
- [ ] Tutti 4 Exit Criteria contract validati visivamente:
  - Palla verticale rimbalza con decadimento corretto ✅
  - Palla orizzontale decelera credibile ✅
  - Spin visibile sull'asse ✅
  - FPS ≥ 60 in editor ✅
- [ ] `PHYSICS_LOG.md` aggiornato con osservazioni Sprint 1
- [ ] Commit `[S01-T05] Parametric launcher and spin visualization`

---

### T06 — Sprint 1 Review + Merge

**Goal:** Sprint chiuso, pulito, mergeato in main.

**Azioni:**
- Run full GUT suite — verde
- Verifica visiva Exit Criteria
- Aggiorna `PHYSICS_LOG.md` con valori finali e marker `[VALIDATED]` per parametri provati
- `gh pr create` → PR `sprint/01-foundation → main`
- Self-review nel PR body con checklist Exit Criteria
- Merge squash o merge commit (decido in base a stato history)
- Tag `v0.1.0-sprint01` su main post-merge

**Exit T06:**
- [ ] PR merged
- [ ] `main` aggiornato
- [ ] Tag pushed
- [ ] Tasks Sprint 1 tutti spuntati nel contract

---

## 3. Riepilogo Commit

```
main:
  9a62f60  [INIT] Initial commit (esistente)
  XXXXXXX  [INIT] Project scaffolding (Bootstrap)

sprint/01-foundation (branched from main post-Bootstrap):
  XXXXXXX  [S01-T01] Field, goals and ISS-like camera
  XXXXXXX  [S01-T02] BallPhysics core with gravity and quadratic drag
  XXXXXXX  [S01-T03] Ground collision and restitution bounce
  XXXXXXX  [S01-T04] GUT unit tests for ball physics
  XXXXXXX  [S01-T05] Parametric launcher and spin visualization
  XXXXXXX  [S01-DOC] PHYSICS_LOG Sprint 1 calibration notes

main (post-merge):
  XXXXXXX  Merge sprint/01-foundation → main (PR #1)
  tag:     v0.1.0-sprint01
```

---

## 4. Rischi Identificati

| Rischio | Probabilità | Mitigazione |
|---------|-------------|-------------|
| Tag submodule (imgui-godot v6.x, GUT v9.x) non esatto | Media | Fallback ultimo stable + log in PHYSICS_LOG |
| `_integrate_forces` + `state.transform` setting collision-skip | Media | Test no_tunneling cattura, fallback `state.integrate_forces()` default |
| CCD Godot 4 non sufficiente a 50+ m/s | Bassa | Swept-sphere backup già previsto |
| Texture pentagoni placeholder brutta da editor | Bassa | Accettabile Sprint 1, Sprint 5 estetica |
| GUT headless non runna su Windows | Bassa | Documentato `--rendering-driver opengl3` fallback |

---

## 5. Cose NON Fatte in Sprint 1 (per chiarezza)

- ❌ Magnus force (Sprint 2)
- ❌ Knuckleball (Sprint 2)
- ❌ Spin transfer al rimbalzo (Sprint 3)
- ❌ Restituzione variabile (Sprint 3)
- ❌ Superfici multiple (Sprint 3)
- ❌ TrajectoryVisualizer (Sprint 2)
- ❌ PhysicsDebugUI completo (Sprint 4)
- ❌ Forward predictor (Sprint 2)
- ❌ Audio rimbalzo (Sprint 3)
- ❌ Squash visivo (Sprint 3)
- ❌ APK Android (Sprint 5)
- ❌ Touch input (Sprint 3)

Sprint 1 = **fondamenta**. Niente di più, niente di meno.

---

## 6. Ruflo Memory — Sprint 1

Solo a Exit T06 (sprint validato):

```bash
npx @claude-flow/cli@latest memory store \
  --namespace IssNostalgia/decisions \
  --key sprint01-architecture \
  --value "Semi-implicit Euler + adaptive substep (4/6/8). Custom integrator via _integrate_forces. Drag quadratico. Restitution costante 0.6. Field 105x68 1u=1m. Camera persp 45° (0,35,20)."

# Param LOCKED solo dopo validazione tua esplicita
```

Nessun `memory_store` durante lo sprint — solo a chiusura, e solo parametri validati.

---

## 7. Approvazione Richiesta

Prima di eseguire **Bootstrap (T0)** mi serve tuo "**ok plan, parti**" o lista modifiche.

Dopo Bootstrap, eseguirò T01, committerò, aspetterò "**ok prosegui**" prima di T02. E così via fino a T06.
