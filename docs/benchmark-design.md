# Resident launcher benchmark design

## Goal

The historical 2026-10-28 cohort compares six Windows UI stacks under the
lifecycle of a resident quick launcher:

1. Tauri 2 (WebView2)
2. Slint
3. zgui
4. Dioxus Desktop (WebView2)
5. Dioxus Native (Blitz/WGPU)
6. gpui-ce

The corrected 2026-10-29 unmanaged-window cohort reruns the historical six and
adds six more contestants:

1. Tauri 2 (WebView2)
2. Slint
3. zgui
4. Dioxus Desktop (WebView2)
5. Dioxus Native (Blitz/WGPU)
6. gpui-ce
7. Iced 0.14.0 (WGPU/DX12)
8. gpui-kit 0.8.1 on gpui-pre 0.3.10
9. KAS 0.17.0 (WGPU/DX12)
10. Makepad Widgets 1.0.0 (native Windows D3D11)
11. FerroUI 0.4.0-preview.1 (default desktop Fluent/Skia/ANGLE)
12. egui/eframe 0.37.0 (WGPU)

The benchmark is a reduced business-equivalent probe, not a comparison between the full Tauri product and minimal demos. Cold startup remains supplementary. The primary result is the cost of a process that stays alive, presents warm windows, performs the same workload, and returns to the background.

## Fair scene and business state

Every probe creates the same two top-level windows before the first measurement:

- main: 700 x 480, search header and 72 shortcut rows;
- auxiliary: 1200 x 760, preview, 66-key atlas, navigation, numpad, and dossier panels.

Both windows start hidden and remain allocated for the whole run. One controller owns one selected-row value. A 400-step workload advances it every 20 ms. Both windows consume the same value; a framework may bridge that state into its renderers, but it may not run one independent workload per window.

The probe emits JSON Lines lifecycle events to a supplied log. Events use wall-clock ISO timestamps plus monotonic elapsed milliseconds. The measurement runner waits for events rather than guessing from process startup time.

## Lifecycle protocol

One measured round executes:

1. `ready-hidden`: both windows created, loaded, and hidden;
2. `hidden-idle`: 10-second concurrent resource sample;
3. `show-start` -> both windows visible; record warm-show latency when both native windows are observable;
4. `visible-idle`: 10-second concurrent resource sample;
5. `workload-start` -> 400 state changes at 20 ms; sample the full 8-second interval;
6. `workload-end`;
7. `hide-start` -> both windows hidden; record warm-hide latency when neither native window is observable;
8. wait 15 seconds for settling;
9. `post-hide-idle`: 10-second concurrent resource sample;
10. repeat 30 show/hide cycles and take a final hidden resource snapshot to expose retention or leaks;
11. exit cleanly.

At least three release rounds run in rotating framework order. Summary values report median and min-max range. The runner records failures without silently substituting a different scene or lifecycle.

For the corrected cohort, both exact window titles are verified as komorebi
ignore rules before launch. The two HWNDs must remain application-owned at
stable 715 x 514 and 1215 x 794 outer sizes at the hidden, visible, post-hide,
and post-cycle checkpoints. A result collected while a window manager arranges
or cloaks either window belongs to a different protocol.

## Metrics

Each resource phase records the full process tree:

- process and renderer counts, including WebView renderers where applicable;
- Working Set, Private Working Set, and Private Bytes;
- process-tree CPU normalized to one logical core and to the whole machine;
- GPU engine utilization, sampled once per second and summed over the tree's engine instances per timestamp;
- dedicated and shared GPU process memory;
- executable size.

CPU and GPU engine samples cover the same wall-clock interval. GPU memory is captured at the beginning and end of the interval; the result retains peak values because presentation and workload spikes matter. Show and hide latencies are separate from cold process startup.

## Reproducibility and interpretation

- All probes are release builds with lockfiles and exact versions or Git revisions.
- Dioxus Desktop and Tauri are WebView2 contenders; Dioxus Native uses Blitz.
  The expansion renderers are Iced WGPU/DX12, gpui-kit/gpui-pre, KAS
  WGPU/DX12, Makepad D3D11, FerroUI Skia/ANGLE, and egui/eframe WGPU.
- OS, GPU, driver, display topology, power state, WebView2 runtime, revisions, and commands are written into result metadata.
- The runner checks window count and dimensions before accepting a phase.
- Results from this machine describe relative cost under this protocol, not universal framework rankings.
- Native renderers, WebView renderers, and GPU drivers cache differently. Post-hide memory is therefore reported, not treated as an automatic leak; the 30-cycle delta supplies the retention signal.
- The historical managed-window cohort and corrected unmanaged-window cohort
  are not directly ranked. The Slint compatibility anchor documented the
  topology and metric drift that led to this separation; rerunning all six
  historical contestants under the corrected rule would be required for a
  combined ranking.

## Disk-bounded sequential workflow

Expansion frameworks run one at a time. Each receives
`.benchmark-work/<framework>/cargo-home` and
`.benchmark-work/<framework>/target`; no global Cargo or Rustup cache is used
for contestant dependencies or build output. The runner performs a debug smoke
test, locked release build, three release rounds, durable JSON/event-log
validation, and only then guarded deletion of that one allow-listed work root.
A failed build, measurement, validation, or anchor check preserves the work
root for diagnosis.

This bounds peak disk use to roughly one framework build plus its isolated
tooling. Exact peak size still varies substantially: native renderer source,
shader, Skia, and ANGLE builds can be much larger than a small Rust-only probe.
FerroUI additionally required an isolated `libclang.dll`; its prerequisite
tooling was kept inside its work root and removed with the validated build.

## Interpretation limits

- All twelve contestants were measured on one machine and date under the
  corrected unmanaged-window rule. These results form a separate comparable
  cohort and do not retroactively replace the historical six-framework report.
- A zero GPU sample means the Windows per-process counter observed no activity
  at the sampling resolution, not that a framework never uses the GPU.
- Framework defaults differ. FerroUI's default Fluent stack transitively
  includes markup/XAML build tooling even though the probe does not enable its
  facade XAML feature; this is retained rather than substituting a renderer.
- FerroUI 0.4 is only published as `0.4.0-preview.1`, so its result represents
  prerelease software. Its upstream ANGLE link warnings are recorded as a
  build limitation, while the executable and all measured lifecycle rounds
  completed successfully.
