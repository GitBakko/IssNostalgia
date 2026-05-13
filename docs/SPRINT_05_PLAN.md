# SPRINT 05 — Calibration & Validation

**Branch:** `sprint/05-calibration`
**Workflow:** Checkpoint task-by-task. After every task: commit → push →
wait for explicit "ok prosegui" from the user before the next task.
Auto-merge is OFF for this sprint because most calibrations are
subjective ("knuckle drift visivamente ok", "rasoterra pulito") and
need eyes-on approval, not just a green GUT run.

## Goal

Close every `[PENDING]` item left by Sprints 1–4, lock each shot type
with a numerical regression, and leave Phase 1 in a "demo-ready +
verified" state ready for the Sprint 6 Android export pass.

## Tasks

### T01 — Bounce energy audit harness
- `tests/unit/test_bounce_energy.gd` (new GUT script)
- Uses `BallPhysics.predict_forward` to simulate N=8 consecutive
  bounces from a controlled launch state
- For each bounce records: KE_lin = ½·m·|v|², KE_rot = ½·I·|ω|²,
  E_total = KE_lin + KE_rot, peak height between bounces
- Asserts:
  - `E_total[i+1] <= E_total[i] * (1 + ε)` for every i  (ε = 1e-3
    for fp noise; grass_kick disabled in this test)
  - peak height monotone non-increasing
  - `|v|` monotone non-increasing in the slip case
- Test cases: spinless lob, topspin curve, backspin drop, knuckle-ish
  low-spin grounder

Out of scope: per-bounce assertion of Cross-2002 grip-vs-slip class;
that's covered by Sprint 3 tests already.

### T02 — Lob second-bounce "schizzo" fix
- Run T01 harness with the exact lob shape from the user report
- If the energy check fires, inspect which channel grew:
  - **Cross-2002 spin→linear leak** → reduce `bounce_e_t`
    (0.5 → 0.35) or add an explicit `omega *= spin_decay_per_bounce`
    (default 0.9) inside `_bounce_cross_2002`
  - **Grass kick amplified** → cap `kick_eff` more aggressively,
    or gate by impact speed only
- Visual regression: 6+ LMB lobs at various distances → every
  trajectory monotonically decays
- Closes `[PENDING] Lob second-bounce schizzo` from PHYSICS_LOG
- New decision `S05-A01` documenting the chosen fix

### T03 — Knuckleball realism pass
- Per-frame knuckle force overlay (extend ForceGizmo or add a
  dedicated thin trail) so the wobble is visible
- Test target: knuckle 28 m/s @ 10° → lateral drift 0.8–1.5 m at
  ~25 m of horizontal travel (arcade ISS-feeling, NOT real-life
  physics — real knuckle is too unpredictable for the game we want)
- Interactive tuning via the existing F1 debug UI: amplitude,
  noise_frequency, spike_frequency_mul, spike_threshold,
  spike_amplitude_mul
- Lock the chosen values as `S05-A02`; closes the Sprint 2 PENDING
- One new GUT test: locks the deterministic acceleration sequence
  for the chosen seed at the chosen parameters

### T04 — Low-power rasoterra verification
- Mirror test for 3 power levels along +X:
  - 30 m/s @ 1° (already validated Sprint 2)
  - 15 m/s @ 3° (intermediate)
  - 10 m/s @ 1° (low — untested before)
- Expected behaviour: bounce height ≤ 4 cm, no "skip" larger than
  6 cm anywhere along the roll, ball comes to rest naturally
- Tune `grass_roughness_min_speed` and `grass_kick_amount` if the low
  shot still hops; document as `S05-A03`
- New GUT test asserts max-y across a 3-second simulation for each
  power level

### T05 — Per-zone surfaces (close S03 deferral)
- New script `SurfaceZone.gd` (Area3D + `@export var wet: bool`)
- `BallPhysics` queries `get_overlapping_areas()` once per substep
  (or caches the last-known zone and invalidates on Area3D enter /
  exit signal — preferred to avoid a per-substep query)
- All surface-aware getters (`_mu_s()`, `_rolling_friction()`,
  `_restitution_base()`, `_grass_kick_amount()`) read from the
  active zone instead of the global `config.surface_wet`
- Backwards compat: if no zone overlaps the ball, fall back to
  `config.surface_wet` (so existing scenes / tests still pass)
- Sandbox demo: one visible wet patch (~5 × 5 m) with a darker
  material at world position (0, 0, 8) → roll the ball through it,
  feel the friction drop
- Test: GUT test using `predict_forward` plumbing an in-memory zone
  switch mid-trajectory (mock the area-query)
- Decision `S05-A04`

### T06 — Mini replay / frame-step
- Ring buffer on `BallPhysics`: `Array[Dictionary]` of `{p, v, ω, t}`
  sized for 5 s of history at 120 Hz → 600 entries
- Push on every physics tick, oldest entry overwritten
- New input bindings (Sandbox + HUD + ImGui pane):
  - **F6** → enter replay mode, pause sim, jump cursor to end of
    buffer
  - **F7** → step forward 1 physics tick (replay-only)
  - **F8** → step backward 1 physics tick
  - **F9** → exit replay, resume live simulation
- During replay: physics integrator is skipped, position / velocity /
  omega are set directly from the buffer entry at the cursor
- Telemetry HUD shows `[REPLAY t=-1.234 s]` while active
- Decision `S05-A05`

### T07 — GUT regression + perf check
- Run full suite: Sprint 1 (4) + Sprint 2 (6) + Sprint 3 (7) + T01
  energy harness (4 cases) + T03 knuckle lock (1) + T04 rasoterra
  triple (3) + T05 zone switch (1) → target ~26 tests, all PASS
- Headless FPS sample: launch sandbox with `--auto-launch curve`,
  read `Engine.get_frames_per_second()` after 3 s → expect ≥ 60 on
  the dev box (Compatibility renderer, MSAA 2×)
- No new failures introduced by the calibration

### T08 — PHYSICS_LOG + PR/merge/tag
- Update `PHYSICS_LOG.md` with `S05-A01..S05-A05` decisions and the
  Sprint 05 calibration sessions table
- Move all `[PENDING]` rows that got closed to the historical record
- Open PR, self-review, merge to main
- Tag `v0.5.0-sprint05`

## Exit criteria

- Every `[PENDING]` from Sprints 1–4 is closed or explicitly
  re-deferred with a new rationale entry
- LMB lob multi-bounce: `E_total` monotone non-increasing across 6+
  bounces (numerical assertion in GUT)
- Knuckle drift confirmed visually inside the 0.8–1.5 m target band
- Both strong AND weak rasoterra produce clean trajectories
  (max-y ≤ 4 cm)
- One visible wet patch on the field; rolling through it changes
  friction obviously, no per-zone tearing artefacts
- F6–F9 replay covers ≥ 5 s of history, stepping forward / backward
  works frame-accurately
- 26+ GUT tests PASS, headless FPS ≥ 60

## Out of scope

- **Android export** → Sprint 6
- **Touch input / mobile UI overhaul** → Sprint 6
- **AI opponent / player logic** → Phase 2
- **Full Cross-2002 paper detail** (separate μ_d for sliding, rolling
  resistance during the bounce window) — only attempted if T02
  cannot be fixed by the simpler `bounce_e_t` / spin-decay tuning
- **Volumetric grass shader / particle splashes** → Phase 2 polish
- **Stadium nets / containment walls** — visible meshes deferred
  with the sandbox no-walls decision (S03-A18); will land alongside
  the level art in Phase 2
