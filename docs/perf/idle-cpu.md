# Idle-CPU Regression Tests

Guards for the "app burns CPU while idle" class (leaked spinners, re-render loops).
See the design at `docs/superpowers/specs/2026-07-23-idle-cpu-regression-testing-design.md`.

## Layers

- **Layer 1 (unit):** Swift Testing tests tagged `.performance` (e.g. `ITerm2StderrDrainTests`).
  Run on every push via `just test` / CI `just coverage`. Also runnable in isolation with `just test-perf`.
- **Layer 2 (end-to-end):** `just test-idle-cpu` launches a real, populated, rendering instance
  isolated on port 7484 and asserts near-zero idle CPU. Runs in CI on PR/main.

## Running

    just test-idle-cpu                 # bridges off (CI-equivalent)
    just test-idle-cpu --with-bridges  # local only: exercises the real iTerm2 daemon

Env overrides: `IDLE_CPU_THRESHOLD` (default 0.10 core), `IDLE_CPU_PORT` (7484),
`IDLE_CPU_SETTLE` (8s), `IDLE_CPU_WINDOW` (20s).

On a local machine with iTerm2 installed, the default run (bridges off) may still briefly
launch the iTerm2 daemon via hook-triggered recovery; the isolated per-port socket prevents
any collision with a manual iTerm2 instance, so the per-PID CPU measurement stays valid.

## Threshold

Default `0.10` core. Real idle is ~0; both historical incidents were ≥ 1 full core, so the
margin is wide. Tune here if CI proves noisy.

| Date | Threshold | Note |
|------|-----------|------|
| 2026-07-24 | 0.10 | Initial. Confirm against first green CI run. |

## Deferred: soak test

A nightly workflow that runs the app for several minutes and asserts memory/threads stay
flat (catches *slow* leaks) is intended but not built. Revisit on a slow-leak incident.
