# Extraction provenance

This repository was extracted on 2026-10-29 from:

- source repository: `kkRelation/komorebi-shortcuts-tauri`
- source branch: `bench/six-framework-resident-benchmark`
- source commit: `4aa044b455d78a78345021ddb59a584fcf3a3991`

The six probe sources, protocol, harness logic, tests, report, and raw result
JSON files come from that commit. Repository-relative paths were reorganized
into `probes/`, `harness/`, `results/`, and `docs/`. The historical JSON files
were copied byte-for-byte and therefore retain their original artifact labels.

The earlier three-framework cold-start/static scripts and product-reference
measurements were intentionally not extracted because they depended on the
source product repository, a sibling Slint project, or another Git worktree.

