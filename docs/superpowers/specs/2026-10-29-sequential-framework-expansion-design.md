# Sequential framework expansion design

## Intent

Extend the Windows resident-UI benchmark beyond its six historical probes while
working within a small-disk constraint. Each new framework is built and measured
alone, its reproducibility artifacts are retained, and all disposable build and
dependency caches for that framework are removed before the next framework is
started.

The six results captured on 2026-10-28 remain an immutable historical cohort.
They are not rebuilt merely to add new contestants. One exact Slint rerun acts
as an environmental anchor between the historical cohort and the new runs.

## Goals

- Add probes in this order: Iced, gpui-kit, KAS, Makepad, FerroUI.
- Preserve the existing two-window scene, shared 400-step workload, lifecycle
  protocol, metrics, and three-round measurement rule.
- Keep peak disk use close to one framework's build footprint instead of the
  cumulative footprint of all frameworks.
- Retain enough source, lock, environment, and result information to rebuild
  any deleted executable later.
- Make cleanup explicit, narrowly scoped, validated, and safe on Windows.
- Distinguish historical and new measurement cohorts in reports.

## Non-goals

- Rebuilding all six historical probes when the Slint anchor is compatible.
- Updating the versions of the six historical probes.
- Treating renderer variants as the same contestant.
- Deleting the user's global Cargo cache, Rust toolchains, or caches belonging
  to unrelated repositories.
- Optimizing a framework until it no longer represents its normal production
  configuration.
- Replacing or rewriting the historical six-framework report and raw result.

## Constraints

- Windows 11 and PowerShell 7 remain the measurement platform.
- The disk cannot retain multiple frameworks' `target` directories or complete
  Cargo download caches concurrently.
- Every probe must satisfy the contract in `CONTRIBUTING.md`: two retained
  top-level windows, exact titles and dimensions, common scene, shared state,
  stdin protocol, event log, hidden residency, and clean quit.
- Direct framework dependencies must be exact-version or exact-revision pins,
  with a committed `Cargo.lock` in each probe.
- Cleanup must never target a workspace root, user profile, global Cargo home,
  Rust toolchain, unresolved variable, or wildcard path.

## Approaches considered

### 1. Sequential measurement with one historical anchor — selected

Rerun Slint 1.16.1 for three rounds, then build and measure each new framework
independently. Isolate and remove each framework's build/download cache after
its result is validated. This gives a useful drift check while respecting the
disk constraint and avoiding six redundant rebuilds.

### 2. Sequentially rerun all historical and new frameworks

This gives the strongest same-period comparison and can still fit the disk by
cleaning between frameworks, but it adds substantial build time, bandwidth, and
measurement time without a current indication that the recorded environment
has changed. It is reserved as a fallback if the anchor fails.

### 3. Add new results without an anchor

This is cheapest, but there is no empirical bridge from the 2026-10-28 cohort
to the new cohort. It is acceptable only for qualitative exploration, not for
the intended comparison report.

## Historical cohort and anchor gate

The existing `results/2026-10-28/2026-10-28-six-framework-resident.json` is
preserved byte-for-byte. It contains the protocol, environment, exact pins,
three rounds per framework, failed-attempt audit data, and final summary.

The anchor is the existing Slint probe pinned to version 1.16.1. It is rebuilt
from its committed source and lockfile and measured for three full release
rounds using the historical protocol:

- 10-second phase samples;
- 15-second post-hide settlement;
- 30 visibility cycles;
- two retained windows;
- 400 shared-state updates at 20 ms.

Before measuring, the runner records the current OS build, logical processor
count, CPU and GPU identities, GPU driver versions, and power plan. A material
identity mismatch stops the anchor comparison and is reported rather than
silently accepted.

The anchor gate is deterministic. Process topology must match exactly. For
each numeric key metric, the new three-round median passes when it is inside
the historical min-max range or its relative difference from the historical
median is at most 10 percent. When the historical median is zero, the new
median must also be zero. The key metrics are hidden and workload PWS,
workload whole-machine CPU, workload GPU average and memory peak, warm
show/hide latency, and post-hide idle.

If exactly one numeric metric fails, the anchor may be measured for one
explicitly numbered three-round retry after checking background load. The
retry must pass every metric; it is retained as an audited supplement rather
than silently replacing the first attempt. More than one failed metric, any
topology mismatch, or a failed retry fails the anchor gate.

If the anchor fails, the workflow stops after preserving the result and
diagnosing readily observable environment drift. It does not automatically
rebuild all six or begin the five new measurements. Continuing later as a
separate, unranked cohort requires an explicit user decision.

## New contestants

Each backend is a separately named contestant and receives an exact version or
revision pin:

1. Iced 0.14 with its WGPU renderer.
2. gpui-kit 0.8.1 using the complete application-facing kit, without optional
   WebView or JavaScript-shell features not needed by the benchmark scene.
3. KAS 0.17 with its normal WGPU desktop backend.
4. Makepad 1.0 with its normal Windows renderer.
5. FerroUI 0.4 with its default desktop Skia/ANGLE path.

Iced tiny-skia and FerroUI Vello are possible future renderer variants, not
fallback substitutions. If a public framework API cannot retain and toggle
both native windows, a minimal Windows adapter may call the native visibility
API, as the existing zgui and Dioxus Native probes do. The adapter and its
reason must be documented in the report.

## Per-framework disk lifecycle

Every build receives an allow-listed framework name and a dedicated ignored
work root under `.benchmark-work/<framework>/`:

- `cargo-home/` is assigned to `CARGO_HOME` for registry archives, unpacked
  crate sources, and Git dependency checkouts;
- `target/` is assigned to `CARGO_TARGET_DIR` for build intermediates and the
  final executable.

The globally installed `cargo`/`rustc` toolchain remains in the user's normal
Rustup location. The user's normal Cargo home is not modified or cleaned.

The lifecycle is:

1. Create the isolated work root and record free disk space.
2. Resolve dependencies and commit the probe's `Cargo.lock`.
3. Run formatting, checks/tests appropriate to the probe, a debug lifecycle
   smoke test, and then a release build.
4. Run three full release measurement rounds.
5. Validate that all three framework/round pairs succeeded and that required
   phases, topology, event logs, and summary fields are present.
6. Record the exact pin, lockfile hash, source commit, `rustc -vV`, `cargo -V`,
   environment, executable size, and executable SHA-256 before deletion.
7. Copy durable raw results and event logs outside `.benchmark-work`.
8. Resolve the cleanup target to an absolute path and verify that it is a
   direct child of the repository's `.benchmark-work` directory with the
   expected allow-listed framework name.
9. Remove only that verified framework work root. Confirm its removal and
   report the recovered free space.

If a build or measurement fails, the workflow stops and preserves the logs and
work root while the failure is diagnosed. It does not automatically advance
to the next framework. Once the user accepts an explicitly recorded terminal
outcome, the same validated cleanup runs before work resumes with another
framework. A `KeepWorkdir` diagnostic switch may suppress cleanup only when
explicitly selected.

FerroUI's isolated cache prevents cumulative growth, but its Skia toolchain may
still impose a larger single-framework peak. Free space is checked before its
build, and the workflow stops cleanly if the measured headroom is insufficient.

## Harness and repository changes

- Add one self-contained probe directory per new contestant.
- Extend the existing framework allow-lists and executable maps in the build
  and measurement scripts.
- Add single-framework commands that pass isolated `CARGO_HOME` and
  `CARGO_TARGET_DIR`; do not make the all-framework build the documented path
  for this machine.
- Add a safe orchestration command for one framework covering build, smoke,
  release measurement, validation, and cleanup.
- Keep cleanup as its own auditable operation and provide `KeepWorkdir` for
  failures under active investigation.
- Add `.benchmark-work/` to `.gitignore`.
- Generalize current top-level documentation from an exclusively
  six-framework project to a historical six-framework result plus expansion
  cohorts. Keep the dated historical report unchanged.
- Store each new raw result in a date- and framework-specific location so a
  partial expansion remains auditable.

## Result interpretation

The final report displays a cohort/date column. Historical values remain the
published 2026-10-28 medians. New candidates use their own three-round medians
and ranges. The Slint anchor is shown separately as a compatibility check; it
does not replace the historical Slint row.

Cross-cohort comparisons are allowed after the anchor passes, but differences
near either cohort's run-to-run range are described as ties or inconclusive.
The report does not claim that a one-framework anchor mathematically removes
all temporal drift.

## Verification and stopping conditions

Before a new framework is considered complete:

- the shared Pester harness tests pass;
- its probe builds from a fresh isolated Cargo home and target directory;
- the debug smoke lifecycle succeeds;
- three release rounds succeed under the common protocol;
- results contain all required phases and exactly two expected top-level
  windows;
- durable metadata and raw logs exist outside the disposable work root;
- the disposable work root is deleted and free space recovery is reported;
- unrelated working-tree changes and global caches remain untouched.

Any protocol deviation, missing round, unexpected renderer substitution,
unsafe cleanup target, insufficient disk headroom, or anchor failure stops the
workflow and is reported instead of being hidden or worked around silently.

## Builder discretion

The builder may choose internal Rust module structure, styling helpers, and the
exact PowerShell data structure used to register frameworks, provided the
public benchmark protocol, pins, cleanup boundary, and result audit trail above
remain unchanged.
