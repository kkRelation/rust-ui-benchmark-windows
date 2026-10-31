$libraryPath = Join-Path $PSScriptRoot "..\framework-run-lib.ps1"
. $libraryPath

function New-FrameworkResultFixture {
  param(
    [string]$Root = $TestDrive,
    [string]$Framework = "iced",
    [int]$Rounds = 3
  )

  $artifactDirectory = Join-Path $Root "durable-artifacts"
  New-Item -ItemType Directory -Force -Path $artifactDirectory | Out-Null
  $phase = [pscustomobject]@{
    processCount = 1
    rendererCount = 0
    privateWorkingSetMb = 10
    cpuMachinePercent = 1
    gpuEngineAveragePercent = 2
    dedicatedGpuPeakMb = 3
    sharedGpuPeakMb = 4
  }
  function New-FixtureWindows {
    param([bool]$Visible)
    @(
      [pscustomobject]@{ Title = "UI Framework Bench - Auxiliary Canvas"; Visible = $Visible; Width = 1215; Height = 794 },
      [pscustomobject]@{ Title = "UI Framework Bench - Main"; Visible = $Visible; Width = 715; Height = 514 }
    )
  }
  $runs = @(
    for ($round = 1; $round -le $Rounds; $round++) {
      $eventLog = Join-Path $artifactDirectory "round-$round-events.jsonl"
      '{"event":"quit"}' | Set-Content -LiteralPath $eventLog -Encoding utf8
      [pscustomobject]@{
        framework = $Framework
        round = $round
        status = "ok"
        eventLog = $eventLog
        executableSha256 = "a" * 64
        lockfileSha256 = "b" * 64
        phases = [pscustomobject]@{
          hiddenIdle = $phase; visibleIdle = $phase; workload400 = $phase
          postHideIdle = $phase; postCycleIdle = $phase
        }
        topology = [pscustomobject]@{
          hidden = @(New-FixtureWindows $false)
          visible = @(New-FixtureWindows $true)
          postHide = @(New-FixtureWindows $false)
          postCycle = @(New-FixtureWindows $false)
        }
      }
    }
  )
  $summaryPhases = @(
    foreach ($name in @("hiddenIdle", "visibleIdle", "workload400", "postHideIdle", "postCycleIdle")) {
      [pscustomobject]@{
        framework = $Framework
        phase = $name
        metrics = [pscustomobject]@{
          privateWorkingSetMb = [pscustomobject]@{ count = $Rounds; median = 10; minimum = 9; maximum = 11 }
        }
      }
    }
  )
  [pscustomobject]@{
    protocol = [pscustomobject]@{
      resident = $true
      windows = 2
      mainContentSize = "700x480"
      auxiliaryContentSize = "1200x760"
      workload = "400 shared-state updates at 20 ms"
      phases = @("hiddenIdle", "warmShow", "visibleIdle", "workload400", "warmHide", "postHideIdle", "cycle30", "postCycleIdle")
      sampleSeconds = if ($Rounds -eq 1) { 1 } else { 10 }
      postHideSettleSeconds = if ($Rounds -eq 1) { 1 } else { 15 }
      cycleCount = if ($Rounds -eq 1) { 2 } else { 30 }
      rounds = $Rounds
      smoke = $Rounds -eq 1
    }
    toolchain = [pscustomobject]@{ rustcVerbose = "rustc fixture"; cargoVersion = "cargo fixture" }
    runs = $runs
    summary = [pscustomobject]@{
      phases = $summaryPhases
      latency = @([pscustomobject]@{
        framework = $Framework
        showLatencyMs = [pscustomobject]@{ count = $Rounds; median = 10; minimum = 9; maximum = 11 }
        hideLatencyMs = [pscustomobject]@{ count = $Rounds; median = 10; minimum = 9; maximum = 11 }
      })
    }
  }
}

Describe "framework result validation" {
  It "accepts exactly three complete successful durable rounds" {
    $result = New-FrameworkResultFixture
    $validation = Test-FrameworkResult -Result $result -Framework "iced" -ExpectedRounds 3
    $validation.Valid | Should Be $true
    $validation.Errors.Count | Should Be 0
  }

  It "collects round, phase, artifact, hash, toolchain, and failure errors" {
    $result = New-FrameworkResultFixture
    $result.runs[0].phases.workload400 = $null
    $result.runs[0].eventLog = Join-Path $TestDrive ".benchmark-work\iced\events.jsonl"
    $result.runs[0].executableSha256 = $null
    $result.runs[1].round = 1
    $result.runs[2].status = "failed"
    $result.toolchain.cargoVersion = ""
    $result.protocol.cycleCount = 999

    $validation = Test-FrameworkResult -Result $result -Framework "iced" -ExpectedRounds 3
    $errors = $validation.Errors -join "`n"
    $validation.Valid | Should Be $false
    $errors | Should Match "distinct successful rounds"
    $errors | Should Match "failed run"
    $errors | Should Match "workload400"
    $errors | Should Match "outside .benchmark-work"
    $errors | Should Match "executableSha256"
    $errors | Should Match "cargoVersion"
    $errors | Should Match "protocol.cycleCount"
  }

  It "requires both exact window titles at every topology checkpoint" {
    $result = New-FrameworkResultFixture
    $result.runs[0].topology.visible[1].Title = "Wrong title"
    $validation = Test-FrameworkResult -Result $result -Framework "iced" -ExpectedRounds 3
    $validation.Valid | Should Be $false
    ($validation.Errors -join "`n") | Should Match "topology.visible"
  }

  It "requires event logs to exist" {
    $result = New-FrameworkResultFixture
    $result.runs[0].eventLog = Join-Path $TestDrive "missing-events.jsonl"
    $validation = Test-FrameworkResult -Result $result -Framework "iced" -ExpectedRounds 3
    $validation.Valid | Should Be $false
    ($validation.Errors -join "`n") | Should Match "does not exist"
  }
}

Describe "single-framework orchestration" {
  BeforeEach {
    $script:orchestrationCalls = @()
    Mock Ensure-BenchmarkWindowsIgnoredByKomorebi {
      $script:orchestrationCalls += "window-manager"
      [pscustomobject]@{ manager = "komorebi"; active = $true; verified = $true; addedRules = @() }
    }
    Mock Enter-BenchmarkScreenpipeIsolation {
      $script:orchestrationCalls += "screenpipe-stop"
      [pscustomobject]@{ wasRunning = $true; stoppedProcessCount = 1; launches = @() }
    }
    Mock Exit-BenchmarkScreenpipeIsolation {
      $script:orchestrationCalls += "screenpipe-restore"
      [pscustomobject]@{ required = $true; startedProcessCount = 1; healthy = $true }
    }
    Mock New-BenchmarkFrameworkWorkspace {
      $script:orchestrationCalls += "workspace"
      [pscustomobject]@{
        Root = Join-Path $TestDrive ".benchmark-work\iced"
        CargoHome = Join-Path $TestDrive ".benchmark-work\iced\cargo-home"
        TargetDirectory = Join-Path $TestDrive ".benchmark-work\iced\target"
        FreeBytesBefore = 1000
      }
    }
    Mock Invoke-BenchmarkFrameworkBuild {
      $script:orchestrationCalls += "build-$Configuration"
    }
    Mock Invoke-BenchmarkFrameworkMeasurement {
      if ($Smoke) {
        $script:orchestrationCalls += "measure-smoke"
        New-FrameworkResultFixture -Framework $Framework -Rounds 1
      } else {
        $script:orchestrationCalls += "measure-release"
        New-FrameworkResultFixture -Framework $Framework -Rounds 3
      }
    }
    Mock Invoke-BenchmarkResultValidation {
      $script:orchestrationCalls += "validate-$ExpectedRounds"
      [pscustomobject]@{ Valid = $true; Errors = @() }
    }
    Mock Invoke-BenchmarkAnchorComparison {
      $script:orchestrationCalls += "anchor"
      [pscustomobject]@{ status = "pass"; retryEligible = $false; failedMetricCount = 0 }
    }
    Mock Remove-BenchmarkFrameworkWorkspace {
      $script:orchestrationCalls += "cleanup"
      [pscustomobject]@{ RemovedPath = $Path; RecoveredBytes = 100 }
    }
  }

  It "runs build, smoke, release, validation, anchor, and cleanup in order" {
    $null = Invoke-BenchmarkFrameworkRun `
      -RepoRoot $TestDrive `
      -Framework "slint" `
      -OutputDirectory (Join-Path $TestDrive "output") `
      -Anchor `
      -HistoricalPath (Join-Path $TestDrive "historical.json")

    $script:orchestrationCalls | Should Be @(
      "window-manager", "workspace", "build-debug", "screenpipe-stop", "measure-smoke",
      "validate-1", "build-release", "measure-release", "validate-3", "anchor",
      "screenpipe-restore", "cleanup"
    )
  }

  It "uses a safe explicit label for retry artifacts" {
    $output = Join-Path $TestDrive "labelled"
    $null = Invoke-BenchmarkFrameworkRun `
      -RepoRoot $TestDrive `
      -Framework "iced" `
      -OutputDirectory $output `
      -Label "iced-unmanaged-attempt-2" `
      -KeepWorkdir
    Test-Path -LiteralPath (Join-Path $output "iced-unmanaged-attempt-2-status.json") | Should Be $true
    $threw = $false
    try {
      $null = Invoke-BenchmarkFrameworkRun `
        -RepoRoot $TestDrive `
        -Framework "iced" `
        -OutputDirectory $output `
        -Label "..\unsafe"
    } catch { $threw = $true }
    $threw | Should Be $true
  }

  It "keeps the workspace after a build failure" {
    Mock Invoke-BenchmarkFrameworkBuild { throw "build failure" }
    $threw = $false
    try {
      $null = Invoke-BenchmarkFrameworkRun -RepoRoot $TestDrive -Framework "iced" -OutputDirectory (Join-Path $TestDrive "build-failure")
    } catch { $threw = $true }
    $threw | Should Be $true
    Assert-MockCalled Remove-BenchmarkFrameworkWorkspace -Times 0 -Scope It
    Test-Path -LiteralPath (Join-Path $TestDrive "build-failure\iced-status.json") | Should Be $true
  }

  It "keeps the workspace after a measurement failure" {
    Mock Invoke-BenchmarkFrameworkMeasurement { throw "measurement failure" }
    try {
      $null = Invoke-BenchmarkFrameworkRun -RepoRoot $TestDrive -Framework "iced" -OutputDirectory (Join-Path $TestDrive "measurement-failure")
    } catch {}
    Assert-MockCalled Remove-BenchmarkFrameworkWorkspace -Times 0 -Scope It
    Assert-MockCalled Exit-BenchmarkScreenpipeIsolation -Times 1 -Scope It
  }

  It "keeps the workspace after validation failure" {
    Mock Invoke-BenchmarkResultValidation { [pscustomobject]@{ Valid = $false; Errors = @("invalid fixture") } }
    try {
      $null = Invoke-BenchmarkFrameworkRun -RepoRoot $TestDrive -Framework "iced" -OutputDirectory (Join-Path $TestDrive "validation-failure")
    } catch {}
    Assert-MockCalled Remove-BenchmarkFrameworkWorkspace -Times 0 -Scope It
  }

  It "keeps the workspace after anchor failure" {
    Mock Invoke-BenchmarkAnchorComparison {
      [pscustomobject]@{ status = "fail"; retryEligible = $true; failedMetricCount = 1 }
    }
    try {
      $null = Invoke-BenchmarkFrameworkRun `
        -RepoRoot $TestDrive `
        -Framework "slint" `
        -OutputDirectory (Join-Path $TestDrive "anchor-failure") `
        -Anchor `
        -HistoricalPath (Join-Path $TestDrive "historical.json")
    } catch {}
    Assert-MockCalled Remove-BenchmarkFrameworkWorkspace -Times 0 -Scope It
  }

  It "skips cleanup when KeepWorkdir is selected" {
    $null = Invoke-BenchmarkFrameworkRun `
      -RepoRoot $TestDrive `
      -Framework "iced" `
      -OutputDirectory (Join-Path $TestDrive "keep") `
      -KeepWorkdir
    Assert-MockCalled Remove-BenchmarkFrameworkWorkspace -Times 0 -Scope It
  }
}
