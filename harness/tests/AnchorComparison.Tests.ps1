$libraryPath = Join-Path $PSScriptRoot "..\anchor-comparison-lib.ps1"
. $libraryPath

function New-AnchorStatistics {
  param([double]$Median = 10, [double]$Minimum = 9, [double]$Maximum = 11)
  [pscustomobject]@{ count = 3; median = $Median; minimum = $Minimum; maximum = $Maximum }
}

function New-AnchorFixture {
  param(
    [hashtable]$Overrides = @{},
    [int]$MainWidth = 715,
    [string]$PowerPlan = "fixture-plan"
  )

  function Get-FixtureStatistics {
    param([string]$Name, [double]$DefaultMedian = 10)
    if ($Overrides.ContainsKey($Name)) {
      $value = [double]$Overrides[$Name]
      return New-AnchorStatistics -Median $value -Minimum $value -Maximum $value
    }
    if ($DefaultMedian -eq 0) {
      return New-AnchorStatistics -Median 0 -Minimum 0 -Maximum 0
    }
    New-AnchorStatistics
  }

  $hiddenMetrics = [pscustomobject]@{
    privateWorkingSetMb = Get-FixtureStatistics "hiddenIdle.privateWorkingSetMb"
  }
  $workloadMetrics = [pscustomobject]@{
    privateWorkingSetMb = Get-FixtureStatistics "workload400.privateWorkingSetMb"
    cpuMachinePercent = Get-FixtureStatistics "workload400.cpuMachinePercent"
    gpuEngineAveragePercent = Get-FixtureStatistics "workload400.gpuEngineAveragePercent"
    dedicatedGpuPeakMb = Get-FixtureStatistics "workload400.dedicatedGpuPeakMb"
    sharedGpuPeakMb = Get-FixtureStatistics "workload400.sharedGpuPeakMb"
  }
  $postHideMetrics = [pscustomobject]@{
    cpuMachinePercent = Get-FixtureStatistics "postHideIdle.cpuMachinePercent" 0
  }
  $phase = [pscustomobject]@{ processCount = 1; rendererCount = 0 }
  $mainWindow = [pscustomobject]@{
    Title = "UI Framework Bench - Main"; Visible = $true; Width = $MainWidth; Height = 514
  }
  $auxWindow = [pscustomobject]@{
    Title = "UI Framework Bench - Auxiliary Canvas"; Visible = $true; Width = 1215; Height = 794
  }
  $windows = @($auxWindow, $mainWindow)

  [pscustomobject]@{
    environment = [pscustomobject]@{
      osVersion = "10.0.fixture"
      logicalProcessors = 8
      cpu = @("Fixture CPU")
      gpu = @([pscustomobject]@{ name = "Fixture GPU"; driverVersion = "1.2.3" })
      powerPlan = $PowerPlan
    }
    runs = @(
      [pscustomobject]@{
        framework = "slint"
        status = "ok"
        phases = [pscustomobject]@{
          hiddenIdle = $phase; visibleIdle = $phase; workload400 = $phase
          postHideIdle = $phase; postCycleIdle = $phase
        }
        topology = [pscustomobject]@{
          hidden = $windows; visible = $windows; postHide = $windows; postCycle = $windows
        }
      }
    )
    summary = [pscustomobject]@{
      phases = @(
        [pscustomobject]@{ framework = "slint"; phase = "hiddenIdle"; metrics = $hiddenMetrics },
        [pscustomobject]@{ framework = "slint"; phase = "workload400"; metrics = $workloadMetrics },
        [pscustomobject]@{ framework = "slint"; phase = "postHideIdle"; metrics = $postHideMetrics }
      )
      latency = @(
        [pscustomobject]@{
          framework = "slint"
          showLatencyMs = Get-FixtureStatistics "latency.showLatencyMs"
          hideLatencyMs = Get-FixtureStatistics "latency.hideLatencyMs"
        }
      )
    }
  }
}

Describe "anchor metric comparison" {
  It "passes a current median inside the historical range" {
    $result = Compare-AnchorMetric `
      -HistoricalStatistics (New-AnchorStatistics) `
      -CurrentStatistics (New-AnchorStatistics -Median 10.5 -Minimum 10.5 -Maximum 10.5) `
      -Name "fixture"
    $result.status | Should Be "pass"
    $result.rule | Should Be "historical-range"
  }

  It "passes outside the range within ten percent of the historical median" {
    $result = Compare-AnchorMetric `
      -HistoricalStatistics (New-AnchorStatistics -Median 100 -Minimum 99 -Maximum 101) `
      -CurrentStatistics (New-AnchorStatistics -Median 109 -Minimum 109 -Maximum 109) `
      -Name "fixture"
    $result.status | Should Be "pass"
    $result.rule | Should Be "relative-10-percent"
  }

  It "fails outside the range beyond ten percent" {
    $result = Compare-AnchorMetric `
      -HistoricalStatistics (New-AnchorStatistics -Median 100 -Minimum 99 -Maximum 101) `
      -CurrentStatistics (New-AnchorStatistics -Median 111 -Minimum 111 -Maximum 111) `
      -Name "fixture"
    $result.status | Should Be "fail"
  }

  It "requires a new zero when the historical median is zero" {
    (Compare-AnchorMetric `
      -HistoricalStatistics (New-AnchorStatistics -Median 0 -Minimum 0 -Maximum 0) `
      -CurrentStatistics (New-AnchorStatistics -Median 0 -Minimum 0 -Maximum 0) `
      -Name "zero").status | Should Be "pass"
    (Compare-AnchorMetric `
      -HistoricalStatistics (New-AnchorStatistics -Median 0 -Minimum 0 -Maximum 0) `
      -CurrentStatistics (New-AnchorStatistics -Median 0.001 -Minimum 0.001 -Maximum 0.001) `
      -Name "zero").status | Should Be "fail"
  }

  It "fails a null or incomplete metric" {
    (Compare-AnchorMetric -HistoricalStatistics $null -CurrentStatistics (New-AnchorStatistics) -Name "missing").status | Should Be "fail"
    $incomplete = [pscustomobject]@{ count = 3; median = $null; minimum = 9; maximum = 11 }
    (Compare-AnchorMetric -HistoricalStatistics (New-AnchorStatistics) -CurrentStatistics $incomplete -Name "missing").status | Should Be "fail"
  }
}

Describe "resident anchor comparison" {
  It "passes matching metrics, environment, and topology" {
    $result = Compare-ResidentAnchor -Historical (New-AnchorFixture) -Current (New-AnchorFixture) -Framework "slint"
    $result.status | Should Be "pass"
    $result.failedMetricCount | Should Be 0
    $result.topologyMatch | Should Be $true
    $result.environmentMatch | Should Be $true
  }

  It "allows one numeric failure to request one retry" {
    $current = New-AnchorFixture -Overrides @{ "workload400.cpuMachinePercent" = 20 }
    $result = Compare-ResidentAnchor -Historical (New-AnchorFixture) -Current $current -Framework "slint"
    $result.status | Should Be "fail"
    $result.failedMetricCount | Should Be 1
    $result.retryEligible | Should Be $true
  }

  It "does not allow retry for two numeric failures" {
    $current = New-AnchorFixture -Overrides @{
      "workload400.cpuMachinePercent" = 20
      "latency.showLatencyMs" = 20
    }
    $result = Compare-ResidentAnchor -Historical (New-AnchorFixture) -Current $current -Framework "slint"
    $result.failedMetricCount | Should Be 2
    $result.retryEligible | Should Be $false
  }

  It "fails exact topology mismatch without retry" {
    $result = Compare-ResidentAnchor `
      -Historical (New-AnchorFixture) `
      -Current (New-AnchorFixture -MainWidth 999) `
      -Framework "slint"
    $result.topologyMatch | Should Be $false
    $result.retryEligible | Should Be $false
    $result.status | Should Be "fail"
  }

  It "fails an environment identity mismatch without retry" {
    $result = Compare-ResidentAnchor `
      -Historical (New-AnchorFixture) `
      -Current (New-AnchorFixture -PowerPlan "different-plan") `
      -Framework "slint"
    $result.environmentMatch | Should Be $false
    $result.retryEligible | Should Be $false
    $result.status | Should Be "fail"
  }
}

Describe "anchor comparison command" {
  It "writes an audit and returns deterministic pass, retry, and failure exit codes" {
    $historicalPath = Join-Path $TestDrive "historical.json"
    $historical = New-AnchorFixture
    $historical | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $historicalPath -Encoding utf8
    $command = Join-Path $PSScriptRoot "..\compare-anchor.ps1"
    $pwsh = @(Get-Command pwsh -CommandType Application)[0].Source
    $cases = @(
      [pscustomobject]@{ Name = "pass"; Current = New-AnchorFixture; ExitCode = 0 },
      [pscustomobject]@{
        Name = "retry"
        Current = New-AnchorFixture -Overrides @{ "workload400.cpuMachinePercent" = 20 }
        ExitCode = 2
      },
      [pscustomobject]@{
        Name = "fail"
        Current = New-AnchorFixture -Overrides @{
          "workload400.cpuMachinePercent" = 20
          "latency.showLatencyMs" = 20
        }
        ExitCode = 1
      }
    )

    foreach ($case in $cases) {
      $currentPath = Join-Path $TestDrive "$($case.Name)-current.json"
      $outputPath = Join-Path $TestDrive "$($case.Name)-audit.json"
      $case.Current | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $currentPath -Encoding utf8
      $null = & $pwsh -NoLogo -NoProfile -File $command `
        -HistoricalPath $historicalPath `
        -CurrentPath $currentPath `
        -Framework "slint" `
        -OutputPath $outputPath
      $exitCode = $LASTEXITCODE

      $exitCode | Should Be $case.ExitCode
      Test-Path -LiteralPath $outputPath | Should Be $true
      $audit = Get-Content -LiteralPath $outputPath -Raw -Encoding utf8 | ConvertFrom-Json
      $audit.comparison.status | Should Be $(if ($case.ExitCode -eq 0) { "pass" } else { "fail" })
    }
  }
}
