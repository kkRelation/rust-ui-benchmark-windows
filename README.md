# Rust UI Benchmark for Windows

A reproducible comparison of desktop UI stacks under the lifecycle of a
resident Windows quick launcher. The published historical cohort contains:

- Tauri/WebView2
- Slint
- zgui
- Dioxus Desktop/WebView2
- Dioxus Native on Blitz
- gpui-ce

Iced, gpui-kit, KAS, Makepad, FerroUI, and egui are the six additional
contestants. All twelve frameworks were tested serially under the corrected
2026-10-29 unmanaged-window protocol, with an isolated Cargo home and target
directory removed only after its durable result passed validation. This keeps
peak disk use close to one framework build at a time.

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

### Corrected unmanaged-window total table

The following medians cover all twelve frameworks rerun for three release
rounds on 2026-10-29 after both exact benchmark titles were excluded from
komorebi. Entries in this table are comparable with each other, but should not
be mixed with the managed-window historical table above.

| Framework | Hidden PWS (MB) | Workload PWS (MB) | Workload CPU (%) | GPU avg (%) | Warm show / hide (ms) |
|---|---:|---:|---:|---:|---:|
| Tauri / WebView2 | 94.6 | 98.2 | 0.328 | **0.000** | 259.550 / 218.722 |
| Slint | 33.2 | 61.5 | 1.304 | 6.717 | 419.151 / 345.402 |
| zgui | 87.0 | 96.6 | 0.328 | 0.834 | **207.027** / 227.862 |
| Dioxus Desktop / WebView2 | 97.2 | 123.1 | 1.313 | 0.481 | 335.474 / 263.959 |
| Dioxus Native / Blitz | 189.5 | 189.9 | **0.325** | **0.000** | 266.597 / **199.261** |
| gpui-ce | 23.7 | 36.6 | 0.658 | 2.985 | 246.915 / 204.532 |
| Iced | 133.3 | 152.0 | 0.327 | 1.054 | 329.911 / 222.939 |
| gpui-kit | **19.0** | **24.8** | 0.656 | 1.618 | 284.224 / 308.871 |
| KAS | 151.7 | 188.4 | 0.328 | 11.699 | 246.977 / 237.816 |
| Makepad | 124.9 | 133.9 | 0.328 | 1.022 | 224.070 / 234.086 |
| FerroUI | 45.7 | 54.4 | 0.329 | 0.632 | 297.982 / 244.843 |
| egui | 184.9 | 189.0 | **0.325** | 0.496 | 253.600 / 230.375 |

These are machine- and scene-specific observations. In particular, the GPU
counter is sampled at Windows process/engine resolution, and the frameworks use
different retained-mode, rendering, and shader-cache strategies.

## Repository layout

- `probes/`: independent probe crates plus the shared protocol crate;
- `harness/`: build, measurement, result-merge scripts, and Pester tests;
- `results/2026-10-28/`: untouched raw data from the original experiment;
- `results/2026-10-29/`: audited compatibility-anchor and unmanaged-cohort results;
- `docs/`: benchmark design, report, and extraction provenance.

Every probe has its own `Cargo.lock`. Direct framework inputs are additionally
pinned in its manifest: Slint 1.16.1, zgui commit `951a0ea3`, Dioxus Desktop
0.7.10, Dioxus Native/Blitz commit `fe33b778`, gpui-ce commit `5cac1478`,
Tauri 2.12.5 (`tauri-build` 2.7.4), Iced 0.14.0, and gpui-kit 0.8.1
(resolving to gpui-pre 0.3.10). KAS, kas-wgpu, and kas-widgets are each
pinned to 0.17.0, with only WGPU's DX12 backend enabled. Makepad Widgets is
pinned to 1.0.0 and uses Makepad's native Windows D3D11 path. FerroUI is pinned
to the only published 0.4 crate, `0.4.0-preview.1`, using its default desktop
Fluent/Skia/ANGLE path. egui/eframe is pinned to 0.37.0 and explicitly uses
eframe's WGPU renderer.

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

### gpui-kit unmanaged-window result

gpui-kit 0.8.1, backed by gpui-pre 0.3.10, completed a debug smoke run and
three valid release rounds on 2026-10-29. Its median hidden/workload private
working sets were 19.0/24.8 MB; workload machine CPU was 0.656%, average GPU
engine use was 1.618%, and warm show/hide latency was 284.224/308.871 ms. Both
native windows retained the expected 715x514 and 1215x794 unmanaged outer
sizes at all four checkpoints in every round. The probe uses gpui-kit's normal
application, root-component, and asset initialization path; dependency and
source inspection found no browser shell, QuickJS, or WebView runtime.

The validated evidence is in
[`gpui-kit-unmanaged-attempt-2.json`](results/2026-10-29/gpui-kit-unmanaged-attempt-2.json)
and its adjacent event/status artifacts. The preceding
[`gpui-kit-unmanaged.json`](results/2026-10-29/gpui-kit-unmanaged.json) is kept
only as a diagnostic: gpui-pre created both initially hidden HWNDs at the full
1920x1012 work area, so that otherwise complete run is not comparable. The
accepted probe normalizes the two HWND outer rectangles with per-window DPI
before emitting `ready-hidden`. Guarded cleanup removed only the isolated
gpui-kit work root and recovered 7,488,868,352 bytes.

### KAS unmanaged-window result

KAS 0.17.0 with its normal WGPU/DX12 runner completed a debug smoke run and
three valid release rounds on 2026-10-29. Its median hidden/workload private
working sets were 151.7/188.4 MB; workload machine CPU was 0.328%, average GPU
engine use was 11.699%, and warm show/hide latency was 246.977/237.816 ms. The
workload GPU figure is notably high for this probe and renderer, but remains a
machine/scene observation rather than a general KAS claim. Both native windows
retained the exact 715x514 and 1215x794 outer sizes at every checkpoint.

The validated evidence is in
[`kas-unmanaged-attempt-2.json`](results/2026-10-29/kas-unmanaged-attempt-2.json)
and its adjacent event/status artifacts. The first [`kas.json`](results/2026-10-29/kas.json)
run is retained as a diagnostic: release rounds 1 and 3 passed, but round 2
caught KAS/Winit still performing the auxiliary window's initial show after
both HWNDs had been created. The accepted probe waits for both initial shows,
normalizes their DPI-aware outer rectangles, and requires 500 ms of stable
hidden state before emitting `ready-hidden`. Guarded cleanup removed only the
isolated KAS work root and recovered 3,313,897,472 bytes.

### Makepad unmanaged-window result

Makepad Widgets 1.0.0 with its native Windows D3D11 renderer completed a
debug smoke run and three valid release rounds on 2026-10-29. Its median
hidden/workload private working sets were 124.9/133.9 MB; workload machine CPU
was 0.328%, average GPU engine use was 1.022%, and warm show/hide latency was
224.070/234.086 ms. Hidden, post-hide, and post-cycle CPU/GPU medians were all
zero at the Windows sampling resolution. Both `MultiWindow` HWNDs retained the
exact 715x514 and 1215x794 outer sizes at every checkpoint.

The validated evidence is in
[`makepad.json`](results/2026-10-29/makepad.json) and its adjacent event/status
artifacts. Makepad 1.0.0 does not expose retained desktop visibility through
its public window API, so the probe uses a current-PID and exact-title Win32
adapter for show/hide, DPI-aware size normalization, and normal `WM_CLOSE`
shutdown. The scene still uses one Makepad process, one `MultiWindow`, and one
Rust selection value projected into both native windows; no WebView runtime is
present. Guarded cleanup removed only the isolated Makepad work root and
recovered 1,897,279,488 bytes.

### FerroUI unmanaged-window result

FerroUI `0.4.0-preview.1` with its default desktop Fluent theme and Skia/ANGLE
renderer completed a debug smoke run and three valid release rounds on
2026-10-29. Its median hidden/workload private working sets were 45.7/54.4 MB;
workload machine CPU was 0.329%, average GPU engine use was 0.632%, and warm
show/hide latency was 297.982/244.843 ms. Both retained native windows kept the
exact 715x514 and 1215x794 outer sizes at all four checkpoints in every round.

The validated evidence is in
[`ferroui.json`](results/2026-10-29/ferroui.json) and its adjacent event/status
artifacts. FerroUI has no stable 0.4.0 release, so this result is explicitly a
prerelease result. The default Fluent path transitively brings its markup/XAML
tooling, but the probe does not enable FerroUI's facade `xaml`, Vello, WinUI,
diagnostics, ReactiveUI, or MVVM variants. Its upstream ANGLE link emits
LNK4217 import warnings; the locked build, smoke run, all three rounds, and
clean shutdown nevertheless succeeded. Guarded cleanup removed only the
isolated FerroUI work root and recovered 15,976,652,800 bytes.

### egui unmanaged-window result

egui/eframe 0.37.0 with the WGPU renderer completed a debug smoke run and
three valid release rounds on 2026-10-29. Its median hidden/workload private
working sets were 184.9/189.0 MB; workload machine CPU was 0.325%, average GPU
engine use was 0.496%, and warm show/hide latency was 253.600/230.375 ms. Both
native viewports retained the exact 715x514 and 1215x794 outer sizes at all
four checkpoints in every round. Hidden, visible-idle, post-hide, and
post-cycle CPU/GPU medians were zero at the Windows sampling resolution.

The validated evidence is in
[`egui.json`](results/2026-10-29/egui.json) and its adjacent event/status
artifacts. The probe uses eframe's root viewport plus
`show_viewport_deferred` for the auxiliary window, one shared Rust selection
value, and an explicit WGPU renderer selection. A current-PID and exact-title
Win32 adapter synchronizes retained visibility using the same unmanaged-window
contract as the other expansion probes. The 14.2 MB executable and locked
dependency graph were identical across all rounds. Guarded cleanup removed
only the isolated egui work root and recovered 3,520,892,928 bytes.

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

