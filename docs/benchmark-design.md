# Six-framework resident launcher benchmark design

## Goal

Compare six Windows UI stacks under the lifecycle of a resident quick launcher:

1. Tauri 2 (WebView2)
2. Slint
3. zgui
4. Dioxus Desktop (WebView2)
5. Dioxus Native (Blitz/WGPU)
6. gpui-ce

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

## Metrics

Each resource phase records the full process tree:

- process and WebView renderer counts;
- Working Set, Private Working Set, and Private Bytes;
- process-tree CPU normalized to one logical core and to the whole machine;
- GPU engine utilization, sampled once per second and summed over the tree's engine instances per timestamp;
- dedicated and shared GPU process memory;
- executable size.

CPU and GPU engine samples cover the same wall-clock interval. GPU memory is captured at the beginning and end of the interval; the result retains peak values because presentation and workload spikes matter. Show and hide latencies are separate from cold process startup.

## Reproducibility and interpretation

- All probes are release builds with lockfiles and exact versions or Git revisions.
- Dioxus Desktop and Tauri are WebView2 contenders; Dioxus Native is the Blitz native renderer contender.
- OS, GPU, driver, display topology, power state, WebView2 runtime, revisions, and commands are written into result metadata.
- The runner checks window count and dimensions before accepting a phase.
- Results from this machine describe relative cost under this protocol, not universal framework rankings.
- Native renderers, WebView renderers, and GPU drivers cache differently. Post-hide memory is therefore reported, not treated as an automatic leak; the 30-cycle delta supplies the retention signal.
