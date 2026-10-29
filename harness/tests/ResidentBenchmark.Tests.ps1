$libraryPath = Join-Path $PSScriptRoot "..\resident-benchmark-lib.ps1"
. $libraryPath

Describe "resident benchmark orchestration helpers" {
  It "rotates framework order without changing membership" {
    $frameworks = @("tauri", "slint", "zgui", "dioxus-desktop")
    @(Get-RotatedFrameworkOrder -Frameworks $frameworks -Round 1) | Should Be $frameworks
    @(Get-RotatedFrameworkOrder -Frameworks $frameworks -Round 2) | Should Be @("slint", "zgui", "dioxus-desktop", "tauri")
    @(Get-RotatedFrameworkOrder -Frameworks $frameworks -Round 5) | Should Be $frameworks
  }

  It "reports median and range for odd and even samples" {
    $odd = Get-BenchmarkStatistics -Values @(9, 1, 5)
    $odd.median | Should Be 5
    $odd.minimum | Should Be 1
    $odd.maximum | Should Be 9

    $even = Get-BenchmarkStatistics -Values @(8, 2, 4, 6)
    $even.median | Should Be 5
  }

  It "summarizes only successful resident runs" {
    $phase = [pscustomobject]@{
      workingSetMb = 1; privateWorkingSetMb = 2; privateBytesMb = 3
      cpuSingleCorePercent = 4; cpuMachinePercent = 5
      gpuEngineAveragePercent = 6; gpuEnginePeakPercent = 7
      dedicatedGpuPeakMb = 8; sharedGpuPeakMb = 9
    }
    $runs = @(
      [pscustomobject]@{ framework = "probe"; status = "ok"; showLatencyMs = 10; hideLatencyMs = 11; phases = [pscustomobject]@{ hiddenIdle=$phase; visibleIdle=$phase; workload400=$phase; postHideIdle=$phase; postCycleIdle=$phase } },
      [pscustomobject]@{ framework = "probe"; status = "failed"; showLatencyMs = 999; hideLatencyMs = 999 }
    )
    $summary = New-ResidentBenchmarkSummary -Runs $runs -Frameworks @("probe")
    $summary.phases[0].metrics.privateWorkingSetMb.count | Should Be 1
    $summary.latency[0].showLatencyMs.median | Should Be 10
  }

  It "waits for one exact JSONL event after a line boundary" {
    $path = Join-Path $TestDrive "events.jsonl"
    @(
      '{"event":"ready-hidden","elapsedMs":1}',
      '{"event":"show-start","elapsedMs":2}',
      '{"event":"show-end","elapsedMs":3}'
    ) | Set-Content -LiteralPath $path -Encoding utf8

    $match = Wait-ProbeEvent -Path $path -Event "show-end" -AfterLine 1 -TimeoutSeconds 1
    $match.lineNumber | Should Be 3
    $match.value.elapsedMs | Should Be 3
  }
}
