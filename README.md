# IssNostalgia

> Mobile football game inspired by ISS Pro Evolution 2 (PS1, 1999).

Custom physics-driven football game built in **Godot 4 (.NET)**. Phase 1 builds
an isolated **Physics Sandbox** that implements a physically correct ball
model — quadratic drag, Magnus effect, knuckleball perturbation, Cross-2002
ground interaction with spin transfer — calibrated for fun and readability on
mobile devices.

## Physics Sandbox (Phase 1)

The sandbox is an end-to-end calibration tool for the ball physics:

- Custom integrator on `RigidBody3D` (semi-implicit Euler, adaptive substeps)
- Quadratic aerodynamic drag
- Magnus force with saturating lift coefficient `Cl(S) = S / (S + 0.5)`
- Knuckleball stochastic perturbation (seeded Simplex noise)
- Cross-2002 spin transfer at ground bounce
- Runtime calibration UI (Dear ImGui)
- 4-test GUT suite locking the physics formulas numerically

See [`docs/PROMPT_CONTRACT_ISS_NOSTALGIA_PHASE1.md`](docs/PROMPT_CONTRACT_ISS_NOSTALGIA_PHASE1.md)
for the design contract and
[`docs/SPRINT_01_PLAN.md`](docs/SPRINT_01_PLAN.md) for the current sprint plan.

## Setup

1. Install **Godot 4.x .NET edition** from
   [godotengine.org](https://godotengine.org/download/windows/).
   Tested on **Godot 4.6.2-stable mono**.
2. Clone with submodules:

   ```bash
   git clone --recurse-submodules https://github.com/GitBakko/IssNostalgia.git
   ```

   If already cloned without submodules:

   ```bash
   git submodule update --init --recursive
   ```

3. Open `project.godot` in the Godot editor.
4. Enable addons in **Project → Project Settings → Plugins**:
   `imgui-godot`, `gut`.
5. Run the main scene (`scenes/PhysicsSandbox.tscn` — created in Sprint 01).

## Running Tests

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
```

## License

[MIT](LICENSE)
