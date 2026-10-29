# Contributing

Contributions should preserve the benchmark contract before optimizing or
adding framework-specific behavior.

## Adding a framework

A new probe must:

1. create both required top-level windows before emitting `ready-hidden`;
2. use the exact titles `UI Framework Bench - Main` and
   `UI Framework Bench - Auxiliary Canvas`;
3. render the same 72-row main scene and 66-key auxiliary scene;
4. keep one shared selection value consumed by both windows;
5. accept `--event-log <path>` and the stdin commands implemented by
   `probe-protocol`;
6. remain alive while hidden and exit cleanly on `quit`;
7. pin direct framework inputs and commit its lockfile.

Add the probe to `harness/build-all.ps1` and `harness/measure-resident.ps1`,
then run the Pester tests and a debug smoke measurement before submitting a
full release result. Do not silently replace failed rounds: retain attempts
and use the merge tool for explicitly numbered retries.

Before this repository accepts third-party contributions, its owner must add
an explicit open-source license.

