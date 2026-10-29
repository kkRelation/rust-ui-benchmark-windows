# Rust UI Benchmark for Windows

A reproducible comparison of six desktop UI stacks under the lifecycle of a
resident Windows quick launcher:

- Tauri/WebView2
- Slint
- zgui
- Dioxus Desktop/WebView2
- Dioxus Native on Blitz
- gpui-ce

The production application that motivated the experiment is not a contestant.
Each reduced probe owns the same two-window scene and shared selection state,
so the experiment measures framework/runtime cost rather than product scope.

This repository is Windows-specific. The harness verifies native HWNDs and
uses Windows process, GPU engine, and GPU process-memory performance counters.

## Results at a glance

The following values are medians from three release rounds on the same Windows
11 machine. Memory is process-tree Private Working Set (PWS); CPU is workload
CPU as a percentage of the whole 32-logical-processor machine; GPU is average
engine utilization during the workload; GPU memory is the workload peak
dedicated/shared allocation. Lower is better for every numeric column.

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

- `probes/`: six independent probe crates plus the shared protocol crate;
- `harness/`: build, measurement, result-merge scripts, and Pester tests;
- `results/2026-10-28/`: untouched raw data from the original experiment;
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

