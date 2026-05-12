# SPRINT 04 — Debug UI & Tuning

**Branch:** `sprint/04-debug-ui`
**Workflow:** Auto mode, checkpoint at end of sprint.

## Deviation from PROMPT_CONTRACT R2 / 8.1

R2 8.1 locked `imgui-godot` as the debug-UI library. The addon ships as
source only (C# scripts + GDExtension C++) with no pre-built binaries —
building it would require .NET tooling + a SCons/CMake C++ pass on
Windows. Out of scope for a tuning sprint.

**Decision (S04-A01):** use native Godot 4 Control nodes
(Panel / ScrollContainer / VBoxContainer / HSlider / SpinBox / Label /
Button). No external dep, runs immediately, ports cleanly to mobile in
Phase 2. Trade-off: no docking / no live console — acceptable for
Sandbox tuning.

## Tasks

- **T01** `scenes/PhysicsDebugUI.tscn` — Panel skin, ScrollContainer,
  one VBox group per PhysicsConfig section (Universe / Ball / Drag /
  Ground / Surface / Magnus / Knuckleball). HSlider + SpinBox + Label
  per parameter. F1 toggles panel.
- **T02** `scripts/PhysicsDebugUI.gd` — two-way binding slider ↔ live
  `PhysicsConfig.tres`. Parameter metadata table (key, min, max, step,
  label, group). `_on_value_changed` writes back into the resource so
  the next physics tick picks it up.
- **T03** Extended telemetry: instantaneous |F_drag|, |F_magnus|,
  |F_knuckle|, |F_grass|, |omega|, spin parameter S. Already partly in
  `SandboxController.gd`; surface in a dedicated panel section.
- **T04** Preset system: built-in presets (Arcade / Simulativo /
  ISS_Feeling) shipped as `resources/presets/*.tres`. UI dropdown +
  Save / Load buttons. `Save current` writes to
  `user://presets/<name>.tres` so user-tuned configs persist between
  runs.
- **T05** 3D force gizmo: `scripts/ForceGizmo.gd` (Node3D +
  ImmediateMesh) drawing colour-coded arrows at the ball position —
  red drag, green Magnus, yellow knuckle, blue grass-kick, white net.
  Toggle G key.
- **T06** GUT regression run (Sprint 1+2+3 suites still PASS), update
  `docs/PHYSICS_LOG.md` with S04-A0x decisions, PR / merge / tag
  `v0.4.0-sprint04`.

## Exit Criteria

- F1 opens debug panel, all params editable live, change is visible at
  the next launched ball
- Presets switchable from dropdown without restart; user-saved presets
  reload across game sessions
- Force gizmo toggles cleanly with G, arrow lengths scale with
  magnitude
- GUT regression: Sprint 1+2+3 still PASS, no new failures
- `docs/PHYSICS_LOG.md` updated with the deviation rationale and any
  new tuning defaults found while playing with sliders

## Out of Scope

- Per-zone surface authoring (still single global wet/dry flag)
- Full replay system (slow-mo only)
- Sound mixer UI (audio levels stay code-side this sprint)
- imgui-godot integration (deferred; only worth the build effort once
  we need docking / multi-window in Phase 2)
- Mobile-friendly layout (cursor-driven; touch layout in Phase 2)
