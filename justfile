set shell := ["pwsh", "-NoLogo", "-NoProfile", "-Command"]

build:
    & './harness/build-all.ps1' -Configuration release

build-debug:
    & './harness/build-all.ps1' -Configuration debug

test:
    Invoke-Pester -Path './harness/tests'

comparison-visuals:
    & './harness/generate-comparison-visuals.ps1'

smoke: build-debug
    & './harness/measure-resident.ps1' -Configuration debug -Smoke -OutputPath './results/local/smoke.json'

measure: build
    & './harness/measure-resident.ps1' -Configuration release -Rounds 3 -SampleSeconds 10 -PostHideSettleSeconds 15 -CycleCount 30 -OutputPath './results/local/resident.json'

framework-test name:
    & './harness/run-framework.ps1' -Framework '{{name}}'

framework-anchor:
    & './harness/run-framework.ps1' -Framework 'slint' -Anchor

framework-clean name:
    . './harness/framework-registry.ps1'; . './harness/framework-workspace.ps1'; $repoRoot = (Resolve-Path '.').Path; $workRoot = Join-Path $repoRoot '.benchmark-work\{{name}}'; Remove-BenchmarkFrameworkWorkspace -RepoRoot $repoRoot -Framework '{{name}}' -Path $workRoot

