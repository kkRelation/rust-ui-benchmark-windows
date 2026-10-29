# Makepad Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add and measure a Makepad 1.0 Windows resident probe with two retained windows, then delete its isolated caches.

**Architecture:** A Makepad application uses `MultiWindow` with two desktop Window instances and one Rust-side selected value. The live design defines the static scene; stdin commands are bridged into Makepad's event loop through its supported cross-thread signal/action mechanism. Visibility is handled by Makepad's window platform API when available, otherwise by the same current-process/title-scoped Win32 adapter used by other probes.

**Tech Stack:** Rust 2024, `makepad-widgets = "=1.0.0"`, Makepad Windows renderer, shared `ui-bench-protocol`.

**Spec:** `docs/superpowers/specs/2026-10-29-sequential-framework-expansion-design.md`

## Global Constraints

- Requires completed foundation, Iced, gpui-kit, and KAS plans.
- Preserve exact titles, dimensions, scene counts, shared selection, event order, and 400x20 ms workload.
- Use Makepad's normal Windows renderer and `MultiWindow`; do not embed a WebView or run two processes.
- Pin all direct Makepad crates to 1.0.0 and commit `Cargo.lock`.
- Keep dependency/build data under `.benchmark-work/makepad`; delete only after result validation.
- Validate/commit/`git swap auto`/push/remote-check after each task.

## Review Focus

- `MultiWindow` must create two actual top-level HWNDs on Windows, not two in-process panels; Task 1 spike and Task 3 smoke check this.
- The cross-thread command bridge must wake a fully hidden event loop; Task 1 spike exercises show after hidden readiness.
- Live-design animations, demo mode, and continuous redraw must be disabled unless required by the static scene; Task 1 review and Task 3 idle metrics catch this.
- Both windows must use one Rust selection value and one workload clock; Task 2 tests the controller.
- If Makepad lacks retained hide/show, the adapter must filter by current PID and exact titles; Task 2 unit-tests the filter.

---

### Task 1: Prove Makepad lifecycle feasibility with a disposable spike

**Files:**
- Create: `probes/makepad-probe/Cargo.toml`
- Create: `probes/makepad-probe/src/main.rs`
- Create: `probes/makepad-probe/src/app.rs`

**Interfaces:**
- Pin `makepad-widgets = "=1.0.0"`.
- Spike must expose two exact-title `MultiWindow` windows, an external-thread wakeup, retained hide/show, and quit.

- [ ] **Step 1: Create the minimal exact-version spike in the isolated workspace**

Follow the pinned Makepad multi-window example, with empty content and no benchmark scene. Resolve/download only under `.benchmark-work/makepad`.

- [ ] **Step 2: Add stdin commands for `show`, `hide`, and `quit`**

Use Makepad's supported event-loop signal/action API. If no retained visibility call exists, add a temporary PID/title-scoped adapter and record that decision in source comments.

- [ ] **Step 3: Manually run a one-cycle lifecycle check**

Verify with the existing harness window enumerator that there are two hidden HWNDs, then two visible HWNDs, then the same two hidden HWNDs, and clean quit. Record handles to prove retention.

- [ ] **Step 4: Stop if the spike cannot satisfy the contract**

Do not build the full scene or substitute close/recreate behavior. Preserve logs/workspace and report the blocker.

- [ ] **Step 5: Commit the proven skeleton and synchronize**

Commit message: `spike: prove makepad resident window lifecycle`

Run account selection, push, and local/remote equality check.

---

### Task 2: Complete the Makepad benchmark probe

**Files:**
- Modify: `probes/makepad-probe/src/main.rs`
- Modify: `probes/makepad-probe/src/app.rs`
- Create: `probes/makepad-probe/src/scene.rs`
- Create: `probes/makepad-probe/src/controller.rs`
- Create: `probes/makepad-probe/src/visibility.rs` only if Task 1 required the adapter
- Create: `probes/makepad-probe/Cargo.lock`

**Interfaces:**
- `controller.rs` owns the single selected value, command bridge, 400-step schedule, cycles, and protocol events.
- `scene.rs` registers live design for both exact scenes and updates selection-dependent properties in both windows.
- Binary framework identity is `makepad`.

- [ ] **Step 1: Write pure controller tests**

Assert readiness gating, exact workload step count, modulo-72 state, one clock, cycles, quit, and title/PID filtering if an adapter exists.

- [ ] **Step 2: Implement the two static live-design scenes**

Match row/key counts, content, selected styling, panels, and dimensions. Disable demo/performance views and avoid live animations or next-frame loops.

- [ ] **Step 3: Implement shared state projection and protocol timing**

Every workload step mutates one value and requests redraw for both windows. Emit lifecycle events around actual window/state operations.

- [ ] **Step 4: Run format/tests and inspect the dependency graph**

Use `invoke-framework-cargo.ps1 -Framework makepad` for `fmt`, `test`, and
`tree -e features`, always passing
`--manifest-path ./probes/makepad-probe/Cargo.toml`.

Expected: PASS; direct Makepad crates are 1.0.0; no WebView dependency was added.

- [ ] **Step 5: Generate and verify the lockfile, then rebuild `--locked`**

Keep all artifacts in `.benchmark-work/makepad`.

- [ ] **Step 6: Commit and synchronize**

Commit message: `feat: complete makepad resident benchmark probe`

Run account selection, push, and equality check.

---

### Task 3: Activate, measure, archive, and clean Makepad

**Files:**
- Modify: `harness/framework-registry.ps1`
- Modify: `harness/tests/FrameworkRegistry.Tests.ps1`
- Create: `results/<measurement-date>/makepad.json`
- Create: `results/<measurement-date>/makepad-artifacts/round-1-events.jsonl`
- Create: `results/<measurement-date>/makepad-artifacts/round-2-events.jsonl`
- Create: `results/<measurement-date>/makepad-artifacts/round-3-events.jsonl`
- Modify: `README.md`

**Interfaces:**
- Enables the predeclared `makepad` definition; its exact directory, binary,
  pin name, and pin remain unchanged.
- Consumes: `just framework-test makepad`.

- [ ] **Step 1: Add the failing registry test, implement the definition, and rerun**

Run: `Invoke-Pester -Path './harness/tests/FrameworkRegistry.Tests.ps1'`

Expected: FAIL while Makepad is disabled and PASS after activation; the full
harness suite also passes.

- [ ] **Step 2: Commit registration and synchronize**

Commit message: `feat: register makepad benchmark contestant`

Run account selection, push, and equality check.

- [ ] **Step 3: Run source/harness tests and isolated measurement**

Run the isolated Cargo wrapper for `test --locked --manifest-path
./probes/makepad-probe/Cargo.toml`, then run the complete Pester suite and
`just framework-test makepad`.

Expected: smoke and three rounds succeed; two retained HWNDs persist; hidden idle is measured with no benchmark-added continuous redraw; cleanup removes `.benchmark-work/makepad`.

- [ ] **Step 4: Audit durable result and cleanup**

Use `jq` to validate rounds/phases/topology/events/hashes and assert the disposable work root is absent.

- [ ] **Step 5: Update README and run final checks**

Add the dated Makepad result and note any Win32 visibility adapter. Run `Invoke-Pester -Path './harness/tests'; git diff --check; git status --short`.

- [ ] **Step 6: Commit and synchronize**

Commit message: `bench: add makepad resident measurements`

Run account selection, push, confirm equality, then begin the FerroUI plan.
