# Rust UI Benchmark for Windows

A reproducible comparison of desktop UI stacks under the lifecycle of a
resident Windows quick launcher. The published historical cohort contains:

- Tauri/WebView2
- Slint
- zgui
- Dioxus Desktop/WebView2
- Dioxus Native on Blitz
- gpui-ce

Iced has joined the corrected unmanaged-window cohort. gpui-kit, KAS, Makepad,
and FerroUI remain planned as sequential expansions. Each one uses an isolated
Cargo home and target directory which is removed only after its durable result
passes validation, keeping peak disk use close to one framework build at a
time.

The production application that motivated the experiment is not a contestant.
Each reduced probe owns the same two-window scene and shared selection state,
so the experiment measures framework/runtime cost rather than product scope.

This repository is Windows-specific. The harness verifies native HWNDs and
uses Windows process, GPU engine, and GPU process-memory performance counters.

## Results at a glance

The following historical values are medians from three release rounds on the
same Windows 11 machine on 2026-10-28. Memory is process-tree Private Working
Set (PWS); CPU is workload CPU as a percentage of the whole
32-logical-processor machine; GPU is average engine utilization during the
workload; GPU memory is the workload peak dedicated/shared allocation. Lower
is better for every numeric column.

| Framework | Hidden PWS (MB) | Workload PWS (MB) | Workload CPU (%) | GPU avg (%) | GPU memory peak (MB) | Warm show / hide (ms) | Main takeaway |
|---|---:|---:|---:|---:|---:|---:|---|
| Tauri / WebView2 | 100.2 | 107.1 | 0.328 | **0.000** | 108.6 / 2.2 | 283.7 / **229.9** | Balanced WebView option: moderate memory, very low workload CPU/GPU, and fastest hide. |
| Slint | 33.2 | 60.7 | 0.983 | 5.378 | 75.3 / 23.2 | 353.9 / 288.2 | Second-lowest resident memory and clean hidden idle, but the highest measured workload GPU use. |
| zgui | 87.6 | 96.5 | 0.655 | 0.413 | 144.1 / 36.3 | **238.7** / 253.2 | Fastest warm show with mid-range memory, but relatively high GPU memory allocation. |
| Dioxus Desktop / WebView2 | 100.9 | 132.2 | 1.639 | 0.218 | 90.8 / 3.3 | Similar hidden WebView cost to Tauri, but higher workload memory/CPU and slower visibility transitions. |
| Dioxus Native / Blitz | 190.5 | 190.5 | **0.327** | **0.000** | 154.2 / 74.2 | 267.2 / 261.8 | Low workload CPU and responsive show, but the largest resident memory and GPU-memory footprint. |
| gpui-ce | **23.8** | **37.3** | 0.650 | 1.826 | **59.5 / 2.1** | 240.6 / 253.7 | Clear footprint leader and near-fastest show; hidden-state CPU observed after hide needs profiling. |

These numbers characterize this probe, machine, driver stack, and pinned
framework revisions—not universal framework rankings. A recorded GPU value of
zero means the Windows per-process counter saw no activity at this sampling
resolution; it does not mean that the framework never uses the GPU. See the
[`full report`](docs/2026-10-28-six-framework-resident-comparison.md) for
ranges, post-hide behavior, limitations, and interpretation.

## Repository layout

- `probes/`: independent probe crates plus the shared protocol crate;
- `harness/`: build, measurement, result-merge scripts, and Pester tests;
- `results/2026-10-28/`: untouched raw data from the original experiment;
- `results/2026-10-29/`: the audited Slint compatibility-anchor attempt;
- `docs/`: benchmark design, report, and extraction provenance.

Every probe has its own `Cargo.lock`. Direct framework inputs are additionally
pinned in its manifest: Slint 1.16.1, zgui commit `951a0ea3`, Dioxus Desktop
0.7.10, Dioxus Native/Blitz commit `fe33b778`, gpui-ce commit `5cac1478`, and
Tauri 2.12.5 (`tauri-build` 2.7.4).

## Protocol

Every probe starts hidden and remains alive until the harness sends `quit`.
One measured round performs:

1. hidden idle sampling;
2. warm show and visible idle sampling;
3. 400 shared-state updates, one every 20 ms;
4. warm hide, 15-second settlement, and hidden sampling;
5. 30 show/hide cycles and a final hidden sample.

The harness measures the whole process tree: Working Set, Private Working Set,
Private Bytes, CPU, GPU engine activity, GPU memory, process/renderer count,
artifact size, and end-to-end warm show/hide latency. See
[`docs/benchmark-design.md`](docs/benchmark-design.md) for the full contract.

## Requirements

- Windows 11;
- PowerShell 7;
- a Rust toolchain and Windows native build tools;
- Pester for the harness tests;
- `just` for the convenience recipes below.

## Build and test

From the repository root:

```powershell
just build
just test
```

The equivalent direct build command is:

```powershell
.\harness\build-all.ps1 -Configuration release
```

## Measure

Use a short debug lifecycle check after changing a probe or the harness:

```powershell
just smoke
```

Run the comparable three-round release experiment with:

```powershell
just measure
```

Local results are written under `results/local/`, which is ignored by Git.
For an explicitly numbered retry, combine `-Rounds 1` with `-RoundStart N`.
Use `harness/merge-resident-results.ps1` to assemble successful pairs while
retaining failed attempts for auditability.

For the disk-bounded expansion workflow, run exactly one framework at a time:

```powershell
just framework-test NAME
just framework-clean NAME
```

After the named probe is implemented and enabled, `framework-test` performs a
debug smoke run, a release build, three full release rounds, result validation,
and guarded cleanup. A failure preserves
`.benchmark-work/<framework>` and writes a terminal status JSON. The explicit
`framework-clean` recipe uses the same allow-listed path checks and is intended
for an accepted terminal outcome, not an incomplete result.

## Compatibility anchor status

The historical six-framework result remains unchanged. On 2026-10-29, Slint
1.16.1 was rebuilt from its committed source and lockfile in an isolated work
root and completed one debug smoke round plus three release rounds. All runs,
event logs, hashes, toolchain metadata, and environment identity checks were
valid, but the deterministic compatibility gate failed and therefore did not
clean the work root or authorize the expansion measurements.

The failed numeric medians were workload GPU utilization (+18.35%), warm show
latency (+42.17%), and warm hide latency (+38.88%) relative to the historical
medians. Window outer dimensions also differed while the asynchronous Grid
window manager was arranging and cloaking the two probe windows. This is more
than the one-metric retry allowance, so no automatic retry was run and the new
frameworks were not started. The durable evidence is in
[`slint-anchor.json`](results/2026-10-29/slint-anchor.json),
[`slint-anchor-comparison.json`](results/2026-10-29/slint-anchor-comparison.json),
and [`slint-anchor-status.json`](results/2026-10-29/slint-anchor-status.json).
Any later continuation must be described as a separate, not directly ranked
cohort unless a newly approved compatibility policy says otherwise.

An explicitly approved second attempt then excluded both fixed benchmark
window titles from komorebi before launch. A live-state check while the probe
process and windows existed found neither window in komorebi's managed tree.
Across all three rounds, the application-owned outer sizes were stable at
`715x514` for the main window and `1215x794` for the auxiliary window. This
confirms that the isolation works, while also proving that the historical
visible/post-hide topology (two komorebi-arranged `1252x652` windows) belongs
to a different window-management protocol.

The second attempt is therefore valid evidence for a new unmanaged-window
cohort, but it does not pass the strict historical gate. In addition to the
expected topology mismatch, four medians fell outside the symmetric 10%
compatibility band: workload CPU (+32.66%), workload GPU utilization
(+24.90%), dedicated GPU allocation (-16.20%, an improvement but still a
compatibility drift), and warm hide latency (+19.86%). Hidden and workload
private working set, shared GPU allocation, warm show latency, environment,
process count, and renderer count passed. Its evidence is in
[`slint-anchor-unmanaged-attempt-2.json`](results/2026-10-29/slint-anchor-unmanaged-attempt-2.json),
[`slint-anchor-unmanaged-attempt-2-comparison.json`](results/2026-10-29/slint-anchor-unmanaged-attempt-2-comparison.json),
and [`slint-anchor-unmanaged-attempt-2-status.json`](results/2026-10-29/slint-anchor-unmanaged-attempt-2-status.json).
After the durable files passed validation, the isolated Cargo home and target
were explicitly removed, recovering 3,625,500,672 bytes.

All expansion probes must use this unmanaged-window rule. Direct ranking
against the original six remains historical context only; a strict combined
ranking would require rerunning those six under the corrected rule.

### Iced unmanaged-window result

Iced 0.14.0 with its WGPU renderer completed a debug smoke run and three valid
release rounds on 2026-10-29. Its median hidden/workload private working sets
were 133.3/152.0 MB; workload machine CPU was 0.327%, average GPU engine use
was 1.054%, and warm show/hide latency was 329.911/222.939 ms. Both native
windows retained the expected unmanaged outer sizes at every checkpoint.

The validated evidence is in
[`iced-unmanaged-attempt-3.json`](results/2026-10-29/iced-unmanaged-attempt-3.json)
and its adjacent event/status artifacts. The first two smoke attempts are kept
as diagnostics for an Iced/Winit same-process HWND enumeration deadlock; the
successful probe restricts lookup to the two exact titles and verifies their
PID before changing visibility. Guarded cleanup then removed only the isolated
Iced work root and recovered 3,280,015,360 bytes.

## Historical result

The original 2026-10-28 result, failed attempts, and explicit retries are kept
under `results/2026-10-28/`. Read the
[`six-framework report`](docs/2026-10-28-six-framework-resident-comparison.md)
for the findings and limitations. The raw files intentionally retain paths
from the source repository; see [`docs/provenance.md`](docs/provenance.md).

The probe executable names and static fixture contain the original `komorebi`
identifier. They are preserved so the published result remains traceable to
the exact measured source; they are fixture labels, not dependencies on the
original application.

Before publishing this repository or accepting outside contributions, choose
and add an explicit open-source `LICENSE`.

