# gpui-kit Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add and measure the production-facing gpui-kit 0.8.1 stack as a separate GPUI-family contestant, then delete its isolated build/download caches.

**Architecture:** Reuse the proven gpui-ce probe's scene and async controller shape, but launch through gpui-kit initialization and `open_window`, retaining the kit-provided per-window root and theme/component infrastructure. The manifest depends on the facade kit only and does not enable the optional JavaScript shell or WebView crates.

**Tech Stack:** Rust 2024, `gpui-kit = "=0.8.1"` (pinned `gpui-pre` backend), shared `ui-bench-protocol`.

**Spec:** `docs/superpowers/specs/2026-10-29-sequential-framework-expansion-design.md`

## Global Constraints

- Requires successful completion of the foundation and Iced plans.
- Preserve the exact scene, titles, dimensions, one shared selection, and 400x20 ms workload.
- Use the application-facing gpui-kit facade/root; do not reduce the contestant to bare `gpui-base` or direct `gpui-pre`.
- Do not enable or initialize gpui-shell, QuickJS, or gpui-webview.
- Pin 0.8.1 and commit the resolved lockfile, including the exact gpui-pre snapshot selected by that release.
- Build and measure only in `.benchmark-work/gpui-kit`, then validated cleanup.
- Follow repository validation/commit/`git swap auto`/push/remote-equality rules after each task.

## Review Focus

- The implementation must actually initialize gpui-kit Root/theme infrastructure rather than accidentally reproducing the bare gpui-ce probe; Task 1 adds an explicit construction assertion/commented boundary and Task 3 reviews dependency metadata.
- Optional shell/WebView features must remain absent from the resolved graph; Tasks 1 and 3 inspect `cargo tree`/lock metadata.
- Both Root-wrapped windows must retain independent handles while reading one selection value; Task 1 tests controller state and Task 3 smoke-tests topology.
- Hidden-state timers introduced by kit components must be measured, not disabled specially; Task 3 preserves default behavior.
- gpui-kit and gpui-ce must remain separately named in results and prose; Tasks 2 and 3 test/document this.

---

### Task 1: Implement the gpui-kit probe

**Files:**
- Create: `probes/gpui-kit-probe/Cargo.toml`
- Create: `probes/gpui-kit-probe/src/main.rs`
- Create: `probes/gpui-kit-probe/src/scene.rs`
- Create: `probes/gpui-kit-probe/src/controller.rs`

**Interfaces:**
- `scene.rs` produces `MainView` and `AuxiliaryView` implementing the GPUI render contract inside gpui-kit's Root.
- `controller.rs` produces the stdin reader and async `run_controller` for retained handles.
- Binary framework identity is exactly `gpui-kit`.

- [ ] **Step 1: Write pure controller tests**

Test command-to-transition mapping, exact 400 updates, modulo-72 selection, shared propagation intent, cycle count, and quit. Keep GPUI window calls behind small controller operations so the state logic is testable.

- [ ] **Step 2: Add the exact manifest and initial compile boundary**

Pin `gpui-kit = "=0.8.1"`, shared protocol, JSON, and only the async channel dependency required by the controller. Import GPUI through the facade's re-export; do not add direct gpui-pre, shell, or WebView dependencies.

- [ ] **Step 3: Implement kit initialization and two hidden Root windows**

Follow the pinned release's `gpui_kit::init` and `gpui_kit::open_window` recipe. Retain the returned window/entity pairs, create both windows hidden with exact titles/sizes, and emit `ready-hidden` only after both calls succeed.

- [ ] **Step 4: Port the exact gpui-ce scene through kit Root**

Preserve the 72-row and 66-key scene and selected styling. Use kit theme/root setup but avoid extra demo widgets, FPS overlays, WebViews, or animations that are not part of the benchmark.

- [ ] **Step 5: Implement show/workload/hide/cycle/quit**

Use retained window handles and the framework event loop. Both windows consume every shared selection update; only one 20 ms timer sequence runs.

- [ ] **Step 6: Run format/tests and inspect features**

Use `invoke-framework-cargo.ps1 -Framework gpui-kit` for three argument
arrays: `fmt --manifest-path ./probes/gpui-kit-probe/Cargo.toml -- --check`,
`test --manifest-path ./probes/gpui-kit-probe/Cargo.toml`, and `tree
--manifest-path ./probes/gpui-kit-probe/Cargo.toml -e features`.

Expected: tests PASS; gpui-kit 0.8.1 and its pinned backend appear; shell, QuickJS, and WebView packages do not.

- [ ] **Step 7: Generate/commit the lockfile from the isolated workspace**

Use `.benchmark-work/gpui-kit/{cargo-home,target}`, then rebuild with `--locked` and verify the facade/backend pins.

- [ ] **Step 8: Commit and synchronize**

Commit message: `feat: add gpui-kit resident benchmark probe`

Run account selection, push, and local/remote equality check.

---

### Task 2: Activate gpui-kit

**Files:**
- Modify: `harness/framework-registry.ps1`
- Modify: `harness/tests/FrameworkRegistry.Tests.ps1`

**Interfaces:**
- Enables the predeclared `gpui-kit` definition after source and lockfile exist;
  its directory, binary, pin name, and pin stay unchanged.

- [ ] **Step 1: Add the failing exact-definition test**

Assert the definition follows Iced, is enabled, and does not alter `gpui-ce`.

- [ ] **Step 2: Verify failure, implement, and rerun**

Run before/after: `Invoke-Pester -Path './harness/tests/FrameworkRegistry.Tests.ps1'`

Expected: FAIL while the definition is disabled; PASS after activation.

- [ ] **Step 3: Run complete harness tests**

Run: `Invoke-Pester -Path './harness/tests'`

Expected: all tests PASS.

- [ ] **Step 4: Commit and synchronize**

Commit message: `feat: register gpui-kit benchmark contestant`

Run account selection, push, and commit equality check.

---

### Task 3: Measure and clean gpui-kit

**Files:**
- Create: `results/<measurement-date>/gpui-kit.json`
- Create: `results/<measurement-date>/gpui-kit-artifacts/round-1-events.jsonl`
- Create: `results/<measurement-date>/gpui-kit-artifacts/round-2-events.jsonl`
- Create: `results/<measurement-date>/gpui-kit-artifacts/round-3-events.jsonl`
- Modify: `README.md`

**Interfaces:**
- Consumes: `just framework-test gpui-kit`.
- Produces: validated gpui-kit results and no `.benchmark-work/gpui-kit`.

- [ ] **Step 1: Run source and harness verification**

Run the isolated Cargo wrapper for `test --locked --manifest-path
./probes/gpui-kit-probe/Cargo.toml`, then run the complete Pester suite.

Expected: PASS.

- [ ] **Step 2: Execute isolated smoke and three rounds**

Run: `just framework-test gpui-kit`

Expected: protocol succeeds, result validation passes, durable events/hashes exist, and guarded cleanup reports recovered bytes.

- [ ] **Step 3: Audit the production-stack boundary**

Record the resolved gpui-kit/gpui-pre versions and absence of optional shell/WebView components in durable metadata or the report. Do not compare it as if it were unrelated to gpui-ce; label it GPUI-family/application-kit.

- [ ] **Step 4: Verify JSON and cleanup**

Use `jq` for three successful runs and all required fields; assert `.benchmark-work/gpui-kit` is absent.

- [ ] **Step 5: Update README and run final checks**

Add the dated row/summary, then run `Invoke-Pester -Path './harness/tests'; git diff --check; git status --short`.

- [ ] **Step 6: Commit and synchronize**

Commit message: `bench: add gpui-kit resident measurements`

Run account selection, push, confirm equality, then begin the KAS plan.
