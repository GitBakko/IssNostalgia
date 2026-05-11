# SPRINT 03 — Ground Interaction & Spin Transfer

**Branch:** `sprint/03-ground-interaction`
**Workflow:** Auto mode, checkpoint at end of sprint.

## Tasks

- **T01** Cross-2002 spin transfer at hard bounce
- **T02** Variable normal restitution `e_n(|v_n|) = e_base · exp(-|v_n|/v_ref)`
- **T03** Surface zones: dry / wet erba toggle (single global flag this sprint)
- **T04** Audio: synthesised bounce sample, pitch ±5 %, volume ∝ impact speed
- **T05** Squash visual at impact (mesh non-uniform scale tween)
- **T06** Slow-mo toggle (F5, `Engine.time_scale = 0.25`)
- **T07** GUT regression + PHYSICS_LOG + PR / merge / tag `v0.3.0-sprint03`

## Exit Criteria (visual checks Sprint 04+)

- Topspin shot → forward acceleration at bounce
- Backspin shot → bounce slows / reverses
- Wet erba → longer bounce, less spin transfer
- Audio fires on bounce, pitch / volume varies
- Squash visible on hard impacts
- Slow-mo readable, GUT regression still PASS

## Out of Scope

- Per-zone surface (single global toggle this sprint)
- Replay system (slow-mo only, full replay Sprint 04+)
- Full Cross 2002 paper detail (using grip / slip-with-Coulomb simplification)
