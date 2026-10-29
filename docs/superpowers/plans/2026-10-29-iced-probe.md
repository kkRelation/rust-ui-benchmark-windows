# Iced Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add and measure an Iced 0.14/WGPU contestant under the resident two-window protocol, then retain its source/results and delete its isolated caches.

**Architecture:** An Iced multi-window daemon owns one application state and two `window::Id` values. Both windows consume the same selected-row state; a subscription bridges stdin commands into Iced messages, while async tasks schedule the 400 updates. Windows are created hidden and use Iced/Winit visibility when available, otherwise the same title-scoped Win32 visibility adapter pattern already audited for zgui and Dioxus Native.

**Tech Stack:** Rust 2024, `iced = "=0.14.0"` with WGPU, shared `ui-bench-protocol`, Windows APIs only if required for retained visibility.

**Spec:** `docs/superpowers/specs/2026-10-29-sequential-framework-expansion-design.md`

## Global Constraints

- Requires a passing Slint anchor from `2026-10-29-sequential-benchmark-foundation.md`.
- Exact titles: `UI Framework Bench - Main` and `UI Framework Bench - Auxiliary Canvas`.
- Exact logical content sizes: 700x480 and 1200x760; 72 rows and 66 keys.
- Both windows exist before `ready-hidden`, remain allocated while hidden, and share one selected value.
- Exactly 400 updates at 20 ms; no independent workload per window.
- Pin Iced 0.14.0 and commit `Cargo.lock`; do not substitute tiny-skia.
- Build and measure only in `.benchmark-work/iced`; clean only after validated success.
- After each completed repository-changing task: validate, commit, `git swap auto`, push, and confirm local/remote equality.

## Review Focus

- Closing either window must not accidentally end the process before `quit`; Task 1 adds a state test and Task 3 smoke-tests it.
- Commands arriving before both hidden windows are ready must not be lost or handled early; Task 1 tests message gating.
- A workload command must update one shared value exactly 400 times and finish near 8 seconds; Task 1 tests the reducer, Task 3 checks event timing.
- Visibility control must affect only the two exact benchmark titles in the current process; Task 1 tests the adapter filter if it is used.
- WGPU initialization or device loss must emit an error/fail the run, never fall back to tiny-skia; Task 3 verifies renderer metadata and logs.

---

### Task 1: Implement the self-contained Iced probe

**Files:**
- Create: `probes/iced-probe/Cargo.toml`
- Create: `probes/iced-probe/src/main.rs`
- Create: `probes/iced-probe/src/scene.rs`
- Create: `probes/iced-probe/src/controller.rs`
- Create: `probes/iced-probe/src/windows.rs`

**Interfaces:**
- `scene.rs` produces `main_view(selected: usize) -> iced::Element<'static, Message>` and `auxiliary_view(selected: usize) -> iced::Element<'static, Message>`.
- `controller.rs` produces `BenchState`, `Message`, `update`, and the stdin command subscription.
- `windows.rs` produces `set_benchmark_windows_visible(visible: bool) -> Result<(), String>` only if Iced's retained public window handle cannot toggle visibility.
- The binary accepts `--event-log <path>` and the shared stdin command language.

- [ ] **Step 1: Write reducer and visibility-filter tests before UI code**

Test a pure controller reducer for readiness gating, one selected value modulo 72, exactly 400 workload steps, cycle counts, and quit. If a Win32 adapter is needed, test that it accepts only current-process windows with the two exact titles.

- [ ] **Step 2: Run tests and verify failure**

Run: `& './harness/invoke-framework-cargo.ps1' -Framework iced -CargoArguments @('test','--manifest-path','./probes/iced-probe/Cargo.toml')`

Expected: initial compile/test failure until the declared controller interfaces are implemented.

- [ ] **Step 3: Implement the manifest and controller**

Pin `iced = "=0.14.0"` with WGPU enabled and use `ui-bench-protocol` by path. Parse the required event-log argument, read commands on a dedicated thread/subscription bridge, and emit shared protocol events from application-controlled transitions.

- [ ] **Step 4: Implement both exact scenes**

Match the existing benchmark labels, row/key counts, color roles, selected-state behavior, and dimensions. Use Iced widgets/canvas without adding animations or timers outside the prescribed workload.

- [ ] **Step 5: Implement retained hidden multi-window lifecycle**

Open both windows with `visible = false`, retain both IDs, render by window ID, prevent close requests from silently exiting, and toggle both together. Prefer Iced's public retained window mechanism; use the title/PID-scoped Windows adapter only if the pinned API cannot set runtime visibility.

- [ ] **Step 6: Run unit tests and formatting**

Run the isolated Cargo wrapper once for `fmt --manifest-path
./probes/iced-probe/Cargo.toml -- --check` and once for `test --manifest-path
./probes/iced-probe/Cargo.toml`.

Expected: all tests PASS.

- [ ] **Step 7: Generate and inspect the lockfile in the isolated workspace**

Use `invoke-framework-cargo.ps1` so dependency downloads and compilation land
under `.benchmark-work/iced`. Run Cargo with `--locked` after generating
`probes/iced-probe/Cargo.lock`; confirm the resolved Iced version is exactly
0.14.0 and WGPU crates are present.

- [ ] **Step 8: Commit and synchronize**

Commit message: `feat: add iced resident benchmark probe`

Run the required account selection, push, and local/remote commit check.

---

### Task 2: Activate Iced in the harness

**Files:**
- Modify: `harness/framework-registry.ps1`
- Modify: `harness/tests/FrameworkRegistry.Tests.ps1`

**Interfaces:**
- Changes the predeclared `iced` definition from disabled to enabled after its
  manifest/source/lockfile exist; its exact path, binary, and pin do not change.
- Makes `just framework-test iced` available through the existing orchestrator.

- [ ] **Step 1: Add a failing registry test**

Assert every exact Iced definition field, its position after the historical
six, and `Enabled = $true`.

- [ ] **Step 2: Run and observe failure**

Run: `Invoke-Pester -Path './harness/tests/FrameworkRegistry.Tests.ps1'`

Expected: FAIL because `iced` is still disabled.

- [ ] **Step 3: Add the registry definition and rerun all harness tests**

Run: `Invoke-Pester -Path './harness/tests'`

Expected: all tests PASS.

- [ ] **Step 4: Commit and synchronize**

Commit message: `feat: register iced benchmark contestant`

Run the required account selection, push, and local/remote commit check.

---

### Task 3: Smoke-test, measure, archive, and clean Iced

**Files:**
- Create: `results/<measurement-date>/iced.json`
- Create: `results/<measurement-date>/iced-artifacts/round-1-events.jsonl`
- Create: `results/<measurement-date>/iced-artifacts/round-2-events.jsonl`
- Create: `results/<measurement-date>/iced-artifacts/round-3-events.jsonl`
- Modify: `README.md`

**Interfaces:**
- Consumes: `just framework-test iced`.
- Produces: one validated three-round Iced cohort result and no remaining `.benchmark-work/iced`.

- [ ] **Step 1: Run pre-measurement tests**

Run the isolated Cargo wrapper for `test --locked --manifest-path
./probes/iced-probe/Cargo.toml`, then run `Invoke-Pester -Path
'./harness/tests'`.

Expected: all tests PASS.

- [ ] **Step 2: Execute the isolated lifecycle**

Run: `just framework-test iced`

Expected: debug smoke and three release rounds succeed; renderer/log metadata identify WGPU; the result validator passes; guarded cleanup removes only `.benchmark-work/iced`.

- [ ] **Step 3: Verify result and cleanup invariants**

Use `jq` to assert three successful rounds, all five resource phases, two exact windows at every topology checkpoint, hashes/toolchain metadata, and referenced event logs. Assert `.benchmark-work/iced` is absent and source/lockfile remain.

- [ ] **Step 4: Update the expansion summary**

Add the dated Iced result and renderer label to README without changing historical values or claiming a universal ranking.

- [ ] **Step 5: Run final checks**

Run: `Invoke-Pester -Path './harness/tests'; git diff --check; git status --short`

Expected: PASS with only intended Iced source, results, and documentation changes.

- [ ] **Step 6: Commit and synchronize**

Commit message: `bench: add iced resident measurements`

Run `git swap auto`, push, confirm commit equality, then begin the gpui-kit plan.
