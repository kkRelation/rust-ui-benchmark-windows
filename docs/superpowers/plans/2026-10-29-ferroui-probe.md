# FerroUI Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add and measure the default FerroUI 0.4 desktop Skia/ANGLE stack without exceeding the single-framework disk policy, then remove its isolated caches.

**Architecture:** A classic desktop FerroUI Application creates two Window controls backed by one shared Rust model. A dispatcher-safe command bridge applies visibility and shared selection updates on the UI thread. The probe uses the released facade/default desktop configuration and Fluent theme, exercising the production control/style/compositor stack without enabling Vello, WinUI hosting, diagnostics, XAML compilation, or unrelated MVVM packages.

**Tech Stack:** Rust 2021/2024-compatible probe, FerroUI 0.4.0 facade or exact component crates, default Skia/ANGLE desktop renderer, shared `ui-bench-protocol`, MSVC/libclang prerequisites.

**Spec:** `docs/superpowers/specs/2026-10-29-sequential-framework-expansion-design.md`

## Global Constraints

- Requires all prior plans and their cleaned work roots.
- Run a free-space preflight before dependency resolution and again before release build; stop rather than using global caches or another disk silently.
- Use released FerroUI 0.4.0 with default desktop Skia/ANGLE; no Vello comparison or WinUI host in this contestant.
- Preserve exact titles, dimensions, row/key counts, one state value, event order, and 400x20 ms workload.
- Commit exact direct dependency pins and `Cargo.lock`.
- All downloads/build output remain in `.benchmark-work/ferroui`; validated cleanup follows successful archive.
- Validate/commit/`git swap auto`/push/remote-check after each completed task.

## Review Focus

- Peak free space may be insufficient even with sequential cleanup; Task 1 preflights and records a conservative requirement before download/build.
- Prebuilt Skia availability or libclang/MSVC discovery may fail; Task 1 stops with diagnostics rather than switching renderer.
- Default features may pull XAML, diagnostics, Vello, WinUI, or MVVM unintentionally; Task 2 inspects and minimizes the direct feature set while retaining the normal desktop/Fluent stack.
- Dispatcher/thread ownership must be respected for visibility and state updates; Task 2 tests the pure controller and Task 3 smoke-tests UI-thread dispatch.
- FerroUI's render thread must be included in the same process tree and allowed to idle naturally; Task 3 verifies topology and does not disable compositor behavior specially.

---

### Task 1: Preflight FerroUI toolchain, disk, and a minimal released window

**Files:**
- Create: `harness/ferroui-preflight.ps1`
- Create: `harness/tests/FerroUiPreflight.Tests.ps1`
- Create: `probes/ferroui-probe/Cargo.toml`
- Create: `probes/ferroui-probe/src/main.rs`

**Interfaces:**
- `ferroui-preflight.ps1` accepts `-WorkRoot` and `-MinimumFreeBytes`, returns structured JSON containing free bytes, MSVC discovery, libclang discovery, and pass/fail reasons.
- Minimal probe pins FerroUI 0.4.0 and opens one empty desktop Window through the default Skia/ANGLE path.

- [ ] **Step 1: Write failing preflight tests**

Mock disk/tool discovery and assert insufficient space, missing MSVC, and missing libclang each fail with a specific reason; a complete fixture passes without changing environment variables or installing software.

- [ ] **Step 2: Implement and test the read-only preflight**

Run: `Invoke-Pester -Path './harness/tests/FerroUiPreflight.Tests.ps1'`

Expected: all cases PASS; the script makes no filesystem changes beyond its explicitly requested output if any.

- [ ] **Step 3: Record actual free space and prerequisites**

Run the preflight against `.benchmark-work/ferroui`. If it fails, stop and report; do not start Cargo or install dependencies automatically.

- [ ] **Step 4: Build a minimal exact-version window in the isolated workspace**

Use the released 0.4.0 facade/default desktop recipe and Fluent theme. Confirm the actual renderer is Skia/ANGLE. Do not enable Vello, WinUI hosting, XAML compilation, diagnostics, or ReactiveUI.

- [ ] **Step 5: Stop if the released configuration cannot build within headroom**

Preserve the structured preflight/build log and workspace for diagnosis; do not substitute a Git preview or alternate renderer.

- [ ] **Step 6: Commit the proven preflight/skeleton and synchronize**

Commit message: `spike: verify ferroui benchmark prerequisites`

Run account selection, push, and local/remote equality check.

---

### Task 2: Complete the FerroUI probe

**Files:**
- Modify: `probes/ferroui-probe/Cargo.toml`
- Modify: `probes/ferroui-probe/src/main.rs`
- Create: `probes/ferroui-probe/src/application.rs`
- Create: `probes/ferroui-probe/src/scene.rs`
- Create: `probes/ferroui-probe/src/controller.rs`
- Create: `probes/ferroui-probe/Cargo.lock`

**Interfaces:**
- `application.rs` creates a classic desktop lifetime with two retained Window controls.
- `scene.rs` creates both exact control trees and exposes selection update hooks.
- `controller.rs` owns one selected value and dispatches stdin commands onto FerroUI's UI thread.
- Binary framework identity is `ferroui`.

- [ ] **Step 1: Write pure controller/shared-state tests**

Assert readiness gating, exact 400 updates, modulo-72 state, both scene projections, cycle counts, UI-dispatch requests, and quit.

- [ ] **Step 2: Implement Application and two hidden windows**

Initialize the Fluent theme and classic desktop lifetime. Create exact-title/sized Window controls before `ready-hidden`; retain them for the process lifetime and prevent user close from bypassing protocol quit.

- [ ] **Step 3: Implement both exact scenes with FerroUI controls**

Build the 72-row main scene and 66-key auxiliary scene with the same static text/panels/colors and selected-state semantics. Avoid diagnostics overlays, animation presets, and unrelated control catalogs.

- [ ] **Step 4: Implement dispatcher-safe lifecycle and workload**

Read stdin off-thread, post operations to the framework dispatcher, use one 20 ms schedule for 400 shared updates, toggle both retained windows, and emit protocol events only after operations are accepted/applied.

- [ ] **Step 5: Inspect features and build metadata**

Use `invoke-framework-cargo.ps1 -Framework ferroui` for `tree
--manifest-path ./probes/ferroui-probe/Cargo.toml -e features`.

Expected: released 0.4.0 direct crates and default desktop/Fluent/Skia/ANGLE path; no Vello, WinUI host, diagnostics, XAML build, or MVVM features unless transitively unavoidable and documented.

- [ ] **Step 6: Run formatting/tests and rebuild `--locked` in isolation**

Use the isolated Cargo wrapper for `fmt --manifest-path
./probes/ferroui-probe/Cargo.toml -- --check` and `test --manifest-path
./probes/ferroui-probe/Cargo.toml`.

Expected: PASS; all output stays in `.benchmark-work/ferroui`.

- [ ] **Step 7: Commit and synchronize**

Commit message: `feat: complete ferroui resident benchmark probe`

Run account selection, push, and equality check.

---

### Task 3: Activate, measure, archive, and clean FerroUI

**Files:**
- Modify: `harness/framework-registry.ps1`
- Modify: `harness/tests/FrameworkRegistry.Tests.ps1`
- Create: `results/<measurement-date>/ferroui.json`
- Create: `results/<measurement-date>/ferroui-artifacts/round-1-events.jsonl`
- Create: `results/<measurement-date>/ferroui-artifacts/round-2-events.jsonl`
- Create: `results/<measurement-date>/ferroui-artifacts/round-3-events.jsonl`
- Modify: `README.md`
- Modify: `docs/benchmark-design.md`

**Interfaces:**
- Enables the predeclared `ferroui` definition; its exact directory, binary,
  pin name, and pin remain unchanged.
- Consumes: `just framework-test ferroui`.

- [ ] **Step 1: Add failing registration test, implement, and rerun suite**

Run: `Invoke-Pester -Path './harness/tests/FrameworkRegistry.Tests.ps1'; Invoke-Pester -Path './harness/tests'`

Expected: initial focused failure; all tests PASS after registration.

- [ ] **Step 2: Commit registration and synchronize**

Commit message: `feat: register ferroui benchmark contestant`

Run account selection, push, and equality check.

- [ ] **Step 3: Rerun preflight immediately before measurement**

Confirm free-space headroom and prerequisites. Stop with the isolated workspace intact if the check fails.

- [ ] **Step 4: Run source tests, smoke, and three release rounds**

Run the isolated Cargo wrapper for `test --locked --manifest-path
./probes/ferroui-probe/Cargo.toml`, then run the complete Pester suite and
`just framework-test ferroui`.

Expected: default Skia/ANGLE renderer, exact topology/protocol, validated durable result, and guarded cleanup with recovered-space report.

- [ ] **Step 5: Audit results and cleanup**

Use `jq` to verify three successful runs, phases, topology, hashes, event logs, toolchain/renderer metadata. Assert `.benchmark-work/ferroui` is absent and global Cargo/Rustup caches were untouched.

- [ ] **Step 6: Finalize expansion documentation**

Update README and the general benchmark design for cohort/date labeling, all five new contestants, explicit renderers, sequential-cache methodology, anchor result, and limitations. Keep the dated six-framework report and historical JSON unchanged.

- [ ] **Step 7: Run complete final verification**

Run: `Invoke-Pester -Path './harness/tests'; cargo test --locked --manifest-path './probes/probe-protocol/Cargo.toml'; git diff --check; git status --short`

Expected: all tests PASS, no whitespace errors, only intended FerroUI/result/final-doc changes remain, and no disposable framework work root remains.

- [ ] **Step 8: Commit and synchronize**

Commit message: `bench: complete sequential framework expansion`

Run `git swap auto`, push, and verify local/remote equality. Stop and report immediately if any synchronization step fails.
