# Sequential Benchmark Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a safe single-framework build/measure/archive/cleanup workflow and validate the historical cohort with a three-round Slint anchor.

**Architecture:** A shared PowerShell registry becomes the source of framework paths, binaries, and pins. A single-framework orchestrator allocates `.benchmark-work/<framework>/{cargo-home,target}`, invokes the existing build and measurement machinery against that target, validates and enriches durable results, and only then calls a path-guarded cleanup function. Anchor comparison remains a separate pure-data command so it can be tested without launching a GUI.

**Tech Stack:** PowerShell 7, Pester, Cargo/Rust, existing JSONL probe protocol, `just`, Windows CIM/performance counters.

**Spec:** `docs/superpowers/specs/2026-10-29-sequential-framework-expansion-design.md`

## Global Constraints

- Preserve `results/2026-10-28/2026-10-28-six-framework-resident.json` byte-for-byte.
- Never delete outside the resolved repository child `.benchmark-work/<allow-listed-framework>`.
- Never modify or clean the user's global Cargo home or Rustup toolchains.
- The anchor is exactly Slint 1.16.1, three release rounds, 10-second samples, 15-second settlement, and 30 cycles.
- Stop on anchor failure; do not begin a new framework automatically.
- Preserve unrelated working-tree changes.
- After each completed repository-changing task: validate, commit, run `git swap auto`, push, and confirm local/remote commits match; stop on any failure.

## Review Focus

- A framework name containing traversal or separators must be rejected before any directory is created or removed; Task 2 tests this.
- A cleanup path that is the repository root, `.benchmark-work` itself, a sibling, or a symlink/junction escape must be rejected; Task 2 tests this.
- Failed or incomplete result JSON must never trigger cleanup; Tasks 3 and 5 test this.
- Existing callers that omit isolated paths must continue to use each probe's normal `target` directory; Task 3 tests this compatibility.
- A historical zero metric must require a new zero median, while one nonzero historical metric uses range-or-10-percent logic; Task 4 tests both.

---

### Task 1: Central framework registry

**Files:**
- Create: `harness/framework-registry.ps1`
- Create: `harness/tests/FrameworkRegistry.Tests.ps1`
- Modify: `harness/build-all.ps1:1-18`
- Modify: `harness/measure-resident.ps1:1-35`

**Interfaces:**
- Produces: `Get-BenchmarkFrameworkDefinitions -> [ordered] IDictionary`
- Produces: `Get-BenchmarkFrameworkDefinition -Name <string> -> PSCustomObject`
- Each definition exposes `Name`, `Directory`, `Binary`, `PinName`, `Pin`, and
  `Enabled`.
- The registry predeclares all five approved candidates with `Enabled = $false`;
  the historical six remain enabled. Build/measure defaults include only
  enabled definitions, while workspace validation accepts every declared name.
- Existing scripts consume the registry and validate names at runtime instead of duplicating `ValidateSet` and maps.

- [ ] **Step 1: Write failing registry tests**

Add Pester cases asserting that the registry contains the original six enabled
in their current order; the five planned names exist disabled in approved
order; Slint resolves to `slint-probe`,
`komorebi-slint-framework-bench.exe`, and pin `1.16.1`; and an unknown name
throws before use.

- [ ] **Step 2: Run the focused tests and verify failure**

Run: `Invoke-Pester -Path './harness/tests/FrameworkRegistry.Tests.ps1'`

Expected: FAIL because `framework-registry.ps1` and its functions do not exist.

- [ ] **Step 3: Implement the registry**

Define the two interfaces above in `harness/framework-registry.ps1`. Keep all
six existing names, paths, binaries, and pins unchanged; Tauri's pin is
`2.12.5` and its pin name is `tauri`. Predeclare disabled Iced, gpui-kit, KAS,
Makepad, and FerroUI definitions using the names/paths/pins in their plans.

- [ ] **Step 4: Replace duplicated definitions in build and measure scripts**

Dot-source the registry, default `-Framework` from enabled keys, reject an
explicit disabled definition in build/measure commands, and generate the
result `pins` object from enabled selected definitions rather than a hard-coded
block.

- [ ] **Step 5: Run focused and existing harness tests**

Run: `Invoke-Pester -Path './harness/tests/FrameworkRegistry.Tests.ps1','./harness/tests/ResidentBenchmark.Tests.ps1'`

Expected: all tests PASS.

- [ ] **Step 6: Commit and synchronize**

Commit message: `refactor: centralize benchmark framework registry`

Then run `git swap auto`, push the current branch, and verify `git rev-parse HEAD` equals the remote tracking commit.

---

### Task 2: Isolated work roots and guarded cleanup

**Files:**
- Create: `harness/framework-workspace.ps1`
- Create: `harness/invoke-framework-cargo.ps1`
- Create: `harness/tests/FrameworkWorkspace.Tests.ps1`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: `Get-BenchmarkFrameworkDefinition -Name` from Task 1.
- Produces: `New-BenchmarkFrameworkWorkspace -RepoRoot <string> -Framework <string> -> PSCustomObject` with `Root`, `CargoHome`, `TargetDirectory`, and `FreeBytesBefore`.
- Produces: `Resolve-SafeBenchmarkWorkRoot -RepoRoot <string> -Framework <string> -Path <string> -> string`.
- Produces: `Remove-BenchmarkFrameworkWorkspace -RepoRoot <string> -Framework <string> -Path <string> -> PSCustomObject` with `RemovedPath`, `FreeBytesBefore`, `FreeBytesAfter`, and `RecoveredBytes`.
- `invoke-framework-cargo.ps1 -Framework <string> -CargoArguments <string[]>`
  creates/reuses the declared framework workspace, assigns its Cargo home and
  target directory only for the child Cargo process, and returns Cargo's exit
  code without cleaning.

- [ ] **Step 1: Write failing workspace tests**

Use `$TestDrive` as a fake repository and test creation of exactly
`<repo>/.benchmark-work/slint/cargo-home` and `target`. Assert a declared but
disabled candidate such as Iced is allowed for workspace creation. Add
rejection cases for `../`, absolute siblings, the repo root,
`.benchmark-work`, a mismatched framework child, and—when Windows permits
creating one—a junction whose final target escapes the fake repository.

- [ ] **Step 2: Run the focused tests and verify failure**

Run: `Invoke-Pester -Path './harness/tests/FrameworkWorkspace.Tests.ps1'`

Expected: FAIL because workspace functions do not exist.

- [ ] **Step 3: Implement workspace creation and path validation**

Resolve all paths with .NET absolute path APIs. Require the final cleanup path to equal the canonical direct child `<repo>/.benchmark-work/<validated-name>`, reject reparse-point escapes, and use only `Remove-Item -LiteralPath` after validation.

- [ ] **Step 4: Implement the isolated Cargo wrapper**

Validate the declared framework name, allocate its workspace, start Cargo via
`System.Diagnostics.ProcessStartInfo` with child-only `CARGO_HOME` and
`CARGO_TARGET_DIR`, forward stdout/stderr and the supplied argument array
without string evaluation, and return/throw on its exact exit status.

- [ ] **Step 5: Add the ignored work root**

Add `/.benchmark-work/` to `.gitignore`; do not broaden existing ignore rules.

- [ ] **Step 6: Run focused tests and diff safety checks**

Run: `Invoke-Pester -Path './harness/tests/FrameworkWorkspace.Tests.ps1'; git diff --check`

Expected: all tests PASS and `git diff --check` produces no output.

- [ ] **Step 7: Commit and synchronize**

Commit message: `feat: isolate and safely clean framework workspaces`

Run the required `git swap auto`, push, and local/remote commit check.

---

### Task 3: Build and measure from an isolated target while preserving logs

**Files:**
- Modify: `harness/build-all.ps1`
- Modify: `harness/measure-resident.ps1`
- Modify: `harness/tests/ResidentBenchmark.Tests.ps1`
- Create: `harness/tests/IsolatedPaths.Tests.ps1`

**Interfaces:**
- Adds to `build-all.ps1`: optional `-CargoHome <string>` and `-TargetDirectory <string>`.
- Adds to `measure-resident.ps1`: optional `-TargetDirectory <string>` and `-ArtifactDirectory <string>`.
- Result run objects gain `eventLog`, `executableSha256`, and `lockfileSha256`.
- Result root gains `toolchain.rustcVerbose` and `toolchain.cargoVersion`.

- [ ] **Step 1: Write failing isolated-path tests**

Mock Cargo/process execution where needed and assert: provided paths become `CARGO_HOME`/Cargo target paths; omitted paths retain `probes/<probe>/target/<configuration>`; the environment is restored after a build failure; and executable lookup uses the supplied target directory.

- [ ] **Step 2: Add failing artifact-preservation tests**

Exercise a fixture event log and assert the durable path is `<ArtifactDirectory>/<framework>/round-<N>-events.jsonl`, the run object references it, and temporary data can be removed without losing that file.

- [ ] **Step 3: Run tests and verify failure**

Run: `Invoke-Pester -Path './harness/tests/IsolatedPaths.Tests.ps1','./harness/tests/ResidentBenchmark.Tests.ps1'`

Expected: FAIL on missing parameters and metadata.

- [ ] **Step 4: Implement isolated build paths**

Temporarily assign `CARGO_HOME` only when supplied, pass `--target-dir` only when supplied, and restore the prior environment in `finally`. Do not change the default path behavior.

- [ ] **Step 5: Implement isolated executable lookup and durable artifacts**

Resolve the binary from `-TargetDirectory` when present. Copy each completed or failed round's event JSONL into `-ArtifactDirectory` before deleting the temporary directory. Compute SHA-256 for the executable and probe lockfile while they exist, and record the toolchain strings once per result.

- [ ] **Step 6: Run focused and complete harness tests**

Run: `Invoke-Pester -Path './harness/tests'`

Expected: all tests PASS.

- [ ] **Step 7: Commit and synchronize**

Commit message: `feat: support isolated benchmark build artifacts`

Run the required account selection, push, and local/remote commit check.

---

### Task 4: Deterministic Slint anchor comparison

**Files:**
- Create: `harness/anchor-comparison-lib.ps1`
- Create: `harness/compare-anchor.ps1`
- Create: `harness/tests/AnchorComparison.Tests.ps1`

**Interfaces:**
- Produces: `Compare-AnchorMetric -HistoricalStatistics <object> -CurrentStatistics <object> -Name <string> -> PSCustomObject`.
- Produces: `Compare-ResidentAnchor -Historical <object> -Current <object> -Framework <string> -> PSCustomObject` with `status`, `failedMetricCount`, `retryEligible`, `topologyMatch`, and `metrics`.
- `compare-anchor.ps1` accepts `-HistoricalPath`, `-CurrentPath`, `-Framework`, and `-OutputPath`, writes JSON, and exits nonzero unless status is `pass`.

- [ ] **Step 1: Write failing metric tests**

Cover inside-range pass, outside-range but <=10% pass, >10% fail, historical zero/current zero pass, historical zero/current nonzero fail, and null/missing metric fail.

- [ ] **Step 2: Write failing aggregate tests**

Use compact fixture objects to assert exact topology is required, zero failures passes, exactly one numeric failure sets `retryEligible = $true`, two failures set it false, and topology failure sets it false.

- [ ] **Step 3: Run tests and verify failure**

Run: `Invoke-Pester -Path './harness/tests/AnchorComparison.Tests.ps1'`

Expected: FAIL because comparison functions do not exist.

- [ ] **Step 4: Implement metric and aggregate comparison**

Compare the spec's hidden/workload PWS, workload machine CPU, workload GPU average, dedicated/shared GPU peaks, show/hide latency, and post-hide CPU. Compare process count, renderer count, window titles, and dimensions as topology, excluding volatile PIDs.

- [ ] **Step 5: Implement the command wrapper and exit behavior**

Write the complete audit JSON even on failure. Exit `0` for pass, `2` for exactly one retry-eligible metric, and `1` for all other failures.

- [ ] **Step 6: Run focused and complete tests**

Run: `Invoke-Pester -Path './harness/tests/AnchorComparison.Tests.ps1'; Invoke-Pester -Path './harness/tests'`

Expected: all tests PASS.

- [ ] **Step 7: Commit and synchronize**

Commit message: `feat: add historical anchor compatibility gate`

Run the required account selection, push, and local/remote commit check.

---

### Task 5: Single-framework orchestration and result validation

**Files:**
- Create: `harness/framework-run-lib.ps1`
- Create: `harness/run-framework.ps1`
- Create: `harness/tests/FrameworkRun.Tests.ps1`
- Modify: `justfile`

**Interfaces:**
- Produces: `Test-FrameworkResult -Result <object> -Framework <string> -ExpectedRounds <int> -> PSCustomObject` with `Valid` and `Errors`.
- `run-framework.ps1` accepts `-Framework`, `-Anchor`, `-KeepWorkdir`, and
  `-OutputDirectory`; tests mock its build/measurement dependencies instead of
  exposing a production bypass switch.
- Adds recipes: `framework-test name`, `framework-anchor`, and `framework-clean name`.

- [ ] **Step 1: Write failing result-validation tests**

Assert that validation requires exactly three successful distinct rounds, every required phase, both exact window titles in all topology checkpoints, event logs that exist outside `.benchmark-work`, hashes, toolchain metadata, and no failed runs.

- [ ] **Step 2: Write failing orchestration tests**

Mock workspace/build/measure/compare/cleanup calls and assert their order. Assert cleanup happens only after valid success, does not happen after build/measurement/validation/anchor failure, and is skipped with `-KeepWorkdir`.

- [ ] **Step 3: Run focused tests and verify failure**

Run: `Invoke-Pester -Path './harness/tests/FrameworkRun.Tests.ps1'`

Expected: FAIL because orchestration functions do not exist.

- [ ] **Step 4: Implement result validation**

Keep it pure over a result object plus filesystem existence checks. Return all validation errors in one object; do not delete or mutate anything.

- [ ] **Step 5: Implement the orchestrator**

Create the isolated workspace, record disk space, build debug, run smoke, build release, run three release rounds, validate, optionally run the anchor gate, then clean. On any error write a terminal status JSON beside the requested output and stop with the workspace intact.

- [ ] **Step 6: Add single-framework recipes**

Make `framework-test name` call the orchestrator, `framework-anchor` call it with Slint and `-Anchor`, and `framework-clean name` call only the guarded cleanup function. Keep existing recipes for compatibility but document the single-framework path later.

- [ ] **Step 7: Run complete tests**

Run: `Invoke-Pester -Path './harness/tests'`

Expected: all tests PASS.

- [ ] **Step 8: Commit and synchronize**

Commit message: `feat: orchestrate one framework with validated cleanup`

Run the required account selection, push, and local/remote commit check.

---

### Task 6: Execute and evaluate the Slint anchor

**Files:**
- Create: `results/<measurement-date>/slint-anchor.json`
- Create: `results/<measurement-date>/slint-anchor-comparison.json`
- Create: `results/<measurement-date>/slint-anchor-artifacts/round-1-events.jsonl`
- Create: `results/<measurement-date>/slint-anchor-artifacts/round-2-events.jsonl`
- Create: `results/<measurement-date>/slint-anchor-artifacts/round-3-events.jsonl`
- Modify: `README.md`

**Interfaces:**
- Consumes: `just framework-anchor` from Task 5.
- Produces: a passing compatibility audit required by every later probe plan.

- [ ] **Step 1: Run all non-GUI verification before measurement**

Run: `Invoke-Pester -Path './harness/tests'; cargo test --locked --manifest-path './probes/probe-protocol/Cargo.toml'`

Expected: all tests PASS.

- [ ] **Step 2: Record current free space and execute the anchor**

Run: `just framework-anchor`

Expected: debug smoke succeeds, three release rounds succeed, the anchor comparison exits `0`, and the Slint work root is removed only after durable artifacts exist.

- [ ] **Step 3: Verify cleanup and durable results**

Assert `.benchmark-work/slint` does not exist, the result contains exactly three successful Slint rounds, all event logs exist, hashes/toolchain metadata are present, and the historical JSON hash is unchanged from before Task 6.

- [ ] **Step 4: Handle a retry-eligible result if necessary**

If the comparison exits `2`, stop, inspect background load, and ask before running one explicitly numbered three-round retry. If it exits `1`, stop and report; do not execute any new probe plan.

- [ ] **Step 5: Document the cohort gate**

Update README with the anchor date, comparison result, durable result paths, and the fact that the old six remain the historical cohort. Do not change the dated historical report.

- [ ] **Step 6: Run final foundation verification**

Run: `Invoke-Pester -Path './harness/tests'; git diff --check; git status --short`

Expected: tests PASS, no whitespace errors, only intended source/result/doc changes remain.

- [ ] **Step 7: Commit and synchronize**

Commit message: `test: validate historical cohort with slint anchor`

Run `git swap auto`, push, verify the local and remote commits match, and only then begin the Iced plan.
