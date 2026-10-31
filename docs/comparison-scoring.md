# Comparison visualization and scoring

The comparison uses two complementary views:

1. a ranking heatmap for exact per-dimension and overall placement;
2. one seven-axis radar per framework for the shape of its strengths and weaknesses.

Thirteen radars are never overlaid. Overlaying that many polygons obscures both
labels and boundaries, while a single radar per framework keeps the same scale
and axis order for visual comparison.

## Seven axes

All raw metrics are lower-is-better:

- **RAM**: equal mean of the hidden-PWS and workload-PWS rank scores;
- **CPU**: workload whole-machine CPU;
- **GPU activity**: workload average GPU engine use;
- **VRAM**: workload peak dedicated GPU allocation;
- **Shared GPU memory**: workload peak system-memory-backed GPU allocation;
- **Warm show**: end-to-end warm-show latency;
- **Warm hide**: end-to-end warm-hide latency.

PWS is used for the RAM axis because it represents private pages resident in
physical memory. Total Working Set includes shareable pages that can be counted
more than once across a process tree, while Private Bytes measures committed
address space rather than resident RAM. Both remain available in the raw
benchmark results, but neither is added to PWS to manufacture a “total RAM”
score.

Shared GPU memory is a separate seventh axis. On Windows it is backed by system
memory and is therefore labelled separately rather than presented as VRAM.

## Cohort-relative score

For each lower-is-better raw metric, frameworks are sorted ascending. Ties get
their average rank. Rank is converted to a 0–100 score:

```text
score = 100 × (framework_count - average_tie_rank) / (framework_count - 1)
```

The best value scores 100 and the worst scores 0. This is a percentile-style
cohort score, not an absolute performance grade. Adding another framework can
change existing scores even when their raw measurements do not change.

The default composite score is the weighted arithmetic mean of the seven axis
scores. Every default weight is 1. The **weakness floor** is the lowest axis
score and exposes a severe weakness that an average could hide.

## Why polygon area is not the ranking

Radar area is useful visual texture but is not a stable aggregate measure:

- the area changes when the same axes are reordered;
- adjacent-axis interactions affect area even though no such interaction was
  measured;
- one long vertex can visually compensate for a near-zero vertex.

The radar therefore displays the seven independently computed scores, while the
composite uses an order-independent weighted mean.

## Hardware-capacity context

Each radar card reports:

- workload PWS as a percentage of 32 GiB system RAM;
- workload peak dedicated allocation as a percentage of 8 GiB VRAM;
- workload peak shared GPU allocation in MB.

These are context rather than score inputs. The measured footprints are small
relative to 32/8 GiB, so a direct `100 - capacity cost` ability score would put
nearly every framework close to 100 and erase useful differences. Capacity cost
is still valuable when applying a hard deployment budget.

## Regeneration and custom weights

Generate the default visuals:

```powershell
just comparison-visuals
```

Generate a latency-focused variant in another directory:

```powershell
& .\harness\generate-comparison-visuals.ps1 `
  -OutputDirectory '.\results\local\latency-visuals' `
  -Weights @{ Ram = 1; Cpu = 1; Gpu = 1; Vram = 1; SharedGpu = 1; Show = 3; Hide = 3 }
```

The generator emits the heatmap, composite ranking, thirteen independent radar
SVGs, and `comparison-data.json`. It uses dependency-free SVG rather than
Apache ECharts because GitHub README files do not execute the JavaScript needed
for an interactive ECharts chart. The exported JSON can still be passed to
ECharts later for a website or dashboard.
